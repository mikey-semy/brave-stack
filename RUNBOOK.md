# RUNBOOK — поднятие brave-stack на сервере с нуля

Порядок развёртывания всей сборки на чистом Linux-сервере, **включая ручные шаги**,
которых нет в compose. Для восстановления данных см. [backup/RESTORE.md](backup/RESTORE.md).

> Проверялось на Debian 13, 1 vCPU / 2 ГБ. Адреса и домены ниже — примеры
> (`example.ru`, RFC-5737-адрес): подставляй свои.

---

## 0. Предпосылки
- Linux-сервер (Debian/Ubuntu), root-доступ.
- Открытые наружу порты: **21115–21119/tcp, 21116/udp** (RustDesk), **80, 443/tcp** (Caddy/TLS).
  На brave ufw включён (см. §7): открыты 22, 80, 443, 21115–21119/tcp, 21116/udp
  и 10050/tcp только с трёх адресов заббикса хостера. Если ufw ставится с нуля:
  `ufw allow 21115:21119/tcp && ufw allow 21116/udp && ufw allow 80,443/tcp`.
- DNS: A-запись поддомена Vaultwarden → IP сервера (напр. `vault.example.ru → 203.0.113.10`).
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
bash setup-backup.sh   # rclone remote + проверка бакета + cron + первый бэкап
```
`BACKUP_PATHS` — все data-каталоги с ценным:
```
BACKUP_PATHS="/root/brave-stack/rustdesk/data /root/brave-stack/vaultwarden/data /root/brave-stack/ntfy/data /root/brave-stack/uptime-kuma/data /root/brave-stack/wallos/data"
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

> **Проверять надо обе стороны, и вот почему.** Ключ на сервере обесценивает
> шифрование: кто получил root, тот прочитал все копии, включая сейф с паролями.
> Но и единственная копия на одном диске — не хранение: потеряли диск, и бэкапы
> нечитаемы навсегда. Правильное состояние: **на сервере только публичный ключ, а
> приватный — минимум в двух местах, и ни одно из них не сервер и не машина,
> которую он обслуживает.** Проверка: `gpg --list-secret-keys` на сервере должен
> молчать.

## 6. Проверка
```bash
docker ps                                   # hbbs, hbbr, caddy, vaultwarden — Up
rclone lsl backup:<бакет>/brave             # копии в облаке с датами
crontab -l                                  # строка backup.sh (на brave — 05:00)
```

---

## 7. Базовая безопасность
```bash
apt-get install -y ufw fail2ban
# firewall: всё закрыто, кроме нужного. SSH РАЗРЕШИТЬ ПЕРВЫМ!
ufw default deny incoming; ufw default allow outgoing
ufw allow 22/tcp                              # SSH (иначе запрёшь себя!)
ufw allow 80/tcp; ufw allow 443/tcp           # Caddy
ufw allow 21115:21119/tcp; ufw allow 21116/udp # RustDesk
# zabbix-агент хостера (если есть) — только с его IP (см. Server= в zabbix_agentd.conf):
# ufw allow from <zbx_ip> to any port 10050 proto tcp
ufw --force enable
```
> На проде включай с предохранителем (на случай ошибки в правилах):
> `nohup bash -c 'sleep 180 && ufw --force disable' & ; ufw --force enable`
> затем проверь НОВЫМ ssh-подключением и сними: `pkill -f 'ufw --force disable'`.

fail2ban (защита SSH; Debian 13 — журнал systemd, не /var/log/auth.log):
```bash
cat > /etc/fail2ban/jail.d/sshd.local <<'J'
[sshd]
enabled = true
backend = systemd
maxretry = 5
bantime = 1h
J
systemctl enable --now fail2ban
```
SSH — только по ключу (`PasswordAuthentication no` в sshd_config). Автообновления:
`unattended-upgrades` + `/etc/apt/apt.conf.d/20auto-upgrades`.

## Если разворачивали не по этому порядку

Бывает, что сервер поднимали раньше документа: файлы доставлены через `scp`, а
рабочая копия git осталась на старом коммите. Тогда `git pull` **не пройдёт** —
git откажется перезаписывать неотслеживаемые файлы, и обновление молча встанет.

Разовая починка, без остановки сервисов:

```bash
git fetch && git stash -u && git reset --hard origin/master
```

`.env` и `backup/backup.env` в `.gitignore` — не пострадают, но сверьте их после.
