# Восстановление / переезд на новый сервер

Принцип «системы ухода»: всё ценное лежит в **S3/B2-бэкапах вне сервера**,
а вся инфра — в монорепо `brave-stack`. Переезд = clone репо + распаковка data +
`docker compose up`.

## Что нужно для восстановления
- Доступ к бакету (те же ключи, что в `backup/backup.env`).
- GPG-приватный ключ, **если** бэкапы шифровались (`GPG_RECIPIENT`). Без него
  зашифрованный архив не открыть — храни этот ключ отдельно и надёжно!

## Шаги переезда
1. Новый сервер (Linux + Docker + compose).
2. Склонируй сборку и восстанови доступ к бэкапам:
   ```bash
   git clone git@github.com:mikey-semy/brave-stack.git && cd brave-stack/backup
   cp backup.env.example backup.env && nano backup.env   # старые бакет/ключи
   bash setup-backup.sh                                   # rclone + remote (+ cron/тест)
   ```
3. Найди и скачай последний бэкап:
   ```bash
   rclone lsf backup:ИМЯ_БАКЕТА/brave
   rclone copy backup:ИМЯ_БАКЕТА/brave/<последний> ./restore/
   ```
4. Если архив зашифрован:
   ```bash
   gpg --decrypt restore/<имя>.tar.gz.gpg > restore/<имя>.tar.gz
   ```
5. Распакуй в корень (пути в архиве абсолютные):
   ```bash
   sudo tar xzf restore/<имя>.tar.gz -C /
   ```
6. Подними сервисы из корня сборки:
   ```bash
   cd ..                                   # в корень brave-stack
   echo "RELAY_HOST=<НОВЫЙ_IP>" > .env
   docker compose up -d                    # вся сборка
   # или один сервис: docker compose -f rustdesk/docker-compose.yml up -d
   ```
   > Данные RustDesk восстановлены в `rustdesk/data/` → **ключ тот же**. Клиентам
   > менять только **Server ID** (новый IP), поле **Key оставить прежним**.
7. Обнови IP в клиентах (и DNS, если используешь домен).

## Регулярная проверка (важно!)
Бэкап без проверки восстановления — это не бэкап. Раз в пару месяцев:
```bash
rclone lsl backup:ИМЯ_БАКЕТА/brave     # свежие даты и размеры на месте?
```
И хотя бы раз сделай тестовую распаковку в `/tmp`, убедись что архив целый
(и GPG-ключ на месте).
