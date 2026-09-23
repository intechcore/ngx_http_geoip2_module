#!/usr/bin/env bash
# Tests for the http and the stream module. Runs nginx from the test image and
# checks the configuration parser, lookups and auto_reload. Every request is
# sent from inside the container.
#
#   tests/run.sh <test image>     build it with: docker build --target test -t <image> .
#
# DOCKER_RUN_ARGS adds arguments to every docker run, for example the gcov
# settings of the coverage build in CI. NGINX_GLOBALS adds global directives to
# every nginx run, for example the env directives that keep the gcov settings
# in the workers.
#
# fixtures/a.mmdb and fixtures/b.mmdb map the same addresses to different
# countries: 203.0.113.0/24 is DE in a and FR in b, 2001:db8::/32 is CH in a
# and AT in b. a.mmdb also maps 192.0.2.0/24 to a record with every data type.
# fixtures/v4.mmdb is an IPv4 only database. Regenerate them with
# fixtures/generate.
set -euo pipefail

IMAGE=${1:?usage: tests/run.sh <test image>}
FIXTURES="$(cd "$(dirname "$0")/fixtures" && pwd)"
CONF="$(cd "$(dirname "$0")/conf" && pwd)"
IPV4=203.0.113.10
IPV6=2001:db8::1
TYPES=192.0.2.1
UNKNOWN=198.51.100.1
TYPE_VALUES="1 raw 1.50000 -2.25000 -9000000000000000000.00000 16 4000000000 -32 18446744073709551615 0x00000000000000010000000000000002 text first"
FALLBACKS="MAP MISSING BADPATH RECORD"

read -r -a EXTRA_ARGS <<<"${DOCKER_RUN_ARGS:-}"
GLOBALS="${NGINX_GLOBALS:-}"
GENERATED="$(mktemp -d)"

passed=0
failed=0
container=""

# Stop nginx gracefully, so an instrumented module can write its counters.
cleanup() {
  if [[ -n "$container" ]]; then
    docker stop -t 10 "$container" >/dev/null 2>&1 || true
    docker rm -f "$container" >/dev/null 2>&1 || true
    container=""
  fi
}
trap 'cleanup; rm -rf "$GENERATED"' EXIT

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
  if [[ "$2" = "$3" ]]; then
    ok "$1"
  else
    not_ok "$1: expected '$2', got '$3'"
  fi
}

# check_match <name> <extended regex> <actual>
check_match() {
  if [[ "$3" =~ $2 ]]; then
    ok "$1"
  else
    not_ok "$1: expected /$2/, got '$3'"
  fi
}

# start [<configuration in tests/conf>]: start nginx with a.mmdb as
# /data/current.mmdb, with tests/nginx.conf by default.
start() {
  local conf=/etc/nginx/nginx.conf
  if [[ $# -gt 0 ]]; then
    conf="/conf/$1"
  fi
  cleanup
  container=$(docker run -d -v "$FIXTURES:/fixtures:ro" -v "$CONF:/conf:ro" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} --entrypoint sh "$IMAGE" \
    -c 'mkdir -p /data && cp /fixtures/a.mmdb /data/current.mmdb &&
        exec nginx -c "$0" -g "daemon off; $1"' "$conf" "$GLOBALS")
  local _
  for _ in $(seq 1 50); do
    if docker exec "$container" curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  docker logs "$container" >&2
  echo "nginx did not start" >&2
  exit 1
}

# http <path> [<curl argument>...]: the response body without the newline.
http() {
  local path=$1
  shift
  docker exec "$container" curl -fsS "$@" "http://127.0.0.1:8080$path" | tr -d '\n'
}

# lookup <address>: the country nginx resolves for that client address.
lookup() {
  http / -H "X-IP: $1"
}

# stream <port> [<client address>|unknown]: the reply of a stream server. The
# address goes in a PROXY protocol header, "unknown" sends PROXY UNKNOWN.
# Without an address, no header is sent.
stream() {
  local header=""
  case ${2:-} in
    "") ;;
    unknown) header="PROXY UNKNOWN" ;;
    *:*) header="PROXY TCP6 $2 ::1 1000 $1" ;;
    *) header="PROXY TCP4 $2 127.0.0.1 1000 $1" ;;
  esac
  docker exec "$container" bash -c \
    'exec 3<>"/dev/tcp/127.0.0.1/$0" && if [[ -n $1 ]]; then printf "%s\r\n" "$1" >&3; fi && cat <&3' \
    "$1" "$header" | tr -d '\n'
}

