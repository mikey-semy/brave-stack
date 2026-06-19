# ntfy — пуш-уведомления

Часть сборки [brave-stack](../README.md). Self-hosted сервис уведомлений: шлёшь
HTTP-запрос → тебе на телефон/в браузер прилетает пуш. Доступ по HTTPS через
[Caddy](../caddy/). Приватный (deny-all + пользователь).

## Предусловия
1. A-запись поддомена → IP сервера (напр. `ntfy.example.ru` → 89.23.101.7).
2. Сеть `brave-web` (одна на сборку): `docker network create brave-web`.
3. В корневом `.env`: `NTFY_DOMAIN`.

## Запуск
```bash
cd brave-stack/ntfy
docker compose --env-file ../.env up -d
# создать своего пользователя (приватный сервер):
docker exec -e NTFY_PASSWORD='ПАРОЛЬ' ntfy ntfy user add --role=admin mike
```

## Использование
**Отправить уведомление** (с логином/паролем или токеном):
```bash
curl -u mike:ПАРОЛЬ -d "Бэкап готов ✅" https://NTFY_DOMAIN/backups
```
**Получать**: приложение ntfy (iOS/Android) или браузер → добавить сервер
`https://NTFY_DOMAIN`, войти, подписаться на топик (напр. `backups`).

Токен для скриптов (вместо пароля):
```bash
docker exec ntfy ntfy token add mike       # выдаст tk_... ; слать: -H "Authorization: Bearer tk_..."
```

## iOS
Мгновенные пуши на iPhone идут через `ntfy.sh` как APNs-«будильник»
(`NTFY_UPSTREAM_BASE_URL=https://ntfy.sh`) — это требование Apple, иначе пуши
приходят с задержкой. Уже настроено в compose.

## Бэкап
`ntfy/data` (user.db) добавляется в `BACKUP_PATHS` (см. [../backup/](../backup/)).
`ntfy/cache` бэкапить не нужно — эфемерный.

## Применение
Алерты бэкапов, «сервер недоступен» (с Uptime Kuma), вход по SSH, события cron/скриптов.
