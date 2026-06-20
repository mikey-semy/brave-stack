# wallos — трекер подписок

Часть сборки [brave-stack](../README.md). Self-hosted учёт подписок/аренд: цены,
циклы, **авто-расчёт следующего платежа**, дашборд (итоги мес/год, разбивка),
мультивалюта с авто-курсами, уведомления (вкл. ntfy). Доступ по HTTPS через
[Caddy](../caddy/).

## Предусловия
1. A-запись поддомена → IP сервера (напр. `subs.example.ru` → 89.23.101.7).
2. Сеть `brave-web`: `docker network create brave-web`.
3. В корневом `.env`: `WALLOS_DOMAIN`.

## Запуск
```bash
cd brave-stack/wallos
docker compose --env-file ../.env up -d
cd ../caddy && docker compose --env-file ../.env up -d   # подхватить WALLOS_DOMAIN
```

## Первая настройка (в браузере)
1. `https://WALLOS_DOMAIN` → регистрация (логин/пароль → в Vaultwarden).
2. Settings → валюта по умолчанию RUB, включить авто-курсы.
3. Settings → Notifications → **ntfy**: URL `https://ntfy.equiply.ru`, topic `subs`,
   токен/логин mike. Включить напоминания о продлениях.
4. Завести подписки (см. данные в money/subscriptions.csv).

## Бэкап
`wallos/data` (db + логотипы) добавляется в `BACKUP_PATHS` (см. [../backup/](../backup/)).

## Связь с money-трекером
`money/subscriptions.csv` + `report.py` — были временным решением. Wallos —
основной UI. CSV можно оставить как резерв/экспорт.
