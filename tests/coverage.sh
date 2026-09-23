#!/usr/bin/env bash
# Measures the test coverage of both modules. Runs tests/run.sh against the
# coverage image and writes the gcovr reports.
#
#   tests/coverage.sh <coverage image> <output directory>
#
# build it with: docker build --target coverage -t <image> .
#
# The output directory gets coverage.xml (SonarQube format), coverage.txt (the
# branches not covered) and compile_commands.json. The script fails below 100%
# line or branch coverage. nginx clears the environment of its workers, so the
# env directives pass the gcov settings on. The branches inside the
# NGX_GEOIP2_FORMAT and ngx_log_error macros are excluded: an allocation
# failure and a disabled log level.
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
  cp /build/compile_commands.json /out/ &&
  gcovr --root /build/module --sonarqube /out/coverage.xml \
    --txt /out/coverage.txt --txt-metric branch --txt-summary \
    --exclude-branches-by-pattern ".*(FORMAT|ngx_log_error)\(.*" \
    --fail-under-line 100 --fail-under-branch 100 \
    /build/nginx-*/objs'
