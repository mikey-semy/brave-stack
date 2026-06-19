# uptime-kuma — мониторинг доступности

Часть сборки [brave-stack](../README.md). Пингует сервисы и шлёт алерт (в т.ч. в
[ntfy](../ntfy/)), если что-то легло. Доступ по HTTPS через [Caddy](../caddy/).
Настраивается полностью в веб-UI.

## Предусловия
1. A-запись поддомена → IP сервера (напр. `status.example.ru` → 89.23.101.7).
2. Сеть `brave-web`: `docker network create brave-web`.
3. В корневом `.env`: `KUMA_DOMAIN`.

## Запуск
```bash
cd brave-stack/uptime-kuma
docker compose --env-file ../.env up -d
# Caddy перевыпустить, чтобы подхватил KUMA_DOMAIN:
cd ../caddy && docker compose --env-file ../.env up -d
```

## Первая настройка (в браузере)
1. Открой `https://KUMA_DOMAIN` — на первом входе создаётся **админ-аккаунт**
   (логин/пароль придумай, сохрани в Vaultwarden).
2. **Settings → Notifications → Add** → тип **ntfy**:
   - Server URL: `https://ntfy.equiply.ru`
   - Topic: `alerts` (или любой)
   - Auth: токен/логин mike (ntfy приватный)
3. **Add New Monitor** на каждый сервис:
   - Vaultwarden: HTTPS `https://brave.equiply.ru` (ожидать 200)
   - ntfy: HTTPS `https://ntfy.equiply.ru/v1/health`
   - RustDesk hbbs: TCP Port `89.23.101.7:21116`
   - RustDesk relay: TCP Port `89.23.101.7:21117`
   Прикрепи к каждому ntfy-уведомление.

## Бэкап
`uptime-kuma/data` (sqlite с мониторами/историей) добавляется в `BACKUP_PATHS`.
