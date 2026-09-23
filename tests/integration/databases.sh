#!/usr/bin/env bash
# Downloads the MaxMind test databases into tests/integration/databases/ and
# checks them. They come from a fixed commit of github.com/maxmind/MaxMind-DB
# (Apache-2.0 or MIT) and have the real GeoLite2 schema.
#
#   tests/integration/databases.sh
set -euo pipefail

# Renovate proposes new commits monthly. If a database changes, the checksum
# check fails: check the expected values in run.sh, then update the sums.
# renovate: maxmind-db
COMMIT=0eef25a46e20f4e96d27b951d0228efabe21323f
DIR="$(cd "$(dirname "$0")" && pwd)/databases"

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

mkdir -p "$DIR"
while read -r sum name; do
  if [[ -f "$DIR/$name" && $(sha256 "$DIR/$name") == "$sum" ]]; then
    continue
  fi
  curl -fsSL --proto '=https' -o "$DIR/$name" \
    "https://raw.githubusercontent.com/maxmind/MaxMind-DB/$COMMIT/test-data/$name"
  if [[ $(sha256 "$DIR/$name") != "$sum" ]]; then
    echo "checksum mismatch: $name" >&2
    rm -f "$DIR/$name"
    exit 1
  fi
done <<'SUMS'
75901b98ed6e58d3bd41af9985044b747a7ec0be1369f930c24f5e044427181a GeoLite2-ASN-Test.mmdb
f936702b51dcb6c94b286d77a6f182c31a1601baf4b27e8e896934deb41f49f2 GeoLite2-City-Test.mmdb
6996ce679243c7f719b901ebe3b490048af2fb5965163f083857533841154fd8 GeoLite2-Country-Test.mmdb
SUMS