# stream_lookup <address>: the country the stream module resolves.
stream_lookup() {
  stream 9000 "$1"
}

# replace_db <shell command run on /data/new.mmdb before the swap>
# Swaps in b.mmdb with mv, which gives the file a new inode.
replace_db() {
  docker exec "$container" sh -c \
    "cp /fixtures/b.mmdb /data/new.mmdb && $1 && mv /data/new.mmdb /data/current.mmdb"
}

# Let the auto_reload interval (1s) pass. The next request and the next stream
# session trigger the check in their log phase, after the response went out.
# Both read no database, so a file changed in place is never read.
trigger_reload() {
  sleep 2
  http /metadata >/dev/null
  stream 9007 "$IPV4" >/dev/null
}

# logged <count> <fixed string>: wait up to 5s until the log holds the string
# at least count times. docker logs can lag behind nginx.
logged() {
  local _
  for _ in $(seq 1 25); do
    if [[ $(docker logs "$container" 2>&1 | grep -cF "$2") -ge $1 ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# check_logged <name> <count> <fixed string>
check_logged() {
  if logged "$2" "$3"; then
    ok "$1"
  else
    not_ok "$1: '$3' not logged $2 times"
  fi
}

# sanitized <output>: true if a sanitizer of the asan image reported an error.
sanitized() {
  grep -qE 'ERROR: AddressSanitizer|runtime error:' <<<"$1"
}

no_crash() {
  local logs
  logs=$(docker logs "$container" 2>&1)
  if sanitized "$logs"; then
    not_ok "$1: a sanitizer reported an error"
    grep -E -A20 'ERROR: AddressSanitizer|runtime error:' <<<"$logs" >&2
  elif grep -q "exited on signal" <<<"$logs"; then
    not_ok "$1: a worker crashed"
  else
    ok "$1: no worker crash"
  fi
}

# rejected <name> <http|stream> <configuration> <expected message>: nginx -t
# must fail on the configuration of the http or stream block with the
# message, and must not crash (exit code 139 is a segfault).
rejected() {
  local conf out rc=0
  conf="$(mktemp "$GENERATED/XXXXXX")"
  printf 'load_module modules/ngx_%s_geoip2_module.so;\nevents {}\n%s {\n%s\n}\n' \
    "$2" "$2" "$3" >"$conf"
  out=$(docker run --rm -v "$FIXTURES:/fixtures:ro" -v "$GENERATED:/generated:ro" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} --entrypoint nginx "$IMAGE" \
    -t -c "/generated/${conf##*/}" -g "$GLOBALS" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    not_ok "$2: $1: accepted"
  elif [[ $rc -eq 139 ]]; then
    not_ok "$2: $1: nginx crashed"
  elif sanitized "$out"; then
    not_ok "$2: $1: a sanitizer reported an error: $out"
  elif [[ $out != *"$4"* ]]; then
    not_ok "$2: $1: message missing, got: $out"
  else
    ok "$2: $1"
  fi
}

echo "module"
if docker run --rm -v "$FIXTURES:/fixtures:ro" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} --entrypoint sh "$IMAGE" \
  -c 'mkdir -p /data && cp /fixtures/a.mmdb /data/current.mmdb && nginx -t -g "$0"' "$GLOBALS" >/dev/null 2>&1; then
  ok "nginx -t accepts both modules and the test configuration"
else
  not_ok "nginx -t accepts both modules and the test configuration"
fi

echo "configuration"
# shellcheck disable=SC2016 # the $ names are nginx variables, not shell ones
for module in http stream; do
  rejected "invalid auto_reload interval (upstream #90)" "$module" \
    'geoip2 /fixtures/a.mmdb { auto_reload bogus; }' \
    'invalid interval for auto_reload "bogus"'
  rejected "auto_reload without an interval" "$module" \
    'geoip2 /fixtures/a.mmdb { auto_reload; }' \
    'invalid number of arguments for auto_reload'
  rejected "unknown setting" "$module" \
    'geoip2 /fixtures/a.mmdb { reload 1s; }' \
    'invalid setting "reload"'
  rejected "unknown setting with the length of auto_reload" "$module" \
    'geoip2 /fixtures/a.mmdb { auto_rel0ad 1s; }' \
    'invalid setting "auto_rel0ad"'
  rejected "duplicate database" "$module" \
    'geoip2 /fixtures/a.mmdb { } geoip2 /fixtures/a.mmdb { }' \
    'Duplicate GeoIP2 mmdb - /fixtures/a.mmdb'
  rejected "missing database, relative path" "$module" \
    'geoip2 missing.mmdb { }' \
    'MMDB_open("/etc/nginx/missing.mmdb") failed'
  rejected "default declared twice" "$module" \
    'geoip2 /fixtures/a.mmdb { $v default=A default=B country iso_code; }' \
    'default has already been declared for  "$v"'
  rejected "source declared twice" "$module" \
    'geoip2 /fixtures/a.mmdb { $v source=$remote_addr source=$remote_addr country iso_code; }' \
    'source has already been declared for  "$v"'
  rejected "source is not a variable" "$module" \
    'geoip2 /fixtures/a.mmdb { $v source=remote_addr country iso_code; }' \
    'invalid source variable name "remote_addr"'
  rejected "source does not compile" "$module" \
    'geoip2 /fixtures/a.mmdb { $v source=${remote_addr country iso_code; }' \
    'unable to compile "${remote_addr" for "$v"'
  rejected "unknown short option" "$module" \
    'geoip2 /fixtures/a.mmdb { $v x=y country iso_code; }' \
    'invalid setting "x=y" for "$v"'
  rejected "unknown long option" "$module" \
    'geoip2 /fixtures/a.mmdb { $v unknown=value country iso_code; }' \
    'invalid setting "unknown=value" for "$v"'
  rejected "variable that nginx already defines" "$module" \
    'geoip2 /fixtures/a.mmdb { $remote_addr country iso_code; }' \
    'the duplicate "remote_addr" variable'
  rejected "metadata without a field" "$module" \
    'geoip2 /fixtures/a.mmdb { $v metadata; }' \
    'invalid number of arguments for metadata "$v"'
  rejected "metadata with an unknown field" "$module" \
    'geoip2 /fixtures/a.mmdb { $v metadata build_epochs; }' \
    'invalid metadata field "build_epochs" for "$v"'
  rejected "metadata variable that nginx already defines" "$module" \
    'geoip2 /fixtures/a.mmdb { $remote_addr metadata build_epoch; }' \
    'the duplicate "remote_addr" variable'
done
rejected "invalid geoip2_proxy network" http \
  'geoip2_proxy bogus;' \
  'invalid network "bogus"'

echo "http lookups"
start
check "IPv4 address" DE "$(lookup "$IPV4")"
check "IPv6 address" CH "$(lookup "$IPV6")"
check "address not in the database gets the default" ZZ "$(lookup "$UNKNOWN")"
check "repeated IPv4 lookup (cached)" DE "$(lookup "$IPV4")"
check "source that is not an address gets the default" ZZ "$(lookup "not-an-address")"
check "address not in the database, no default" "[]" "$(http /bare -H "X-IP: $UNKNOWN")"
check "IPv4 address in an IPv4 database" SE "$(http /v4 -H "X-IP: $IPV4")"
check "IPv6 address in an IPv4 database gets the default" FAIL "$(http /v4 -H "X-IP: $IPV6")"
check "same IPv6 address again (cached failure)" FAIL "$(http /v4 -H "X-IP: $IPV6")"
check "every data type" "$TYPE_VALUES" "$(http /types -H "X-IP: $TYPES")"
check "map, missing key, invalid path, no path get the default" "$FALLBACKS" \
  "$(http /fallback -H "X-IP: $TYPES")"
check_match "metadata" '^[1-9][0-9]* [1-9][0-9]* [1-9][0-9]*$' "$(http /metadata)"
check "client address" ZZ "$(http /client)"
check "client address, path starts with a word of 8 letters" "[]" "$(http /location)"
check "X-Forwarded-For from a trusted proxy" DE "$(http /client -H "X-Forwarded-For: $IPV4")"
check "X-Forwarded-For, recursive" DE \
  "$(http /client -H "X-Forwarded-For: $IPV4, $UNKNOWN")"
check "unix socket client gets the default" ZZ \
  "$(docker exec "$container" curl -fsS --unix-socket /tmp/http.sock http://localhost/client | tr -d '\n')"
check_logged "warning for the low bits of a geoip2_proxy network" 1 \
  "low address bits of 198.51.100.1/24 are meaningless"
no_crash "http lookups"

echo "stream lookups"
check "IPv4 address" DE "$(stream_lookup "$IPV4")"
check "IPv6 address" CH "$(stream_lookup "$IPV6")"
check "address not in the database gets the default" ZZ "$(stream_lookup "$UNKNOWN")"
check "repeated IPv4 lookup (cached)" DE "$(stream_lookup "$IPV4")"
check "PROXY UNKNOWN gets the default" ZZ "$(stream_lookup unknown)"
check "address not in the database, no default" "[]" "$(stream 9002 "$UNKNOWN")"
check "IPv4 address in an IPv4 database" SE "$(stream 9003 "$IPV4")"
check "IPv6 address in an IPv4 database gets the default" FAIL "$(stream 9003 "$IPV6")"
check "every data type" "$TYPE_VALUES" "$(stream 9005 "$TYPES")"
check "map, missing key, invalid path, no path get the default" "$FALLBACKS" \
  "$(stream 9006 "$TYPES")"
check_match "metadata" '^[1-9][0-9]* [1-9][0-9]* [1-9][0-9]*$' "$(stream 9007 "$IPV4")"
check "client address" ZZ "$(stream 9001 "$IPV4")"
check "client address, path starts with a word of 8 letters" "[]" "$(stream 9004 "$IPV4")"
# telnet:// sends nothing. Unread request data would make nginx reset the
# connection, and the reset can overtake the reply.
check "unix socket client gets the default" ZZ \
  "$(docker exec "$container" curl -sS --unix-socket /tmp/stream.sock telnet://localhost </dev/null | tr -d '\n')"
no_crash "stream lookups"

echo "auto_reload, new database with a new mtime (#134)"
start
check "http: before the swap" DE "$(lookup "$IPV4")"
check "stream: before the swap" DE "$(stream_lookup "$IPV4")"
replace_db "true"
trigger_reload
check "http: same address as the last lookup gets new data" FR "$(lookup "$IPV4")"
check "http: other address gets new data" AT "$(lookup "$IPV6")"
check "stream: same address as the last lookup gets new data" FR "$(stream_lookup "$IPV4")"
check "stream: other address gets new data" AT "$(stream_lookup "$IPV6")"
check_logged "reload is logged by both modules" 2 'Reload MMDB "/data/current.mmdb"'
no_crash "reload with a new mtime"

echo "auto_reload, new database with an old mtime"
start
check "http: before the swap" DE "$(lookup "$IPV4")"
check "stream: before the swap" DE "$(stream_lookup "$IPV4")"
replace_db "touch -d \"2020-01-01 00:00:00\" /data/new.mmdb"
trigger_reload
check "http: database is reloaded although its mtime is older" FR "$(lookup "$IPV4")"
check "stream: database is reloaded although its mtime is older" FR "$(stream_lookup "$IPV4")"
# 2020-01-01 00:00:00 UTC
check_match "http: last_change is the mtime of the new database" ' 1577836800$' "$(http /metadata)"
check_match "stream: last_change is the mtime of the new database" ' 1577836800$' \
  "$(stream 9007 "$IPV4")"
no_crash "reload with an old mtime"

echo "auto_reload, database changed in place with an old mtime"
start
docker exec "$container" sh -c \
  'cp /fixtures/b.mmdb /data/current.mmdb && touch -d "2020-01-01 00:00:00" /data/current.mmdb'
trigger_reload
check "http: the new size triggers the reload" FR "$(lookup "$IPV4")"
check "stream: the new size triggers the reload" FR "$(stream_lookup "$IPV4")"
no_crash "reload of a file changed in place"

echo "auto_reload, errors"
start
trigger_reload
check "http: unchanged database is kept" DE "$(lookup "$IPV4")"
check "stream: unchanged database is kept" DE "$(stream_lookup "$IPV4")"
docker exec "$container" rm /data/current.mmdb
trigger_reload
check_logged "missing database is logged by both modules" 2 \
  'stat() "/data/current.mmdb" failed'
check "http: lookups go on with the loaded database" DE "$(lookup "$IPV4")"
check "stream: lookups go on with the loaded database" DE "$(stream_lookup "$IPV4")"
docker exec "$container" sh -c 'echo broken > /data/current.mmdb'
trigger_reload
check_logged "broken database is logged by both modules" 2 \
  'MMDB_open("/data/current.mmdb") failed to reload'
check "http: lookups go on after a broken database" DE "$(lookup "$IPV4")"
check "stream: lookups go on after a broken database" DE "$(stream_lookup "$IPV4")"
no_crash "reload errors"

echo "http without geoip2_proxy, stream without a database"
start no-proxy.conf
check "X-Forwarded-For is ignored" ZZ "$(http / -H "X-Forwarded-For: $IPV4")"
check "stream serves without a database" ok "$(stream 9001)"
no_crash "no geoip2_proxy"

echo "http without a database"
start no-http-database.conf
check "http serves without a database" ok "$(http /)"
check "stream lookup" ZZ "$(stream 9001)"
no_crash "no http database"

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
