# remote-app — собственная инфраструктура RustDesk

Self-hosted remote desktop на базе [RustDesk](https://github.com/rustdesk/rustdesk):
свой сервер, свои ключи, без лицензионных ограничений. Аналог AnyDesk/TeamViewer,
где весь трафик идёт **только через твою машину**, а не через чужое облако.

Работает между **Windows ⇄ macOS ⇄ Linux**, с **iPhone/Android в роли пульта**.

## Что внутри

| Файл | Назначение |
|------|-----------|
| [deploy.sh](deploy.sh) | **Автодеплой «под ключ»**: ставит Docker, firewall, поднимает всё, печатает ключ |
| [docker-compose.yml](docker-compose.yml) | Два сервиса: `hbbs` (брокер) + `hbbr` (relay), host-режим |
| [docker-compose.dokploy.yml](docker-compose.dokploy.yml) | Вариант для Dokploy: проброс портов + `dokploy-network` |
| [.env.example](.env.example) | Шаблон конфига — сюда вписываешь IP/домен VPS |
| [DEPLOY.md](DEPLOY.md) | Пошаговый ручной деплой, firewall, выдача ключа |
| [.gitignore](.gitignore) | Исключает секреты (`data/`, `.env`) из git |

## Архитектура

```
┌──────────┐        регистрация / heartbeat        ┌──────────┐
│ Клиент A │ ───────────────────────────────────►  │   hbbs   │
│  (Win)   │ ◄───── брокеринг соединения ────────   │ (брокер) │
└────┬─────┘                                        └──────────┘
     │  P2P (прямое) — если NAT позволяет
     │  ─────────────────────────────────►  ┌──────────┐
     │  fallback, если P2P не удался         │   hbbr   │
     └────────────────────────────────────► │ (relay)  │
                                             └──────────┘
                  твой VPS
```

- **hbbs** — регистрирует устройства, тестирует NAT, сводит клиентов. Лёгкий, работает всегда.
- **hbbr** — проксирует видеопоток, **только** когда прямой P2P не удался. Основной потребитель трафика.

## Быстрый старт (автодеплой)

Один скрипт делает всё: ставит Docker, открывает порты, поднимает сервисы
и печатает готовые параметры для клиентов.

```bash
# на Linux-сервере
git clone https://github.com/mikey-semy/remote-app.git
cd remote-app
sudo ./deploy.sh                 # RELAY_HOST определится по публичному IP
# или явно:
sudo ./deploy.sh my.domain.com
```

В конце скрипт выведет `ID Server`, `Relay` и `Key` — это всё, что нужно вбить в клиентах.

### Ручной запуск (без скрипта)

```bash
cp .env.example .env && nano .env      # впиши RELAY_HOST = IP/домен VPS
ufw allow 21115:21119/tcp && ufw allow 21116/udp && ufw reload
docker compose up -d
cat data/id_ed25519.pub                # публичный ключ для клиентов
```

Подробности, troubleshooting и обслуживание — в [DEPLOY.md](DEPLOY.md).

## Деплой через Dokploy

Используй [docker-compose.dokploy.yml](docker-compose.dokploy.yml) (тип сервиса
**Docker Compose**). Отличия от основного compose: проброс портов вместо
host-режима и подключение к `dokploy-network`.

1. Создай в Dokploy сервис типа **Docker Compose**, укажи этот репозиторий
   и путь к `docker-compose.dokploy.yml`.
2. Во вкладке **Environment** задай `RELAY_HOST=<IP/домен сервера>`.
3. Открой на сервере порты **21115–21119/tcp** и **21116/udp**.
4. Деплой. Ключ забери после старта:
   `docker exec hbbs cat /root/id_ed25519.pub` (или через файловый браузер Dokploy).

> **Удалённый сервер без Dokploy на борту** (как у тебя): сети `dokploy-network`
> там нет. Либо убери блоки `networks`/`dokploy-network` из compose, либо просто
> возьми основной `docker-compose.yml` (host-режим) — он самодостаточен.

## Клиенты

Ставятся **официальные** клиенты RustDesk — кастомные собирать не нужно.
Самостоятельный делается только сервер; клиент привязывается к нему настройками.

| Платформа | Скачать | Примечание |
|-----------|---------|-----------|
| **Windows** | [GitHub Releases](https://github.com/rustdesk/rustdesk/releases) (`.exe`) · [rustdesk.com](https://rustdesk.com/) | Есть portable и установка как сервис (доступ к залоченному экрану) |
| **macOS** | [GitHub Releases](https://github.com/rustdesk/rustdesk/releases) (`.dmg`) | Отдельно Apple Silicon / Intel. Не подписан → разрешить запуск, дать права Screen Recording + Accessibility |
| **Linux** | [GitHub Releases](https://github.com/rustdesk/rustdesk/releases) (`.deb` / `.rpm` / AppImage) · [Flathub](https://flathub.org/apps/com.rustdesk.RustDesk) | |
| **iPhone / iPad** | [App Store](https://apps.apple.com/app/rustdesk-remote-desktop/id1581225015) | ⚠️ Только как **пульт**: управляешь другими, самим iOS управлять нельзя (ограничение системы) |
| **Android** | [Google Play](https://play.google.com/store/apps/details?id=com.carriez.flutter_hbb) · [GitHub Releases](https://github.com/rustdesk/rustdesk/releases) (`.apk`) | Может и управлять, и быть управляемым |
| **Исходники** | [github.com/rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) | Для самостоятельной сборки, если нужен полный аудит |

### Привязка клиента к своему серверу

В клиенте: **⋮ → Network / ID-Relay Server**:
- **ID Server**: `<твой IP/домен>` (без порта)
- **Relay Server**: пусто (возьмётся из `-r`) или тот же адрес
- **Key**: содержимое `data/id_ed25519.pub`

**Лайфхак для телефона:** на настроенном десктопе **⋮ → Network → Export Server Config**
получишь строку/QR со всеми параметрами; на iPhone — **Import Server Config**,
вставка из буфера. Не нужно вбивать длинный ключ вручную.

## Unattended access (подключение без подтверждения)

Главный сценарий «своего AnyDesk» — достучаться до машины, когда рядом никого нет.

- **Windows**: установить RustDesk **как сервис** (опция в инсталляторе), задать
  постоянный пароль в **Settings → Security → Permanent password**. Тогда доступ
  есть даже до входа в систему / на экране блокировки.
- **macOS**: задать permanent password; обязательно выдать **Screen Recording**
  и **Accessibility** в «Системные настройки → Конфиденциальность».
- ⚠️ Постоянный пароль = постоянный доступ. Делай его сложным и не переиспользуй.

## Web-клиент (опционально)

`hbbs` слушает порты web-клиента (21118/21119). Для доступа из браузера
понадобится поднять web-клиент за reverse-proxy с TLS. Для большинства личных
сценариев это не нужно — нативные клиенты удобнее и быстрее.

## Безопасность

- `-k _` в compose **требует** шифрование: без правильного ключа не подключиться.
- Весь трафик — только через твой сервер, не через облако RustDesk.
- Папка `data/` хранит приватный ключ и БД устройств — **бэкапь и не коммить**
  (уже в `.gitignore`). Потеря ключа = перенастройка всех клиентов.
- Открывай наружу только порты 21115–21119; `21116/udp` обязателен.

## Ресурсы

Сервисы почти ничего не едят: **~30–80 МБ RAM**, CPU ≈ 0 в простое.
Хватает самого дешёвого VPS (**1 vCPU / 1 ГБ**). Реальное ограничение —
**трафик**: при P2P через сервер идёт только heartbeat (байты), при relay —
весь поток (~1–5 Мбит/с на сессию). Выбирай VPS по лимиту трафика, а не по CPU.

## Лицензия

Конфиги в этом репозитории — свободны к использованию.
RustDesk распространяется под [AGPL-3.0](https://github.com/rustdesk/rustdesk/blob/master/LICENCE).
