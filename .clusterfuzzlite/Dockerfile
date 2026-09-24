# Builder image for ClusterFuzzLite. fuzz/build.sh does the work.
FROM gcr.io/oss-fuzz-base/base-builder@sha256:14b5fea57004f2f4edcfa212aa8c77397244f307a37eb216277ac40ec0155b1e

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl gnupg gpgv libmaxminddb-dev zip && \
    rm -rf /var/lib/apt/lists/*

COPY . $SRC/ngx_http_geoip2_module
COPY .clusterfuzzlite/build.sh $SRC/
WORKDIR $SRC/ngx_http_geoip2_module
