#!/usr/bin/env bash
# Runs in the nginx container. Sends requests to the http server (50 per
# keep-alive connection) and connections to the stream server for the given
# seconds, from the given number of parallel clients of each kind. Writes the
# replies, one per line, to /tmp/http.replies and /tmp/stream.replies.
#
#   load.sh <seconds> <clients>
set -euo pipefail

end=$((SECONDS + ${1:?usage: load.sh <seconds> <clients>}))
clients=${2:?usage: load.sh <seconds> <clients>}

urls=()
for _ in $(seq 1 50); do
  urls+=(http://127.0.0.1:8080/)
done

http_client() {
  while ((SECONDS < end)); do
    curl -s -H 'X-IP: 203.0.113.10' "${urls[@]}" || true
  done
}

stream_client() {
  while ((SECONDS < end)); do
    if exec 3<>/dev/tcp/127.0.0.1/9000; then
      printf 'PROXY TCP4 203.0.113.10 127.0.0.1 1000 9000\r\n' >&3 || true
      cat <&3 || true
      exec 3<&-
    fi
  done
}

rm -f /tmp/http.* /tmp/stream.*
for i in $(seq 1 "$clients"); do
  http_client >"/tmp/http.$i" 2>/dev/null &
  stream_client >"/tmp/stream.$i" 2>/dev/null &
done
wait
cat /tmp/http.[0-9]* >/tmp/http.replies
cat /tmp/stream.[0-9]* >/tmp/stream.replies
