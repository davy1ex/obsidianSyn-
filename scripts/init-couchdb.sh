#!/bin/sh
set -eu

base_url=${COUCHDB_URL:-http://couchdb:5984}
username=${COUCHDB_USER:?COUCHDB_USER is required}
password=${COUCHDB_PASSWORD:?COUCHDB_PASSWORD is required}
database=${COUCHDB_DATABASE:-obsidiannotes}
auth="${username}:${password}"

case "$database" in
  ''|*[!a-z0-9_-]*|[!a-z]* )
    echo "COUCHDB_DATABASE must start with a lowercase letter and contain only lowercase letters, digits, _ or -." >&2
    exit 1
    ;;
esac

echo "Waiting for CouchDB..."
until curl -fsS --max-time 4 --user "$auth" "$base_url/_up" | grep -q '"status":"ok"'; do
  sleep 2
done

ensure_true() {
  section=$1
  key=$2
  setting_url="$base_url/_node/_local/_config/$section/$key"
  current=$(curl -sS --user "$auth" "$setting_url" 2>/dev/null || true)
  if [ "$current" != '"true"' ]; then
    curl -fsS --user "$auth" -X PUT \
      -H 'Content-Type: application/json' \
      -d '"true"' "$setting_url" >/dev/null
  fi
}

# Apply the access requirement after first-run single-node setup is complete.
ensure_true chhttpd require_valid_user

database_url="$base_url/$database"
status=$(curl -sS --user "$auth" -o /dev/null -w '%{http_code}' "$database_url")
case "$status" in
  200)
    echo "Database '$database' already exists."
    ;;
  404)
    curl -fsS --user "$auth" -X PUT "$database_url" >/dev/null
    echo "Created database '$database'."
    ;;
  *)
    echo "Unexpected HTTP status $status while checking database '$database'." >&2
    exit 1
    ;;
esac
