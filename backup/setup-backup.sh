#!/usr/bin/env bash
#
# Настройка бэкапов «под ключ»: ставит rclone, настраивает remote из backup.env,
# проверяет доступ к бакету, ставит cron (ежедневно 03:00) и делает первый бэкап.
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/backup.env" ] || { echo "[x] нет backup.env (cp backup.env.example backup.env и заполни)"; exit 1; }
# shellcheck disable=SC1091
. "$DIR/backup.env"

: "${RCLONE_REMOTE:?задай RCLONE_REMOTE в backup.env}"
REMOTE_NAME="${RCLONE_REMOTE%%:*}"   # имя remote = часть до ':'

# 1. rclone
if ! command -v rclone >/dev/null 2>&1; then
  echo "[*] ставлю rclone..."
  curl -fsS https://rclone.org/install.sh | bash
fi

# 2. настройка remote
echo "[*] настраиваю remote '${REMOTE_NAME}' (provider=${PROVIDER:-b2})"
rclone config delete "$REMOTE_NAME" >/dev/null 2>&1 || true
case "${PROVIDER:-b2}" in
  b2)
    : "${B2_KEY_ID:?задай B2_KEY_ID}"; : "${B2_APP_KEY:?задай B2_APP_KEY}"
    rclone config create "$REMOTE_NAME" b2 account "$B2_KEY_ID" key "$B2_APP_KEY" >/dev/null
    ;;
  s3)
    : "${S3_ACCESS_KEY:?}"; : "${S3_SECRET_KEY:?}"; : "${S3_ENDPOINT:?}"
    # force_path_style: имя бакета остаётся в пути, а не в hostname —
    # обязательно для бакетов с точкой (напр. brave.data), иначе ломается TLS-SNI.
    rclone config create "$REMOTE_NAME" s3 provider Other \
      access_key_id "$S3_ACCESS_KEY" secret_access_key "$S3_SECRET_KEY" \
      endpoint "$S3_ENDPOINT" region "${S3_REGION:-auto}" \
      force_path_style true >/dev/null
    ;;
  *) echo "[x] неизвестный PROVIDER: ${PROVIDER}"; exit 1 ;;
esac

# 3. проверка доступа
echo "[*] проверяю доступ к бакету..."
BUCKET_REMOTE="${RCLONE_REMOTE%%/*}"   # backup:bucket (без под-пути)
if rclone lsd "$BUCKET_REMOTE" >/dev/null 2>&1; then
  echo "[+] бакет доступен"
else
  echo "[!] не вижу бакет '${BUCKET_REMOTE}'. Проверь имя и права ключа (нужны read+write)."
  exit 1
fi

# 4. cron: ежедневно в 03:00 (надёжно даже при пустом crontab)
CRON_LINE="0 3 * * * ${DIR}/backup.sh >> /var/log/brave-backup.log 2>&1"
EXISTING="$(crontab -l 2>/dev/null | grep -vF "${DIR}/backup.sh" || true)"
{ [ -n "$EXISTING" ] && printf '%s\n' "$EXISTING"; printf '%s\n' "$CRON_LINE"; } | crontab -
echo "[+] cron установлен: ежедневно 03:00 (лог: /var/log/brave-backup.log)"

# 5. первый бэкап
echo "[*] делаю первый бэкап..."
chmod +x "$DIR/backup.sh"
"$DIR/backup.sh"

echo "[+] всё готово. Проверить копии: rclone lsl ${RCLONE_REMOTE}"
