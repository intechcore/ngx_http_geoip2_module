#!/usr/bin/env bash
# Downloads the MaxMind test databases into tests/integration/databases/.
# They come from a fixed commit of github.com/maxmind/MaxMind-DB (Apache-2.0
# or MIT) and have the real GeoLite2 schema.
#
#   tests/integration/databases.sh
set -euo pipefail

# Renovate updates the commit monthly. The commit fixes the content of the
# files. If MaxMind changes a value the tests use, tests/integration/run.sh fails.
# renovate: maxmind-db
COMMIT=55f9b2727fd5ab22ce175b475afbcd44c64dd009
DIR="$(cd "$(dirname "$0")" && pwd)/databases"
NAMES=(GeoLite2-ASN-Test.mmdb GeoLite2-City-Test.mmdb GeoLite2-Country-Test.mmdb)

# The databases of this commit are already here.
current() {
  [[ -f "$DIR/.commit" && $(<"$DIR/.commit") == "$COMMIT" ]] || return 1
  local name
  for name in "${NAMES[@]}"; do
    [[ -s "$DIR/$name" ]] || return 1
  done
}

current && exit 0
mkdir -p "$DIR"
rm -f "$DIR/.commit"
for name in "${NAMES[@]}"; do
  curl -fsSL --proto '=https' -o "$DIR/$name" \
    "https://raw.githubusercontent.com/maxmind/MaxMind-DB/$COMMIT/test-data/$name"
done
echo "$COMMIT" >"$DIR/.commit"
