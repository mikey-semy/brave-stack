# vaultwarden — менеджер паролей (Bitwarden-совместимый)

Часть сборки [brave-stack](../README.md). Self-hosted сервер Bitwarden: пароли,
2FA-коды, заметки, карты, вложения, passkeys — всё в зашифрованном сейфе на твоём
сервере. Пользуешься официальными приложениями Bitwarden.

Доступ только по HTTPS через [Caddy](../caddy/) (авто-TLS Let's Encrypt).

## Предусловия
1. **Домен/поддомен** с A-записью на IP сервера (напр. `vault.example.ru` → 89.23.101.7).
2. Общая docker-сеть (один раз на сервере): `docker network create brave-web`.
3. В корневом `.env`: `VW_DOMAIN`, `VW_SIGNUPS_ALLOWED`.

## Запуск (через общую сборку)
```bash
cd brave-stack
docker network create brave-web        # один раз
cp .env.example .env && nano .env      # VW_DOMAIN = твой поддомен
docker compose up -d                   # поднимет rustdesk + caddy + vaultwarden
```

## Создание своего аккаунта (и закрытие регистрации)
Регистрация по умолчанию выключена (`VW_SIGNUPS_ALLOWED=false`). Чтобы завести
свой аккаунт:
1. В `.env` выставь `VW_SIGNUPS_ALLOWED=true`, передеплой: `docker compose up -d`.
2. Открой `https://VW_DOMAIN`, зарегистрируйся (надёжный уникальный мастер-пароль!).
3. Верни `VW_SIGNUPS_ALLOWED=false`, снова `docker compose up -d`.

Теперь сервер закрыт: новые регистрации запрещены, входишь только ты.

## Клиенты
Официальные Bitwarden: расширения браузеров, приложения iOS/Android/Desktop.
В настройках сервера (Self-hosted) укажи `https://VW_DOMAIN` — и всё.

## Бэкап
`vaultwarden/data` содержит сейф с паролями → бэкапится **с GPG-шифрованием**
(см. [../backup/](../backup/), путь добавлен в `BACKUP_PATHS`). Приватный GPG-ключ
храни ОТДЕЛЬНО от сервера, иначе восстановление невозможно.

## Безопасность
- Мастер-пароль длинный, уникальный, нигде больше. Забыл → данные не вернуть (E2E).
- `/admin` включается только при заданном `VW_ADMIN_TOKEN`.
- Наружу торчит только Caddy (443); сам Vaultwarden порты не публикует.
