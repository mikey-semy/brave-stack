# RustDesk self-hosted — деплой

Своя инфраструктура RustDesk: два сервиса (`hbbs` + `hbbr`) на одном Linux VPS.
Никаких лицензий, весь трафик идёт только через твой сервер.

## Что это за процессы

| Сервис | Роль | Порты |
|--------|------|-------|
| **hbbs** | ID/Rendezvous: регистрация устройств, heartbeat, брокеринг, тест NAT | 21115/tcp, 21116/tcp+**udp**, 21118/tcp (web) |
| **hbbr** | Relay: проксирует видеопоток, когда прямой P2P не удался | 21117/tcp, 21119/tcp (web) |

> `21116/udp` — критичен. Без него устройства не регистрируются. Это самая частая ошибка при настройке firewall.

## Шаги

### 1. Сервер
Нужен Linux VPS (Ubuntu/Debian) с Docker и docker-compose-plugin.

```bash
# установка docker (если ещё нет)
curl -fsSL https://get.docker.com | sh
```

### 2. Конфиг
```bash
cp .env.example .env
# впиши публичный IP/домен VPS в RELAY_HOST
nano .env
```

### 3. Firewall
```bash
ufw allow 21115:21119/tcp
ufw allow 21116/udp
ufw reload
```

### 4. Запуск
```bash
docker compose up -d
docker compose logs -f hbbs   # убедиться, что поднялся
```

### 5. Забрать публичный ключ
hbbs при первом старте сгенерировал ключ-пару в `./data`.
Клиентам нужен **публичный** ключ:

```bash
cat ./data/id_ed25519.pub
```
Скопируй эту строку — она пойдёт в настройки клиентов.

### 6. Настройка клиентов (Windows / macOS / iPhone)
В приложении RustDesk → ID/Relay Server (⋮ → Network):
- **ID Server**: `<RELAY_HOST>` (только адрес, без порта)
- **Relay Server**: оставить пустым (возьмётся из -r) или `<RELAY_HOST>`
- **Key**: вставить содержимое `id_ed25519.pub`

После этого устройства видят только твой сервер. Готово.

## Обслуживание
```bash
docker compose pull && docker compose up -d   # обновление
docker compose down                           # остановка
```

⚠️ Папка `./data` содержит ключи и БД устройств — **бэкапь её**. Потеря
`id_ed25519`/`.pub` = придётся перенастраивать ключ на всех клиентах.

## Host-режим vs ports
По умолчанию используется `network_mode: host` — так hbbs видит реальные
IP клиентов и чаще удаётся прямой P2P (меньше нагрузки на relay). Работает
только на Linux. Если деплоишь не на Linux — в `docker-compose.yml` убери
`network_mode: host` и раскомментируй блоки `ports`.
