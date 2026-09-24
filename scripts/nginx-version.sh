#!/usr/bin/env bash
# Prints the nginx version of a branch, from the tag of its pinned base images
# in the Dockerfile. Fails when the Debian and the Alpine image of the branch
# hold different nginx versions.
#
#   scripts/nginx-version.sh mainline|stable
set -euo pipefail

if [[ ${1:-} != mainline && ${1:-} != stable ]]; then
  echo "usage: $0 mainline|stable" >&2
  exit 2
fi

# nginx:1.31.6-trixie@sha256:... gives 1.31.6.
version() {
  local tag
  tag=$("$(dirname "$0")/nginx-image.sh" "$1" "$2")
  tag=${tag#*:}
  echo "${tag%%-*}"
}

debian=$(version "$1" debian)
alpine=$(version "$1" alpine)
if [[ $debian != "$alpine" ]]; then
  echo "nginx $1: the Debian image is nginx $debian, the Alpine image nginx $alpine" >&2
  exit 1
fi
echo "$debian"
