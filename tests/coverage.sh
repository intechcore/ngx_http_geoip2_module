#!/usr/bin/env bash
# Measures the test coverage of both modules. Runs tests/run.sh against the
# coverage image and writes the gcovr reports.
#
#   tests/coverage.sh <coverage image> <output directory>
#
# build it with: docker build --target coverage -t <image> .
#
# The output directory gets coverage.xml (SonarQube format), coverage.txt (the
# lines and branches not covered) and compile_commands.json. nginx clears the
# environment of its workers, so the env directives pass the gcov settings on.
set -euo pipefail

IMAGE=${1:?usage: tests/coverage.sh <coverage image> <output directory>}
OUT=${2:?usage: tests/coverage.sh <coverage image> <output directory>}

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
GCOV="$(mktemp -d)"
# The workers run as root and write the counters as root.
trap 'docker run --rm -v "$GCOV:/cov" --entrypoint rm "$IMAGE" -rf /cov/build; rmdir "$GCOV"' EXIT

DOCKER_RUN_ARGS="-e GCOV_PREFIX=/cov -e GCOV_PREFIX_STRIP=0 -v $GCOV:/cov" \
  NGINX_GLOBALS="user root; env GCOV_PREFIX; env GCOV_PREFIX_STRIP;" \
  "$(dirname "$0")/run.sh" "$IMAGE"

docker run --rm -v "$GCOV:/cov" -v "$OUT:/out" --entrypoint sh "$IMAGE" -c '
  cp -a /cov/build/. /build/ &&
  gcovr --root /build/module --sonarqube /out/coverage.xml \
    --txt /out/coverage.txt --txt-metric branch --txt-summary /build/nginx-*/objs &&
  cp /build/compile_commands.json /out/'
