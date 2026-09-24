#!/usr/bin/env bash
# Prints the pinned nginx base image of a branch and system, from the
# Dockerfile. Pass it to the build as NGINX_IMAGE (debian) or
# NGINX_ALPINE_IMAGE (alpine).
#
#   scripts/nginx-image.sh mainline|stable debian|alpine
#
#   nginx:1.31.6-trixie@sha256:...
set -euo pipefail

case ${1:-}/${2:-} in
  mainline/debian) key=NGINX_IMAGE ;;
  mainline/alpine) key=NGINX_ALPINE_IMAGE ;;
  stable/debian) key=NGINX_STABLE_IMAGE ;;
  stable/alpine) key=NGINX_STABLE_ALPINE_IMAGE ;;
  *)
    echo "usage: $0 mainline|stable debian|alpine" >&2
    exit 2
    ;;
esac

image=$(awk -F= -v key="ARG $key" '$1 == key { print $2; exit }' "$(dirname "$0")/../Dockerfile")
if [[ ! $image =~ ^nginx:[0-9]+\.[0-9]+\.[0-9]+-[a-z]+@sha256:[0-9a-f]{64}$ ]]; then
  echo "ARG $key in the Dockerfile is not nginx:<version>-<system>@sha256:<digest>: '$image'" >&2
  exit 1
fi
echo "$image"
