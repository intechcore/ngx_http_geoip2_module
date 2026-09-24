#!/bin/bash -eu
# ClusterFuzzLite entry point.
exec "$SRC/ngx_http_geoip2_module/fuzz/build.sh"
