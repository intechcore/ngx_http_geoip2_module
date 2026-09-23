# shellcheck shell=bash
# Helpers of tests/run.sh and tests/integration/run.sh. Source it after
# set -euo pipefail. The helpers act on the nginx container in $container and
# count the checks in $passed and $failed.

passed=0
failed=0
container=""

# Stop nginx gracefully, so an instrumented module can write its counters.
cleanup() {
  if [[ -n "$container" ]]; then
    docker stop -t 10 "$container" >/dev/null 2>&1 || true
    docker rm -f "$container" >/dev/null 2>&1 || true
    container=""
  fi
}

ok() {
  echo "  ok   $1"
  passed=$((passed + 1))
}

not_ok() {
  echo "  FAIL $1"
  failed=$((failed + 1))
}

# check <name> <expected> <actual>
check() {
  if [[ "$2" = "$3" ]]; then
    ok "$1"
  else
    not_ok "$1: expected '$2', got '$3'"
  fi
}

# check_match <name> <extended regex> <actual>
check_match() {
  if [[ "$3" =~ $2 ]]; then
    ok "$1"
  else
    not_ok "$1: expected /$2/, got '$3'"
  fi
}

# wait_for_nginx: wait up to 10s until nginx in $container answers on port
# 8080. Print its log and exit if it does not.
wait_for_nginx() {
  local _
  for _ in $(seq 1 50); do
    if docker exec "$container" curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  docker logs "$container" >&2
  echo "nginx did not start" >&2
  exit 1
}

# http <path> [<curl argument>...]: the response body without the newline.
http() {
  local path=$1
  shift
  docker exec "$container" curl -fsS "$@" "http://127.0.0.1:8080$path" | tr -d '\n'
}

# stream <port> [<client address>|unknown]: the reply of a stream server. The
# address goes in a PROXY protocol header, "unknown" sends PROXY UNKNOWN.
# Without an address, no header is sent.
stream() {
  local header=""
  case ${2:-} in
    "") ;;
    unknown) header="PROXY UNKNOWN" ;;
    *:*) header="PROXY TCP6 $2 ::1 1000 $1" ;;
    *) header="PROXY TCP4 $2 127.0.0.1 1000 $1" ;;
  esac
  docker exec "$container" bash -c \
    'exec 3<>"/dev/tcp/127.0.0.1/$0" && if [[ -n $1 ]]; then printf "%s\r\n" "$1" >&3; fi && cat <&3' \
    "$1" "$header" | tr -d '\n'
}

# logged <count> <fixed string>: wait up to 5s until the log holds the string
# at least count times. docker logs can lag behind nginx.
logged() {
  local _
  for _ in $(seq 1 25); do
    if [[ $(docker logs "$container" 2>&1 | grep -cF "$2") -ge $1 ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# check_logged <name> <count> <fixed string>
check_logged() {
  if logged "$2" "$3"; then
    ok "$1"
  else
    not_ok "$1: '$3' not logged $2 times"
  fi
}

# sanitized <output>: true if a sanitizer of the asan image reported an error.
sanitized() {
  grep -qE 'ERROR: AddressSanitizer|runtime error:' <<<"$1"
}

no_crash() {
  local logs
  logs=$(docker logs "$container" 2>&1)
  if sanitized "$logs"; then
    not_ok "$1: a sanitizer reported an error"
    grep -E -A20 'ERROR: AddressSanitizer|runtime error:' <<<"$logs" >&2
  elif grep -q "exited on signal" <<<"$logs"; then
    not_ok "$1: a worker crashed"
  else
    ok "$1: no worker crash"
  fi
}

# summary: print the counts, and fail if a check failed.
summary() {
  echo
  echo "$passed passed, $failed failed"
  [[ "$failed" -eq 0 ]]
}
