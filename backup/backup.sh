#!/usr/bin/env bash
#
# Бэкап data-каталогов в S3/B2 через rclone.
# Архивирует -> (опц.) шифрует GPG -> заливает в облако -> чистит старое -> пингует ntfy.
# Запускается вручную или по cron (см. setup-backup.sh).
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/backup.env" ] || { echo "[x] нет backup.env (cp backup.env.example backup.env)"; exit 1; }
# shellcheck disable=SC1091
. "$DIR/backup.env"

: "${BACKUP_PATHS:?задай BACKUP_PATHS в backup.env}"
: "${RCLONE_REMOTE:?задай RCLONE_REMOTE в backup.env}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

HOST="$(hostname)"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ARCHIVE="$TMP/${HOST}-${STAMP}.tar.gz"

notify() {
  [ -z "${NTFY_URL:-}" ] && return 0
  # NTFY_TOKEN нужен для приватного ntfy (deny-all); без него — анонимно
  if [ -n "${NTFY_TOKEN:-}" ]; then
    curl -fsS -m 10 -H "Authorization: Bearer ${NTFY_TOKEN}" -H "Title: brave-stack backup" \
      -d "$1" "$NTFY_URL" >/dev/null 2>&1 || true
  else
    curl -fsS -m 10 -H "Title: brave-stack backup" -d "$1" "$NTFY_URL" >/dev/null 2>&1 || true
  fi
}
fail()   { echo "[x] $1" >&2; notify "❌ backup ${HOST}: $1"; exit 1; }

echo "[*] архивирую: $BACKUP_PATHS"
# абсолютные пути -> tar сам уберёт ведущий '/', при восстановлении: tar x -C /
tar czf "$ARCHIVE" $BACKUP_PATHS 2>/dev/null || fail "tar failed"

if [ -n "${GPG_RECIPIENT:-}" ]; then
  echo "[*] шифрую для $GPG_RECIPIENT"
  gpg --batch --yes --encrypt --recipient "$GPG_RECIPIENT" --output "$ARCHIVE.gpg" "$ARCHIVE" || fail "gpg failed"
  rm -f "$ARCHIVE"; ARCHIVE="$ARCHIVE.gpg"
fi

SIZE="$(du -h "$ARCHIVE" | cut -f1)"
echo "[*] заливаю $SIZE -> $RCLONE_REMOTE"
rclone copy "$ARCHIVE" "$RCLONE_REMOTE" || fail "upload failed"

echo "[*] чищу копии старше ${RETENTION_DAYS} дней"
rclone delete "$RCLONE_REMOTE" --min-age "${RETENTION_DAYS}d" 2>/dev/null || true

echo "[+] готово: $(basename "$ARCHIVE") ($SIZE)"
notify "✅ backup ${HOST} ok: $(basename "$ARCHIVE") ($SIZE)"
