#!/usr/bin/env bash
#
# RustDesk self-hosted — автодеплой «под ключ».
# Ставит Docker (если нет), пишет .env, открывает firewall, поднимает hbbs+hbbr
# и в конце печатает готовые параметры для клиентов (включая публичный ключ).
#
# Запуск на Linux-сервере (root / sudo):
#   sudo ./deploy.sh                 # RELAY_HOST определится по публичному IP
#   sudo ./deploy.sh my.domain.com   # или явно укажи IP/домен
#   sudo RELAY_HOST=1.2.3.4 ./deploy.sh
#
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
DATA_DIR="./data"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Нужны права root. Запусти: sudo ./deploy.sh"
    exit 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker уже есть ($(docker --version))"
  else
    log "Docker не найден — устанавливаю через get.docker.com..."
    curl -fsSL https://get.docker.com | sh
  fi

  if ! docker compose version >/dev/null 2>&1; then
    err "Нет плагина 'docker compose'. Установи docker-compose-plugin и повтори."
    exit 1
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
}

detect_ip() {
  local ip
  for svc in https://ifconfig.me https://api.ipify.org https://ipinfo.io/ip; do
    ip="$(curl -fsS --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')" || true
    if [ -n "${ip:-}" ]; then printf '%s' "$ip"; return 0; fi
  done
  return 1
}

setup_env() {
  RELAY_HOST="${RELAY_HOST:-${1:-}}"
  if [ -z "${RELAY_HOST}" ]; then
    log "RELAY_HOST не задан — определяю публичный IP..."
    RELAY_HOST="$(detect_ip)" || {
      err "Не смог определить IP. Передай вручную: sudo ./deploy.sh <IP|домен>"
      exit 1
    }
    log "Определён адрес сервера: ${RELAY_HOST}"
  fi
  echo "RELAY_HOST=${RELAY_HOST}" > .env
  log ".env записан (RELAY_HOST=${RELAY_HOST})"
}

setup_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "Открываю порты в ufw (21115-21119/tcp, 21116/udp)..."
    ufw allow 21115:21119/tcp >/dev/null
    ufw allow 21116/udp       >/dev/null
    log "Порты открыты"
  else
    warn "ufw не найден — открой порты вручную (в провайдере/iptables):"
    warn "    TCP 21115-21119 и UDP 21116 (udp обязателен!)"
  fi
}

deploy_stack() {
  mkdir -p "${DATA_DIR}"
  log "Тяну образы rustdesk-server..."
  docker compose -f "${COMPOSE_FILE}" pull
  log "Поднимаю сервисы..."
  docker compose -f "${COMPOSE_FILE}" up -d
}

show_result() {
  log "Жду генерацию ключа hbbs..."
  for _ in $(seq 1 20); do
    [ -f "${DATA_DIR}/id_ed25519.pub" ] && break
    sleep 1
  done

  echo
  echo "=================================================================="
  if [ -f "${DATA_DIR}/id_ed25519.pub" ]; then
    log "Готово! Вбей это в клиентах (⋮ → Network / ID-Relay Server):"
    echo
    echo "    ID Server : ${RELAY_HOST}"
    echo "    Relay     : ${RELAY_HOST}"
    echo "    Key       : $(cat "${DATA_DIR}/id_ed25519.pub")"
  else
    warn "Ключ ещё не сгенерился. Проверь логи: docker compose logs hbbs"
    warn "Позже забери ключ: cat ${DATA_DIR}/id_ed25519.pub"
  fi
  echo "=================================================================="
  echo
  docker compose -f "${COMPOSE_FILE}" ps
}

main() {
  require_root
  install_docker
  setup_env "${1:-}"
  setup_firewall
  deploy_stack
  show_result
}

main "$@"
