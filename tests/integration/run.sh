#!/usr/bin/env bash
# Integration tests. tests/run.sh checks each code path on synthetic fixtures;
# these tests run the modules the way users do: with the MaxMind test
# databases, which have the real GeoLite2 schema. The expected values come
# from mmdblookup on the same databases.
#
#   tests/integration/run.sh <test image>     build it with: docker build --target test -t <image> .
set -euo pipefail

IMAGE=${1:?usage: tests/integration/run.sh <test image>}
HERE="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=tests/lib.sh
. "$HERE/../lib.sh"
trap cleanup EXIT

"$HERE/databases.sh"

# start <configuration in tests/integration>
start() {
  cleanup
  container=$(docker run -d -v "$HERE/databases:/databases:ro" -v "$HERE:/integration:ro" \
    --entrypoint nginx "$IMAGE" -c "/integration/$1" -g "daemon off;")
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

summary
