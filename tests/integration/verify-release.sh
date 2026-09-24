#!/usr/bin/env bash
# Verifies the published artifacts of one nginx version the way users take
# them, for the architecture of the Docker host:
#
# 1. The files of the latest GitHub release: SHA256SUMS, LICENSE and the
#    build provenance attestation of each module.
# 2. Debian only: the attestation of the module image, and that its modules
#    equal the ones in the release.
# 3. A clean nginx:<version>-trixie or nginx:<version>-alpine image with the
#    released modules passes tests/run.sh and tests/integration/run.sh of the
#    commit the release was built from. Tests of a later commit may expect a
#    later behavior.
#
#   tests/integration/verify-release.sh <nginx version> <debian|alpine>
#
# Needs gh with a token (GH_TOKEN) for the attestations.
set -euo pipefail

VERSION=${1:?usage: verify-release.sh <nginx version> <debian|alpine>}
OS=${2:?usage: verify-release.sh <nginx version> <debian|alpine>}
REPO=intechcore/ngx_http_geoip2_module
IMAGE=ghcr.io/$REPO
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

case $(docker info --format '{{.Architecture}}') in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture" >&2; exit 2 ;;
esac

case $OS in
  debian) base="nginx:$VERSION-trixie" ;;
  alpine) base="nginx:$VERSION-alpine" ;;
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
tag_image="geoip2-release:$VERSION-$OS-$arch"
trap 'git -C "$ROOT" worktree remove --force "$work/src" >/dev/null 2>&1 || true
      rm -rf "$work"; docker rmi "$tag_image" >/dev/null 2>&1 || true' EXIT

# Releases are v<version>-<n>, up to 1.31.6-14 and 1.30.5-7 without the v.
# The image tag and the file names never carry the v.
release=$(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' |
  grep -E "^v?${VERSION//./\\.}-[0-9]+$" | sort -t- -k2 -n | tail -1 || true)
if [[ -z $release ]]; then
  echo "no release for nginx $VERSION" >&2
  exit 1
fi
tag=${release#v}
echo "release $release, $OS $arch"
suffix="$tag-$OS-$arch"

gh release download "$release" --repo "$REPO" --dir "$work" \
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

# The tests of the release commit: the tag points to it.
git -C "$ROOT" fetch -q origin "refs/tags/$release:refs/tags/$release" 2>/dev/null || true
git -C "$ROOT" worktree add -q --detach "$work/src" "$release"
tests="$work/src/tests"

echo "clean $base with the released modules, tests of $release"
mkdir "$work/context"
cp "$work/ngx_http_geoip2_module-$suffix.so" "$work/context/ngx_http_geoip2_module.so"
cp "$work/ngx_stream_geoip2_module-$suffix.so" "$work/context/ngx_stream_geoip2_module.so"
cp "$tests/nginx.conf" "$work/context/nginx.conf"
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

"$tests/run.sh" "$tag_image" | tail -1
# Releases before the integration tests have no tests/integration/run.sh.
if [[ -x $tests/integration/run.sh ]]; then
  "$tests/integration/run.sh" "$tag_image" | tail -1
fi
