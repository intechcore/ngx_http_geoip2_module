#!/usr/bin/env bash
# Integration tests. tests/run.sh checks each code path on synthetic fixtures;
# these tests run the modules the way users do: with the MaxMind test
# databases, which have the real GeoLite2 schema, and behind proxies (see
# proxies/compose.yml). The expected values come from mmdblookup on the same
# databases.
#
#   tests/integration/run.sh <test image>     build it with: docker build --target test -t <image> .
#
# LOAD_SECONDS and LOAD_CLIENTS set the length and the parallel clients of
# the load test, 10 s and 4 by default.
set -euo pipefail

IMAGE=${1:?usage: tests/integration/run.sh <test image>}
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD_SECONDS=${LOAD_SECONDS:-10}
LOAD_CLIENTS=${LOAD_CLIENTS:-4}

# shellcheck source=tests/lib.sh
. "$HERE/../lib.sh"
# compose <argument>...: docker compose on the proxy topology.
compose() {
  IMAGE="$IMAGE" DATABASES="$HERE/databases" \
    docker compose -f "$HERE/proxies/compose.yml" "$@"
}

trap 'cleanup; [[ -n ${KEEP:-} ]] || compose down --timeout 5 >/dev/null 2>&1 || true' EXIT

"$HERE/databases.sh"

