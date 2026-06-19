# rustdesk — собственная инфраструктура RustDesk

Часть сборки [brave-stack](../README.md). Self-hosted remote desktop на базе
[RustDesk](https://github.com/rustdesk/rustdesk):
свой сервер, свои ключи, без лицензионных ограничений. Аналог AnyDesk/TeamViewer,
где весь трафик идёт **только через твою машину**, а не через чужое облако.

Работает между **Windows ⇄ macOS ⇄ Linux**, с **iPhone/Android в роли пульта**.

## Что внутри

| Файл | Назначение |
|------|-----------|
| [docker-compose.yml](docker-compose.yml) | Сервисы `hbbs` + `hbbr` + одноразовый `init`, host-режим |
| [docker-compose.dokploy.yml](docker-compose.dokploy.yml) | Вариант для Dokploy: проброс портов + `dokploy-network` |
| [init.sh](init.sh) | Init-шаг: при деплое сам печатает `ID/Relay/Key` в лог |
| [deploy.sh](deploy.sh) | Деплой на «голый» сервер без Dokploy (ставит Docker, firewall, поднимает всё) |
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

## Как деплоить

- **Через Dokploy** (основной путь) — нажимаешь Deploy, всё поднимается само,
  ключ появляется в логах. См. [раздел ниже](#деплой-через-dokploy).
- **На «голый» сервер без Dokploy** — одной командой через [deploy.sh](deploy.sh):

  ```bash
  git clone git@github.com:mikey-semy/brave-stack.git
  cd brave-stack/rustdesk
  sudo ./deploy.sh                 # RELAY_HOST определится по публичному IP
  # или явно: sudo ./deploy.sh my.domain.com
  ```

  Скрипт ставит Docker, открывает firewall, поднимает сервисы и в конце печатает
  `ID Server` / `Relay` / `Key`.

- **Вручную** (если хочется по шагам):

  ```bash
  cp .env.example .env && nano .env      # впиши RELAY_HOST = IP/домен VPS
  ufw allow 21115:21119/tcp && ufw allow 21116/udp && ufw reload
  docker compose up -d
  cat data/id_ed25519.pub                # публичный ключ для клиентов
  ```

Подробности, troubleshooting и обслуживание — в [DEPLOY.md](DEPLOY.md).

## Деплой через Dokploy

Ничего вручную запускать не нужно — всё поднимается само при нажатии **Deploy**.
В compose есть одноразовый сервис `init` ([init.sh](init.sh)): при каждом деплое
он дожидается генерации ключа и **печатает готовые `ID Server` / `Relay` / `Key`
прямо в логи** (контейнер `rustdesk-init`). Вручную лезть за ключом не надо.

1. Создай в Dokploy сервис типа **Docker Compose**, укажи этот репозиторий.
   Файл compose: `docker-compose.yml` (host-режим) — он самодостаточен.
2. Во вкладке **Environment** задай `RELAY_HOST=<IP/домен сервера>`.
3. Открой на сервере порты **21115–21119/tcp** и **21116/udp** — это
   **разовая** настройка хоста (см. ниже), не на каждый деплой.
4. Нажми **Deploy**. После старта открой логи `rustdesk-init` — там готовые
   параметры для клиентов.

> Сеть `dokploy-network` нужна, только если деплоишь на тот же сервер, где сам
> Dokploy. На отдельном удалённом сервере используется `docker-compose.yml`
> (host-режим, без внешней сети). Файл `docker-compose.dokploy.yml` — про запас.

### Firewall — один раз на сервере

Открытие портов — разовая операция уровня хоста (контейнеру лезть в firewall
хоста неправильно), поэтому в compose её нет. Сделай один раз по SSH:

```bash
ufw allow 21115:21119/tcp && ufw allow 21116/udp && ufw reload
```

Если на сервере нет `ufw` — открой те же порты в панели провайдера. Дальше
деплои в Dokploy идут уже без всякого SSH.

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
