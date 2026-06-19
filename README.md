# brave-stack 🦊

Сборка self-hosted сервисов для сервера **brave** (89.23.101.7).
*Brave* — «отважный», Vulpecula — созвездие «Лисичка».

Монорепозиторий: каждый сервис в своей папке со своими двумя compose
(standalone + Dokploy), а в корне — **общая сборка**, которая через `include`
поднимает все сервисы сразу. Накатывается на любой сервер: `git clone` + `up`.

## Сервисы

| Папка | Что | Статус |
|-------|-----|--------|
| [rustdesk/](rustdesk/) | RustDesk (hbbs+hbbr) — self-hosted удалёнка, аналог AnyDesk | ✅ работает |
| [backup/](backup/) | Off-site бэкапы (S3/B2) + переезд (`RESTORE.md`) | ✅ работает |
| [caddy/](caddy/) | общий reverse-proxy + авто-TLS (Let's Encrypt) | ✅ готово |
| [vaultwarden/](vaultwarden/) | менеджер паролей (Bitwarden) | ✅ работает (brave.equiply.ru) |
| [ntfy/](ntfy/) | пуш-уведомления | ✅ готово, нужен домен |

## Структура

```
brave-stack/
├── docker-compose.yml            # ОБЩАЯ сборка всех сервисов (standalone)
├── docker-compose.dokploy.yml    # ОБЩАЯ сборка для Dokploy
├── .env.example                  # общий конфиг (RELAY_HOST и пр.)
├── rustdesk/
│   ├── docker-compose.yml         # ← свой standalone
│   ├── docker-compose.dokploy.yml # ← свой Dokploy
│   ├── init.sh · deploy.sh · README.md · DEPLOY.md
├── backup/                        # серверный бэкап-кит (скрипты, не сервис)
└── README.md
```

Корневые compose ничего не дублируют — только `include` per-app файлов.
Добавляешь сервис → создаёшь папку с двумя compose → дописываешь две строки
`include` в корневые файлы.

## Запуск

### Вся сборка сразу (standalone)
```bash
git clone git@github.com:mikey-semy/brave-stack.git
cd brave-stack
cp .env.example .env && nano .env      # RELAY_HOST = IP/домен сервера
docker compose up -d                   # поднимет все сервисы из include
```

### Один сервис отдельно
```bash
cd brave-stack/rustdesk
cp .env.example .env && nano .env
docker compose up -d
```
> Запускай из папки сервиса — тогда подхватится его `.env`. (Из корня корневой
> `.env` для одиночного `-f rustdesk/...` не подхватится — нужен `--env-file .env`.)

Или см. README конкретного сервиса (напр. [rustdesk/README.md](rustdesk/README.md)
с автодеплоем `deploy.sh`).

### Через Dokploy
Тип сервиса **Docker Compose**, файл `docker-compose.dokploy.yml` (вся сборка)
или `rustdesk/docker-compose.dokploy.yml` (один сервис). `RELAY_HOST` и прочее —
во вкладке **Environment**.

## Поднятие с нуля и переезд

- **[RUNBOOK.md](RUNBOOK.md)** — полный порядок развёртывания всей сборки на чистом
  сервере, включая ручные шаги (пакеты, сеть, env, TLS, бэкапы) и грабли.
- **[backup/RESTORE.md](backup/RESTORE.md)** — восстановление данных из off-site бэкапов.

Сервер временный → всё ценное уезжает off-site в S3/B2, инфра — в этом репо.

## Текущий деплой

Развёрнут на `brave` (89.23.101.7, `ssh brave`). Параметры RustDesk-клиентов и
прочие детали — в [rustdesk/README.md](rustdesk/README.md).