# start <configuration in tests/integration>: start nginx with the MaxMind
# databases in /databases, and tests/fixtures/a.mmdb as /data/current.mmdb.
start() {
  cleanup
  container=$(docker run -d -v "$HERE/databases:/databases:ro" -v "$HERE:/integration:ro" \
    -v "$HERE/../fixtures:/fixtures:ro" --entrypoint sh "$IMAGE" \
    -c 'mkdir -p /data && cp /fixtures/a.mmdb /data/current.mmdb &&
        exec nginx -c "/integration/$0" -g "daemon off;"' "$1")
  wait_for_nginx
}

# lookup <address>: country|subdivision|city|city escaped|Japanese city
# escaped|latitude|longitude|geoname_id|country (Country database)|continent|
# ASN|AS organization escaped
lookup() {
  http / -H "X-IP: $1"
}

echo "MaxMind test databases: http"
start maxmind.conf
check "London: subdivision, double values, Japanese name escaped" \
  "GB|ENG|London|London|%E3%83%AD%E3%83%B3%E3%83%89%E3%83%B3|51.51420|-0.09310|2643743|GB|EU|-|-" \
  "$(lookup 81.2.69.142)"
check "Linköping: non-ASCII English name, ASN" \
  "SE|E|Linköping|Link%C3%B6ping|%E3%83%AA%E3%83%B3%E3%82%B7%E3%82%A7%E3%83%BC%E3%83%94%E3%83%B3%E3%82%B0|58.41670|15.61670|2694762|SE|EU|29518|Bredband2%20AB" \
  "$(lookup 89.160.20.112)"
check "San Diego: IPv6, space escaped" \
  "US|CA|San Diego|San%20Diego|%E3%82%B5%E3%83%B3%E3%83%87%E3%82%A3%E3%82%A8%E3%82%B4|32.72030|-117.15520|5391811|US|NA|-|-" \
  "$(lookup 2001:480::1)"
check "Czech Republic: IPv6, a country without a city" \
  "CZ|-|-|-|-|49.75000|15.00000|-|CZ|EU|-|-" \
  "$(lookup 2a02:d280::1)"
check "AT&T: only in the ASN database, ampersand escaped" \
  "-|-|-|-|-|-|-|-|-|-|7018|AT%26T%20Services" \
  "$(lookup 12.81.92.1)"
check "private address: in no database" \
  "-|-|-|-|-|-|-|-|-|-|-|-" \
  "$(lookup 10.0.0.1)"
check_match "metadata of a real database" '^1[0-9]{9}$' "$(http /metadata)"

echo "MaxMind test databases: stream"
check "London" "GB|London|-" "$(stream 9000 81.2.69.142)"
check "Linköping: non-ASCII name, ASN" "SE|Linköping|29518" "$(stream 9000 89.160.20.112)"
check "San Diego: IPv6" "US|San Diego|-" "$(stream 9000 2001:480::1)"
check "AT&T: only in the ASN database" "-|-|7018" "$(stream 9000 12.81.92.1)"
no_crash "MaxMind test databases"

# swap <a|b>: replace /data/current.mmdb with that fixture, atomically.
swap() {
  docker exec "$container" sh -c \
    "cp /fixtures/$1.mmdb /data/new.mmdb && mv /data/new.mmdb /data/current.mmdb"
}

# replies <http|stream>: the replies load.sh got, one per line.
replies() {
  docker exec "$container" cat "/tmp/$1.replies"
}

echo "load and reload: $LOAD_SECONDS s, $LOAD_CLIENTS http and $LOAD_CLIENTS stream clients"
start load.conf
docker exec "$container" /integration/load.sh "$LOAD_SECONDS" "$LOAD_CLIENTS" &
load=$!
swaps=0
next=b
end=$((SECONDS + LOAD_SECONDS - 1))
while ((SECONDS < end)); do
  sleep 1
  swap "$next"
  swaps=$((swaps + 1))
  last=$next
  if [[ $next == b ]]; then next=a; else next=b; fi
  if ((swaps % 3 == 0)); then
    docker exec "$container" nginx -c /integration/load.conf -s reload 2>/dev/null
  fi
done
wait "$load"
for kind in http stream; do
  out=$(replies "$kind")
  total=$(grep -c . <<<"$out" || true)
  echo "  $kind: $total replies, $swaps swaps, $((swaps / 3)) reloads"
  check "$kind: every reply is DE or FR" "" "$(grep -vxE 'DE|FR' <<<"$out" | sort -u | head -3)"
  check_match "$kind: replies from both databases" '^[1-9][0-9]* [1-9][0-9]*$' \
    "$(grep -cx DE <<<"$out" || true) $(grep -cx FR <<<"$out" || true)"
done
check_match "auto_reload loaded the swapped database" '^[1-9][0-9]*$' \
  "$(docker exec "$container" grep -c 'Reload MMDB "/data/current.mmdb"' /tmp/info.log || true)"
# New workers open the database at start: after a reload, every worker has
# the last swapped file.
docker exec "$container" nginx -c /integration/load.conf -s reload 2>/dev/null
sleep 1
expected=DE
if [[ $last == b ]]; then expected=FR; fi
check "http: the last database after a reload" "$expected" "$(http / -H 'X-IP: 203.0.113.10')"
check "stream: the last database after a reload" "$expected" "$(stream 9000 203.0.113.10)"
no_crash "load and reload"

# client <shell command>: run it in the client container, the output without
# the newline.
client() {
  compose exec -T client bash -c "$1" | tr -d '\n'
}

# via_front <X-Forwarded-For>: what the app gets for a request through front:
# country|escaped city|X-Forwarded-For.
via_front() {
  client "curl -fsS -H 'X-Forwarded-For: $1' http://172.30.123.20:8080/"
}

# proxied <server> <address>: the stream reply of the server to a PROXY
# protocol header with the client address.
proxied() {
  client "exec 3<>/dev/tcp/$1/9000 && printf 'PROXY TCP4 $2 172.30.123.20 1000 9000\r\n' >&3 && cat <&3"
}

cleanup
if ! out=$(compose up -d --quiet-pull 2>&1); then
  echo "$out" >&2
  exit 1
fi
up=""
for _ in $(seq 1 50); do
  if client 'curl -fsS http://172.30.123.20:8080/' >/dev/null 2>&1; then
    up=yes
    break
  fi
  sleep 0.2
done
if [[ -z $up ]]; then
  compose logs >&2
  echo "the proxy topology did not start" >&2
  exit 1
fi

echo "proxy topology: http"
check "client behind a trusted CDN and load balancer" \
  "SE|Link%C3%B6ping|89.160.20.112, 172.30.123.10" "$(via_front 89.160.20.112)"
check "recursive: the last address that is not trusted" \
  "-|-|81.2.69.142, 10.1.2.3, 172.30.123.10" "$(via_front '81.2.69.142, 10.1.2.3')"
check "without X-Forwarded-For: the CDN address" \
  "-|-|172.30.123.10" "$(client 'curl -fsS http://172.30.123.20:8080/')"
check "X-Forwarded-For from an untrusted address is ignored" "-|-|81.2.69.142" \
  "$(compose exec -T app curl -fsS -H 'X-Forwarded-For: 81.2.69.142' http://172.30.123.30:8080/ | tr -d '\n')"

echo "proxy topology: stream"
check "client address through the load balancer and realip" \
  "GB|London|81.2.69.142" "$(proxied 172.30.123.20 81.2.69.142)"
check "PROXY header from an untrusted address is ignored" \
  "-|-|172.30.123.10" "$(proxied 172.30.123.30 81.2.69.142)"

container=$(compose ps -a -q geoip)
no_crash "proxy topology"
container=""

summary
