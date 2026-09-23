#!/usr/bin/env bash
# Verifies the published artifacts of one nginx version the way users take
# them, for the architecture of the Docker host:
#
# 1. The files of the latest GitHub release: SHA256SUMS, LICENSE and the
#    build provenance attestation of each module.
# 2. Debian only: the attestation of the module image, and that its modules
#    equal the ones in the release.
# 3. A clean nginx:<version>-trixie or nginx:<version>-alpine image with the
#    released modules passes tests/run.sh and tests/integration/run.sh.
#
#   tests/integration/verify-release.sh <nginx version> <debian|alpine>
#
# Needs gh with a token (GH_TOKEN) for the attestations.
set -euo pipefail

VERSION=${1:?usage: verify-release.sh <nginx version> <debian|alpine>}
OS=${2:?usage: verify-release.sh <nginx version> <debian|alpine>}
REPO=intechcore/ngx_http_geoip2_module
IMAGE=ghcr.io/$REPO
HERE="$(cd "$(dirname "$0")" && pwd)"
TESTS="$(cd "$HERE/.." && pwd)"

case $(docker info --format '{{.Architecture}}') in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture" >&2; exit 2 ;;
esac

case $OS in
  debian) suffix="$VERSION-$arch"; base="nginx:$VERSION-trixie" ;;
  alpine) suffix="$VERSION-alpine-$arch"; base="nginx:$VERSION-alpine" ;;
  *) echo "usage: verify-release.sh <nginx version> <debian|alpine>" >&2; exit 2 ;;
esac

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

work="$(mktemp -d)"
tag_image="geoip2-release:$suffix"
trap 'rm -rf "$work"; docker rmi "$tag_image" >/dev/null 2>&1 || true' EXIT

tag=$(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' |
  grep -E "^${VERSION//./\\.}-[0-9]+$" | sort -t- -k2 -n | tail -1 || true)
if [[ -z $tag ]]; then
  echo "no release for nginx $VERSION" >&2
  exit 1
fi
echo "release $tag, $OS $arch"

gh release download "$tag" --repo "$REPO" --dir "$work" \
  --pattern "ngx_http_geoip2_module-$suffix.so" \
  --pattern "ngx_stream_geoip2_module-$suffix.so" \
  --pattern SHA256SUMS --pattern LICENSE

echo "checksums"
for module in http stream; do
  file="ngx_${module}_geoip2_module-$suffix.so"
  expected=$(awk -v f="$file" '$2 == f { print $1 }' "$work/SHA256SUMS")
  actual=$(sha256 "$work/$file")
  if [[ -z $expected || $expected != "$actual" ]]; then
    echo "checksum mismatch: $file" >&2
    exit 1
  fi
  echo "  ok   $file"
done
if ! grep -q "Redistribution and use in source and binary forms" "$work/LICENSE"; then
  echo "the release has no BSD license" >&2
  exit 1
fi
echo "  ok   LICENSE"

echo "attestations"
for module in http stream; do
  gh attestation verify "$work/ngx_${module}_geoip2_module-$suffix.so" --repo "$REPO" >/dev/null
  echo "  ok   ngx_${module}_geoip2_module-$suffix.so"
done

if [[ $OS == debian ]]; then
  echo "module image"
  gh attestation verify "oci://$IMAGE:$tag" --repo "$REPO" >/dev/null
  echo "  ok   attestation of $IMAGE:$tag"
  docker pull -q "$IMAGE:$tag" >/dev/null
  # The image has no command. The container never runs, docker cp reads it.
  id=$(docker create "$IMAGE:$tag" none)
  for module in http stream; do
    file="ngx_${module}_geoip2_module"
    if ! docker cp "$id:/$file.so" "$work/image-$module.so" >/dev/null ||
      [[ $(sha256 "$work/image-$module.so") != $(sha256 "$work/$file-$suffix.so") ]]; then
      docker rm "$id" >/dev/null
      echo "the image has no $file.so, or it differs from the release" >&2
      exit 1
    fi
    echo "  ok   the image $module module equals the release module"
  done
  docker rm "$id" >/dev/null
fi

echo "clean $base with the released modules"
mkdir "$work/context"
cp "$work/ngx_http_geoip2_module-$suffix.so" "$work/context/ngx_http_geoip2_module.so"
cp "$work/ngx_stream_geoip2_module-$suffix.so" "$work/context/ngx_stream_geoip2_module.so"
cp "$TESTS/nginx.conf" "$work/context/nginx.conf"
# The libraries the release notes name. bash runs the stream checks.
if [[ $OS == alpine ]]; then
  install='apk add --no-cache bash libmaxminddb-libs'
else
  install='apt-get update && apt-get install -y --no-install-recommends libmaxminddb0 && rm -rf /var/lib/apt/lists/*'
fi
docker build -q -t "$tag_image" -f - "$work/context" >/dev/null <<DOCKERFILE
FROM $base
RUN $install
COPY ngx_http_geoip2_module.so ngx_stream_geoip2_module.so /usr/lib/nginx/modules/
COPY nginx.conf /etc/nginx/nginx.conf
DOCKERFILE

"$TESTS/run.sh" "$tag_image" | tail -1
"$HERE/run.sh" "$tag_image" | tail -1
