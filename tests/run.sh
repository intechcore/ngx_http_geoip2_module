#!/usr/bin/env bash
# Tests for the module. Runs nginx from the test image and checks lookups and
# auto_reload through HTTP.
#
#   tests/run.sh <test image>     build it with: docker build --target test -t <image> .
#
# fixtures/a.mmdb and fixtures/b.mmdb map the same addresses to different
# countries: 203.0.113.0/24 is DE in a and FR in b, 2001:db8::/32 is CH in a
# and AT in b. Regenerate them with fixtures/generate.
set -euo pipefail

IMAGE=${1:?usage: tests/run.sh <test image>}
FIXTURES="$(cd "$(dirname "$0")/fixtures" && pwd)"
IPV4=203.0.113.10
IPV6=2001:db8::1
UNKNOWN=198.51.100.1

passed=0
failed=0
container=""
port=""

cleanup() {
  if [ -n "$container" ]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
    container=""
  fi
}
trap cleanup EXIT

ok() {
  echo "  ok   $1"
  passed=$((passed + 1))
}

not_ok() {
  echo "  FAIL $1"
  failed=$((failed + 1))
}

# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    not_ok "$1: expected '$2', got '$3'"
  fi
}

# Start nginx with a.mmdb as /data/current.mmdb.
start() {
  cleanup
  container=$(docker run -d -p 127.0.0.1::8080 -v "$FIXTURES:/fixtures:ro" \
    --entrypoint sh "$IMAGE" \
    -c 'mkdir -p /data && cp /fixtures/a.mmdb /data/current.mmdb && exec nginx -g "daemon off;"')
  port=$(docker port "$container" 8080/tcp | head -1 | awk -F: '{print $NF}')
  local _
  for _ in $(seq 1 50); do
    if curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  docker logs "$container" >&2
  echo "nginx did not start" >&2
  exit 1
}

# lookup <address>: the country nginx resolves for that client address.
lookup() {
  curl -fsS -H "X-IP: $1" "http://127.0.0.1:$port/" | tr -d '\n'
}

# replace_db <shell command run on /data/new.mmdb before the swap>
# Swaps in b.mmdb with mv, which gives the file a new inode.
replace_db() {
  docker exec "$container" sh -c \
    "cp /fixtures/b.mmdb /data/new.mmdb && $1 && mv /data/new.mmdb /data/current.mmdb"
}

# Let the auto_reload interval (1s) pass. The next request triggers the reload
# in its log phase, after its response went out. The request after that sees
# the new database.
trigger_reload() {
  sleep 2
  lookup "$1" >/dev/null
}

no_crash() {
  if docker logs "$container" 2>&1 | grep -q "exited on signal"; then
    not_ok "$1: a worker crashed"
  else
    ok "$1: no worker crash"
  fi
}

echo "module"
if docker run --rm -v "$FIXTURES:/fixtures:ro" --entrypoint sh "$IMAGE" \
  -c 'mkdir -p /data && cp /fixtures/a.mmdb /data/current.mmdb && nginx -t' >/dev/null 2>&1; then
  ok "nginx -t accepts the module and the geoip2 block"
else
  not_ok "nginx -t accepts the module and the geoip2 block"
fi

echo "lookups"
start
check "IPv4 address" DE "$(lookup "$IPV4")"
check "IPv6 address" CH "$(lookup "$IPV6")"
check "address not in the database gets the default" ZZ "$(lookup "$UNKNOWN")"
check "repeated IPv4 lookup (cached)" DE "$(lookup "$IPV4")"

echo "auto_reload, new database with a new mtime (#134)"
start
check "before the swap" DE "$(lookup "$IPV4")"
replace_db "true"
trigger_reload "$IPV4"
check "same address as the last lookup gets new data" FR "$(lookup "$IPV4")"
check "other address gets new data" AT "$(lookup "$IPV6")"
if docker logs "$container" 2>&1 | grep -q 'Reload MMDB "/data/current.mmdb"'; then
  ok "reload is logged"
else
  not_ok "reload is logged"
fi
no_crash "reload with a new mtime"

echo "auto_reload, new database with an old mtime"
start
check "before the swap" DE "$(lookup "$IPV4")"
replace_db "touch -d 2020-01-01 /data/new.mmdb"
trigger_reload "$IPV4"
check "database is reloaded although its mtime is older than the start" FR "$(lookup "$IPV4")"
no_crash "reload with an old mtime"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
