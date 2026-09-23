# Builds ngx_http_geoip2_module as a dynamic module for one nginx version.
#
# A dynamic module loads only into the nginx version it was built for, so the
# build runs inside the official nginx image of that version. The final stage
# is a scratch image that holds only the module. Consumers copy it:
#
#   COPY --from=ghcr.io/intechcore/ngx_http_geoip2_module:<nginx>-<n> \
#        /ngx_http_geoip2_module.so /usr/lib/nginx/modules/
#
# Stages: build compiles, test adds the module to nginx for tests/run.sh,
# module (the default) is the published image.

# renovate: nginx
ARG NGINX_VERSION=1.31.6

FROM nginx:${NGINX_VERSION}-trixie AS build
ARG NGINX_VERSION
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        gnupg \
        gpgv \
        libmaxminddb-dev \
        libpcre2-dev \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# The nginx release managers sign the source tarball. Their keys are kept in
# keys/ (from https://nginx.org/en/pgp_keys.html). A release signed by a key
# not in keys/ fails here on purpose: verify the new key, then add it.
COPY keys/ keys/
RUN cat keys/*.key | gpg --dearmor > nginx-keyring.gpg && \
    curl -fsSLO "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    curl -fsSLO "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc" && \
    gpgv --keyring ./nginx-keyring.gpg \
        "nginx-${NGINX_VERSION}.tar.gz.asc" "nginx-${NGINX_VERSION}.tar.gz" && \
    tar xzf "nginx-${NGINX_VERSION}.tar.gz"

COPY config ngx_http_geoip2_module.c ngx_stream_geoip2_module.c module/

WORKDIR /build/nginx-${NGINX_VERSION}
RUN ./configure --with-compat --add-dynamic-module=../module && \
    make modules && \
    cp objs/ngx_http_geoip2_module.so /build/

FROM nginx:${NGINX_VERSION}-trixie AS test
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends libmaxminddb0 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /build/ngx_http_geoip2_module.so /usr/lib/nginx/modules/
COPY tests/nginx.conf /etc/nginx/nginx.conf

# Coverage build for SonarCloud, used by CI only. It rebuilds both modules
# (http and stream) with gcov instrumentation and records the compile commands
# with bear. The http module then replaces the test module. Workers run as root
# here, so they can write the gcov counters to any mounted directory.
FROM build AS coverage
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends bear gcovr libmaxminddb0 && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build/nginx-${NGINX_VERSION}
RUN make clean && \
    ./configure --with-compat --with-stream --add-dynamic-module=../module \
        --with-cc-opt=--coverage --with-ld-opt=--coverage && \
    bear --output /build/compile_commands.json -- make modules && \
    cp objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/
COPY tests/nginx.conf /etc/nginx/nginx.conf
RUN sed -i '1i user root;' /etc/nginx/nginx.conf

FROM scratch AS module
ARG NGINX_VERSION
COPY --from=build /build/ngx_http_geoip2_module.so /ngx_http_geoip2_module.so
COPY LICENSE /LICENSE
LABEL org.opencontainers.image.title="ngx_http_geoip2_module" \
      org.opencontainers.image.description="nginx GeoIP2 dynamic module for nginx ${NGINX_VERSION} (Debian trixie)" \
      org.opencontainers.image.source="https://github.com/intechcore/ngx_http_geoip2_module" \
      org.opencontainers.image.licenses="BSD-2-Clause" \
      org.opencontainers.image.version="${NGINX_VERSION}"
