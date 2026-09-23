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
# binaries holds both modules for the GitHub release, module (the default) is
# the published image. build-alpine, test-alpine and binaries-alpine do the
# same for the nginx:<version>-alpine image (musl).

# The two nginx branches. Renovate keeps both on the latest release: mainline
# has an odd minor version, stable an even one. CI builds each of them with
# --build-arg NGINX_VERSION=<version>.
# renovate: nginx mainline
ARG NGINX_MAINLINE=1.31.6
# renovate: nginx stable
ARG NGINX_STABLE=1.30.5
ARG NGINX_VERSION=${NGINX_MAINLINE}

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
    curl -fsSLO --proto '=https' --tlsv1.2 "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    curl -fsSLO --proto '=https' --tlsv1.2 "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc" && \
    gpgv --keyring ./nginx-keyring.gpg \
        "nginx-${NGINX_VERSION}.tar.gz.asc" "nginx-${NGINX_VERSION}.tar.gz" && \
    tar xzf "nginx-${NGINX_VERSION}.tar.gz"

COPY config ngx_geoip2_common.h ngx_http_geoip2_module.c ngx_stream_geoip2_module.c \
     module/

WORKDIR /build/nginx-${NGINX_VERSION}
RUN ./configure --with-compat --with-stream --add-dynamic-module=../module && \
    make modules && \
    cp objs/ngx_http_geoip2_module.so objs/ngx_stream_geoip2_module.so /build/

FROM nginx:${NGINX_VERSION}-trixie AS test
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends libmaxminddb0 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /build/ngx_http_geoip2_module.so /build/ngx_stream_geoip2_module.so \
     /usr/lib/nginx/modules/
COPY tests/nginx.conf /etc/nginx/nginx.conf

# Coverage build for SonarCloud, used by CI only. It rebuilds both modules
# (http and stream) with gcov instrumentation and records the compile commands
# with bear. Both modules then replace the test modules. tests/coverage.sh runs
# the workers as root, so they can write the gcov counters to a mounted
# directory.
FROM build AS coverage
ARG NGINX_VERSION
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends bear gcovr libmaxminddb0 && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build/nginx-${NGINX_VERSION}
RUN make clean && \
    ./configure --with-compat --with-stream --add-dynamic-module=../module \
        --with-cc-opt=--coverage --with-ld-opt=--coverage && \
    bear --output /build/compile_commands.json -- make modules && \
    cp objs/ngx_http_geoip2_module.so objs/ngx_stream_geoip2_module.so /usr/lib/nginx/modules/
COPY tests/nginx.conf /etc/nginx/nginx.conf

# The http and the stream module as files, for docker build --output. The
# publish workflow attaches them to the GitHub release.
FROM scratch AS binaries
COPY --from=build /build/ngx_http_geoip2_module.so /build/ngx_stream_geoip2_module.so /

# The same modules for the official nginx:<version>-alpine image, built against
# musl. The nginx source is the tarball the build stage verified.
FROM nginx:${NGINX_VERSION}-alpine AS build-alpine
ARG NGINX_VERSION
# hadolint ignore=DL3018
RUN apk add --no-cache \
        build-base \
        libmaxminddb-dev \
        linux-headers \
        openssl-dev \
        pcre2-dev \
        zlib-dev
WORKDIR /build
COPY --from=build /build/nginx-${NGINX_VERSION}.tar.gz ./
RUN tar xzf "nginx-${NGINX_VERSION}.tar.gz"
COPY config ngx_geoip2_common.h ngx_http_geoip2_module.c ngx_stream_geoip2_module.c \
     module/
WORKDIR /build/nginx-${NGINX_VERSION}
RUN ./configure --with-compat --with-stream --add-dynamic-module=../module && \
    make modules && \
    cp objs/ngx_http_geoip2_module.so objs/ngx_stream_geoip2_module.so /build/

# bash runs the stream checks of tests/run.sh inside the container.
FROM nginx:${NGINX_VERSION}-alpine AS test-alpine
# hadolint ignore=DL3018
RUN apk add --no-cache bash libmaxminddb-libs
COPY --from=build-alpine /build/ngx_http_geoip2_module.so \
     /build/ngx_stream_geoip2_module.so /usr/lib/nginx/modules/
COPY tests/nginx.conf /etc/nginx/nginx.conf

FROM scratch AS binaries-alpine
COPY --from=build-alpine /build/ngx_http_geoip2_module.so \
     /build/ngx_stream_geoip2_module.so /

FROM scratch AS module
ARG NGINX_VERSION
COPY --from=build /build/ngx_http_geoip2_module.so /ngx_http_geoip2_module.so
COPY LICENSE /LICENSE
# Nothing runs in this image. It only carries files for COPY --from.
USER 65534:65534
LABEL org.opencontainers.image.title="ngx_http_geoip2_module" \
      org.opencontainers.image.description="nginx GeoIP2 dynamic module for nginx ${NGINX_VERSION} (Debian trixie)" \
      org.opencontainers.image.source="https://github.com/intechcore/ngx_http_geoip2_module" \
      org.opencontainers.image.licenses="BSD-2-Clause" \
      org.opencontainers.image.version="${NGINX_VERSION}"
