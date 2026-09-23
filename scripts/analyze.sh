#!/usr/bin/env bash
# Static analysis of both modules. Runs in the analyze stage of the
# Dockerfile, on the nginx build tree of the coverage stage and its compile
# commands. Any finding fails it.
#
# 1. gcc -fanalyzer: paths through the code, such as NULL use, leaks and out
#    of bounds access. The build flags hold -Werror.
# 2. clang-tidy: the clang static analyzer, bugprone and cert checks.
# 3. cppcheck: warning, portability and performance checks, all branches.
set -euo pipefail

# commands: the directory and the compile command of each module, without
# -o, one tab separated pair per line.
commands() {
  python3 - <<'PYTHON'
import json, shlex
for entry in json.load(open("/build/compile_commands.json")):
    if entry["file"].endswith("_geoip2_module.c"):
        args = list(entry["arguments"])
        i = args.index("-o")
        del args[i:i + 2]
        print(entry["directory"] + "\t" + " ".join(shlex.quote(a) for a in args))
PYTHON
}

echo "gcc -fanalyzer"
while IFS=$'\t' read -r directory command; do
  (cd "$directory" && eval "$command -fanalyzer -o /dev/null")
  nginx=$directory
done < <(commands)
echo "  no findings"

# Checks left out, each for its reason:
# - insecureAPI.DeprecatedOrUnsafeBufferHandling wants memset_s and memcpy_s
#   of C11 Annex K, which neither glibc nor musl has.
# - easily-swappable-parameters, multi-level-implicit-pointer-conversion and
#   narrowing-conversions report the nginx API: handler signatures, void *
#   from the pools, ngx_flag_t for int flags.
checks="-*,clang-analyzer-*,-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling"
checks="$checks,bugprone-*,-bugprone-easily-swappable-parameters"
checks="$checks,-bugprone-multi-level-implicit-pointer-conversion,-bugprone-narrowing-conversions"
checks="$checks,cert-*"

echo "clang-tidy"
clang-tidy -p /build --quiet --checks="$checks" --warnings-as-errors='*' \
  --header-filter='ngx_geoip2_common\.h' \
  /build/module/ngx_http_geoip2_module.c /build/module/ngx_stream_geoip2_module.c
echo "  no findings"

echo "cppcheck"
cd "$nginx"
cppcheck --quiet --error-exitcode=1 --check-level=exhaustive \
  --enable=warning,portability,performance --std=c99 \
  --suppress=missingIncludeSystem --suppress=toomanyconfigs --file-filter='*geoip2*' \
  -I src/core -I src/event -I src/event/modules -I src/os/unix -I objs \
  -I src/http -I src/http/modules -I src/stream -I ../module \
  ../module/ngx_http_geoip2_module.c ../module/ngx_stream_geoip2_module.c
echo "  no findings"
