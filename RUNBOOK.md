# RUNBOOK — поднятие brave-stack на сервере с нуля

Порядок развёртывания всей сборки на чистом Linux-сервере, **включая ручные шаги**,
которых нет в compose. Для восстановления данных см. [backup/RESTORE.md](backup/RESTORE.md).

> Текущий прод — сервер **brave** (89.23.101.7, `ssh brave`, Debian 13, 1 vCPU / 1.9 ГБ).
> Особенности его текущего состояния — в конце, в разделе «Состояние brave».

---

## 0. Предпосылки
- Linux-сервер (Debian/Ubuntu), root-доступ.
- Открытые наружу порты: **21115–21119/tcp, 21116/udp** (RustDesk), **80, 443/tcp** (Caddy/TLS).
  На brave фаервола (ufw) нет — порты открыты на уровне провайдера. Если есть ufw:
  `ufw allow 21115:21119/tcp && ufw allow 21116/udp && ufw allow 80,443/tcp`.
- DNS: A-запись поддомена Vaultwarden → IP сервера (напр. `brave.equiply.ru → 89.23.101.7`).
  Если домен на Cloudflare — режим «DNS only» (серое облако), иначе ломается TLS-ALPN.

## 1. Системные пакеты (Debian 13 их НЕ ставит по умолчанию!)
```bash
# Docker
curl -fsSL https://get.docker.com | sh
# rclone (для бэкапов) и cron — на чистой Debian 13 ОТСУТСТВУЮТ
apt-get update && apt-get install -y rclone cron unzip
systemctl enable --now docker cron
```
> `unzip` нужен, если ставить rclone скриптом с rclone.org; через apt — не обязателен,
> но пусть будет. Без `cron` не встанет расписание бэкапов.

## 2. Репозиторий
```bash
cd /root
git clone https://github.com/mikey-semy/brave-stack.git
cd brave-stack
cp .env.example .env
nano .env     # RELAY_HOST=<IP>, VW_DOMAIN=<поддомен>, VW_SIGNUPS_ALLOWED=true (пока)
```

## 3. RustDesk
```bash
cd /root/brave-stack
docker compose -f rustdesk/docker-compose.yml up -d
# ключ для клиентов:
docker logs rustdesk-init 2>&1 | tail        # ID / Relay / Key
# либо: cat rustdesk/data/id_ed25519.pub
```
В клиентах (⋮ → Network): ID Server = IP, Key = из вывода выше.

## 4. Caddy + Vaultwarden (общий reverse-proxy + TLS)
```bash
cd /root/brave-stack
docker network create brave-web                  # общая сеть, ОДИН раз
# Vaultwarden, затем Caddy (Caddy сам получит сертификат Let's Encrypt):
cd vaultwarden && docker compose --env-file /root/brave-stack/.env up -d && cd ..
cd caddy       && docker compose --env-file /root/brave-stack/.env up -d && cd ..
docker logs caddy 2>&1 | grep -i "certificate obtained"   # дождаться выпуска TLS
```
Проверка: `curl -I https://VW_DOMAIN` → 200.

**Создание аккаунта и закрытие регистрации:**
1. С `VW_SIGNUPS_ALLOWED=true` зайти на `https://VW_DOMAIN`, зарегистрироваться.
2. В `.env` поставить `VW_SIGNUPS_ALLOWED=false`, передеплой:
   `cd vaultwarden && docker compose --env-file /root/brave-stack/.env up -d`

> Caddyfile/.env, отредактированные в Windows, приносят CRLF — почистить:
> `sed -i 's/\r//g' .env caddy/Caddyfile`

## 4b. ntfy (пуш-уведомления, тоже за Caddy)
A-запись `NTFY_DOMAIN → IP`, в `.env` задать `NTFY_DOMAIN`. Caddyfile уже содержит
блок ntfy. Затем:
```bash
cd /root/brave-stack
cd ntfy && docker compose --env-file /root/brave-stack/.env up -d && cd ..
# перевыпустить caddy, чтобы подхватил NTFY_DOMAIN + новый блок Caddyfile:
cd caddy && docker compose --env-file /root/brave-stack/.env up -d && cd ..
# приватный сервер — создать пользователя:
docker exec -e NTFY_PASSWORD='ПАРОЛЬ' ntfy ntfy user add --role=admin mike
```
Проверка: `curl -u mike:ПАРОЛЬ -d test https://NTFY_DOMAIN/test`.

## 4c. Uptime Kuma (мониторинг, тоже за Caddy)
A-запись `KUMA_DOMAIN → IP`, в `.env` задать `KUMA_DOMAIN`. Caddyfile содержит блок kuma.
```bash
cd /root/brave-stack
cd uptime-kuma && docker compose --env-file /root/brave-stack/.env up -d && cd ..
cd caddy && docker compose --env-file /root/brave-stack/.env up -d && cd ..
```
Дальше в веб-UI (`https://KUMA_DOMAIN`): создать админа, добавить ntfy-уведомление
и мониторы на сервисы. См. uptime-kuma/README.md.

## 5. Бэкапы (off-site, Selectel S3 / любой S3 / B2)
```bash
cd /root/brave-stack/backup
cp backup.env.example backup.env
nano backup.env     # PROVIDER=s3, S3_*, RCLONE_REMOTE, BACKUP_PATHS (см. ниже), GPG_RECIPIENT
bash setup-backup.sh   # rclone remote + проверка бакета + cron 03:00 + первый бэкап
```
`BACKUP_PATHS` — все data-каталоги с ценным:
```
BACKUP_PATHS="/root/brave-stack/rustdesk/data /root/brave-stack/vaultwarden/data /root/brave-stack/ntfy/data /root/brave-stack/uptime-kuma/data"
```
Selectel: `PROVIDER=s3`, `S3_ENDPOINT=https://s3.ru-3.storage.selcloud.ru`, регион `ru-3`,
бакет с точкой (`brave.data`) → скрипт включает `force_path_style` автоматически.

**GPG-шифрование (обязательно, т.к. в бэкапе сейф Vaultwarden):**
```bash
gpg --quick-generate-key "brave-backup" default default never
gpg --list-keys                       # взять fingerprint/email -> GPG_RECIPIENT в backup.env
gpg --armor --export-secret-keys <key> > brave-backup-private.asc
```
⚠️ `brave-backup-private.asc` СКАЧАТЬ и хранить ОФЛАЙН/ОТДЕЛЬНО от сервера, затем удалить
с сервера приватный ключ (оставить только публичный — им шифруется). Без приватного
ключа восстановление невозможно (by design).

## 6. Проверка
```bash
docker ps                                   # hbbs, hbbr, caddy, vaultwarden — Up
rclone lsl backup:<бакет>/brave             # копии в облаке с датами
crontab -l                                  # строка backup.sh 03:00
```

---

## Состояние brave (важные отклонения от идеала)
- Сервер развёрнут в каталоге **`/root/remote-app`** (старое имя), НЕ мигрирован на
  раскладку `brave-stack`. Поэтому реальные пути там:
  - RustDesk данные: `/root/remote-app/data` (а не `rustdesk/data`)
  - Caddy/Vaultwarden: `/root/remote-app/{caddy,vaultwarden}` (доставлены через scp)
  - `BACKUP_PATHS=/root/remote-app/data` (Vaultwarden ещё предстоит добавить)
  - env бэкапов: `/root/remote-app/backup/backup.env`
- RustDesk крутится со старого compose (host-режим), миграцию на монорепо-раскладку
  откладывали, чтобы не ронять рабочий сервис.
- Новый сервер поднимать по шагам выше (чистая `brave-stack`-раскладка) — это целевой вид.
