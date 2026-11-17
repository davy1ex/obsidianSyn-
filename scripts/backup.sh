#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd)
backup_dir="$repo_dir/backups"
image=couchdb:3.5.3

cd "$repo_dir"

volume_name=${COUCHDB_VOLUME_NAME:-}
if [ -z "$volume_name" ] && [ -f .env ]; then
  volume_name=$(sed -n 's/^COUCHDB_VOLUME_NAME=//p' .env | tail -n 1)
fi
volume_name=${volume_name:-livesync-couchdb-data}
case "$volume_name" in
  *[!a-zA-Z0-9_.-]*|'') echo "COUCHDB_VOLUME_NAME contains unsupported characters." >&2; exit 1 ;;
esac

if ! docker compose ps --services --status running | grep -qx couchdb; then
  echo "CouchDB must be running before a backup." >&2
  exit 1
fi

keep_days=${BACKUP_KEEP_DAYS:-}
if [ -z "$keep_days" ] && [ -f .env ]; then
  keep_days=$(sed -n 's/^BACKUP_KEEP_DAYS=//p' .env | tail -n 1)
fi
keep_days=${keep_days:-30}
case "$keep_days" in
  *[!0-9]*) echo "BACKUP_KEEP_DAYS must be a non-negative integer." >&2; exit 1 ;;
esac

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
archive_name="couchdb-$(date -u +%Y%m%dT%H%M%SZ)-$$.tar.gz"

docker compose stop couchdb
restart_couchdb() {
  docker compose start couchdb >/dev/null 2>&1 || echo "Warning: start CouchDB manually with 'docker compose start couchdb'." >&2
}
trap restart_couchdb EXIT

docker run --rm --network none \
  --mount "type=volume,source=$volume_name,target=/data,readonly" \
  --mount "type=bind,source=$backup_dir,target=/backup" \
  --env "ARCHIVE_NAME=$archive_name" \
  --entrypoint sh "$image" \
  -ec 'tar -czf "/backup/$ARCHIVE_NAME" -C /data .'

tar -tzf "$backup_dir/$archive_name" >/dev/null
chmod 600 "$backup_dir/$archive_name"

if [ "$keep_days" -gt 0 ]; then
  find "$backup_dir" -type f -name 'couchdb-*.tar.gz' -mtime "+$keep_days" -delete
fi

echo "Backup created: $backup_dir/$archive_name"
