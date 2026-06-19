#!/bin/sh
# Одноразовый init-шаг. Запускается автоматически при каждом `docker compose up`
# (т.е. при каждом деплое в Dokploy). Дожидается, пока hbbs сгенерит ключ,
# и печатает готовые параметры для клиентов прямо в лог.
set -e

echo "[init] Жду генерацию ключа hbbs..."
i=0
while [ ! -f /data/id_ed25519.pub ] && [ "$i" -lt 30 ]; do
  i=$((i + 1))
  sleep 1
done

echo "=================================================================="
if [ -f /data/id_ed25519.pub ]; then
  echo "[init] RustDesk готов. Параметры для клиентов (⋮ → Network):"
  echo
  echo "    ID Server : ${RELAY_HOST:-<задай RELAY_HOST в Environment>}"
  echo "    Relay     : ${RELAY_HOST:-<задай RELAY_HOST в Environment>}"
  echo "    Key       : $(cat /data/id_ed25519.pub)"
else
  echo "[init] Ключ ещё не появился — проверь логи сервиса hbbs."
fi
echo "=================================================================="
