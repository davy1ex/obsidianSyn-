#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 backups/couchdb-YYYYMMDDTHHMMSSZ-id.tar.gz" >&2
  exit 2
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd)
image=couchdb:3.5.3

if [ ! -f "$repo_dir/.env" ]; then
  echo "Missing .env. Restore validation uses the configured CouchDB credentials." >&2
  exit 1
fi

archive=$1
case "$archive" in
  /*) ;;
  *) archive="$repo_dir/$archive" ;;
esac
archive_dir=$(CDPATH= cd "$(dirname "$archive")" && pwd)
archive_name=$(basename "$archive")
archive="$archive_dir/$archive_name"

case "$archive_name" in
  couchdb-*.tar.gz) ;;
  *) echo "Expected a couchdb-*.tar.gz backup archive." >&2; exit 2 ;;
esac
if [ ! -f "$archive" ]; then
  echo "Backup archive not found: $archive" >&2
  exit 1
fi

tar -tzf "$archive" >/dev/null
python3 -c 'import pathlib,sys,tarfile; t=tarfile.open(sys.argv[1], "r:gz"); bad=[m.name for m in t.getmembers() if pathlib.PurePosixPath(m.name).is_absolute() or ".." in pathlib.PurePosixPath(m.name).parts]; t.close(); sys.exit("Unsafe path in archive" if bad else 0)' "$archive"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
recovery_volume="livesync-couchdb-restore-${timestamp}-$$"
check_container="livesync-couchdb-restore-check-$$"

docker volume create \
  "$recovery_volume" >/dev/null

docker run --rm --network none \
  --mount "type=volume,source=$recovery_volume,target=/data" \
  --mount "type=bind,source=$archive_dir,target=/restore,readonly" \
  --env "ARCHIVE_NAME=$archive_name" \
  --entrypoint sh "$image" \
  -ec 'tar -xzf "/restore/$ARCHIVE_NAME" -C /data'

cleanup() {
  docker rm -f "$check_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --rm --network none \
  --name "$check_container" \
  --env-file "$repo_dir/.env" \
  --mount "type=volume,source=$recovery_volume,target=/opt/couchdb/data" \
  --mount "type=bind,source=$repo_dir/couchdb/livesync.ini,target=/opt/couchdb/etc/local.ini" \
  "$image" >/dev/null

ready=0
attempt=0
while [ "$attempt" -lt 60 ]; do
  if docker exec "$check_container" sh -ec '
    auth="$COUCHDB_USER:$COUCHDB_PASSWORD"
    curl -fsS --max-time 4 --user "$auth" http://127.0.0.1:5984/_up | grep -q status
    curl -fsS --max-time 4 --user "$auth" "http://127.0.0.1:5984/$COUCHDB_DATABASE" >/dev/null
  '; then
    ready=1
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done

if [ "$ready" -ne 1 ]; then
  docker logs "$check_container" >&2 || true
  echo "The recovery volume did not pass the CouchDB health and database checks." >&2
  echo "Preserved for inspection: $recovery_volume" >&2
  exit 1
fi

docker stop "$check_container" >/dev/null
trap - EXIT

echo "Recovery volume passed CouchDB health and database checks: $recovery_volume"
echo "Original volume was not changed. Note verification still requires a test Obsidian vault."
echo "After stopping all syncing devices, set these in .env:"
echo "COUCHDB_VOLUME_NAME=$recovery_volume"
echo "COUCHDB_VOLUME_EXTERNAL=true"
echo "Then run: docker compose up -d"
