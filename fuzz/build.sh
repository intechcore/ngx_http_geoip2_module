#!/usr/bin/env bash
# Builds the fuzz targets. ClusterFuzzLite runs it in its builder image with
# CC, CFLAGS, LIB_FUZZING_ENGINE and OUT set (see .clusterfuzzlite/). The
# nginx core objects of the mainline version link into each target, and
# libmaxminddb links statically, so the target runs on the runner image.
set -euo pipefail

# Set by the ClusterFuzzLite builder image, or by hand for a local build.
: "${CC:?}" "${CXX:?}" "${CFLAGS?}" "${CXXFLAGS?}" "${LIB_FUZZING_ENGINE:?}" "${OUT:?}"

REPO=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$("$REPO/scripts/nginx-version.sh" mainline)
WORK=${WORK:-/tmp/fuzz-build}
mkdir -p "$WORK" "$OUT"
cd "$WORK"

# The same signature check as the Dockerfile.
cat "$REPO"/keys/*.key | gpg --dearmor > nginx-keyring.gpg
curl -fsSLO --proto '=https' --tlsv1.2 "https://nginx.org/download/nginx-${VERSION}.tar.gz"
curl -fsSLO --proto '=https' --tlsv1.2 "https://nginx.org/download/nginx-${VERSION}.tar.gz.asc"
gpgv --keyring ./nginx-keyring.gpg "nginx-${VERSION}.tar.gz.asc" "nginx-${VERSION}.tar.gz"
tar xzf "nginx-${VERSION}.tar.gz"
cd "nginx-${VERSION}"

# Core only: the lookup code needs pools, strings and logs, not http.
./configure --with-cc="$CC" --with-cc-opt="$CFLAGS" --with-ld-opt="$CFLAGS" \
    --without-http --without-pcre
make -j"$(nproc)" -f objs/Makefile objs/nginx

# nginx.o holds main(); the fuzzing engine brings its own.
objcopy --redefine-sym main=ngx_fuzz_unused_main objs/src/core/nginx.o

mapfile -t objects < <(find objs/src -name '*.o'; echo objs/ngx_modules.o)
# The flags are lists of options.
read -r -a cc_options <<<"$CFLAGS"
read -r -a cxx_options <<<"$CXXFLAGS"
read -r -a engine_options <<<"$LIB_FUZZING_ENGINE"

for target in "$REPO"/fuzz/fuzz_*.c; do
    name=$(basename "$target" .c)
    "$CC" "${cc_options[@]}" -I src/core -I src/event -I src/os/unix -I objs \
        -c "$target" -o "$name.o"
    "$CXX" "${cxx_options[@]}" "$name.o" "${objects[@]}" "${engine_options[@]}" \
        -Wl,-Bstatic -lmaxminddb -Wl,-Bdynamic -lcrypt -lpthread -ldl \
        -o "$OUT/$name"
done

# The test databases are the seed corpus.
(cd "$REPO/tests/fixtures" && zip -q -j "$OUT/fuzz_lookup_seed_corpus.zip" ./*.mmdb)
