#!/usr/bin/env bash
# Prints the nginx version of a branch, from the Dockerfile.
#
#   scripts/nginx-version.sh mainline|stable
set -euo pipefail

case ${1:-} in
  mainline) key=NGINX_MAINLINE ;;
  stable) key=NGINX_STABLE ;;
  *)
    echo "usage: $0 mainline|stable" >&2
    exit 2
    ;;
esac

awk -F= -v key="ARG $key" '$1 == key { print $2; exit }' "$(dirname "$0")/../Dockerfile"
