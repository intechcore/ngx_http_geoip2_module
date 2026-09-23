# ngx_http_geoip2_module (intechcore fork)

[![CI](https://github.com/intechcore/ngx_http_geoip2_module/actions/workflows/ci.yml/badge.svg)](https://github.com/intechcore/ngx_http_geoip2_module/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/intechcore/ngx_http_geoip2_module)](https://github.com/intechcore/ngx_http_geoip2_module/releases)
[![License: BSD-2-Clause](https://img.shields.io/badge/License-BSD_2--Clause-orange.svg)](LICENSE)

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=coverage)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Duplicated Lines (%)](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=duplicated_lines_density)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Lines of Code](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=ncloc)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Bugs](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=bugs)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=vulnerabilities)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Code Smells](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=code_smells)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)
[![Technical Debt](https://sonarcloud.io/api/project_badges/measure?project=intechcore_ngx_http_geoip2_module&metric=sqale_index)](https://sonarcloud.io/summary/new_code?id=intechcore_ngx_http_geoip2_module)

nginx modules that set variables from [MaxMind GeoIP2](https://dev.maxmind.com/geoip/) databases.
The lookup uses the client address, or an address from any variable. IPv4 and IPv6 are supported.
`ngx_http_geoip2_module` works in the `http` context, `ngx_stream_geoip2_module` in the `stream`
context.

This is a maintained fork of [leev/ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module).
Upstream has had no commits since 2024-04.

## Changes from upstream

Fixes:

- `auto_reload` returned the cached lookup result of the old, closed database for the same client
  address ([#134](https://github.com/leev/ngx_http_geoip2_module/issues/134)). From upstream PR
  [#138](https://github.com/leev/ngx_http_geoip2_module/pull/138) by Felipe Travi.
- `auto_reload` never loaded a new database file with an older mtime than the nginx start. The
  module now also compares the inode and the size. From the same PR.
- An invalid `auto_reload` interval crashed `nginx -t` in the stream module. Upstream fixed it in
  the http module only ([#90](https://github.com/leev/ngx_http_geoip2_module/issues/90)).
- A heap overflow in both modules for uint128 and large double values.
- An out of bounds read for `$var metadata` without a field, and for `$var` without arguments.

Changes in behavior:

- An unknown `metadata` field, or a wrong number of arguments, is a configuration error.

Additions:

- Prebuilt module images and release binaries for the official nginx images, amd64 and arm64,
  Debian and Alpine.
- Tests for both modules with 100% line and branch coverage, run in CI on every change.

See [CHANGELOG.md](CHANGELOG.md) for the details. Fixes go back upstream where possible.

## Installation

A dynamic module loads only into the nginx version it was built for. All prebuilt modules are
built with `--with-compat` for one nginx version. Renovate follows new nginx releases.

| Source | Modules | Loads into | Needs |
|---|---|---|---|
| Image `ghcr.io/intechcore/ngx_http_geoip2_module:<nginx>-<n>` | http | `nginx:<nginx>-trixie` | `libmaxminddb0` |
| Release file `*-<nginx>-<arch>.so` | http, stream | `nginx:<nginx>-trixie`, nginx.org packages for trixie | `libmaxminddb0` |
| Release file `*-<nginx>-alpine-<arch>.so` | http, stream | `nginx:<nginx>-alpine` | `libmaxminddb-libs` |

`<n>` counts the builds for one nginx version. Each image tag has a
[GitHub release](https://github.com/intechcore/ngx_http_geoip2_module/releases) with the same
name. A release holds the http and the stream module for amd64 and arm64, `SHA256SUMS` and
`LICENSE`.

### Docker image

The image holds only `/ngx_http_geoip2_module.so`. Copy it into the nginx image:

```dockerfile
FROM nginx:1.31.6-trixie
RUN apt-get update && apt-get install -y --no-install-recommends libmaxminddb0 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/intechcore/ngx_http_geoip2_module:1.31.6-6 \
     /ngx_http_geoip2_module.so /usr/lib/nginx/modules/
```

Verify the build provenance of an image:

```sh
gh attestation verify oci://ghcr.io/intechcore/ngx_http_geoip2_module:1.31.6-6 \
  --owner intechcore
```

### Release binaries

Download a module from the latest release, check it and install it. For another nginx version,
pass its tag to `gh release download`. For Alpine, use the `-alpine-` files.

```sh
gh release download --repo intechcore/ngx_http_geoip2_module \
  --pattern 'ngx_http_geoip2_module-*-amd64.so' --pattern SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS
gh attestation verify ngx_http_geoip2_module-*-amd64.so --owner intechcore
sudo install -m 644 ngx_http_geoip2_module-*-amd64.so \
  /usr/lib/nginx/modules/ngx_http_geoip2_module.so
```

### Build from source

1. Install [libmaxminddb](https://github.com/maxmind/libmaxminddb) with its headers, for
   example `libmaxminddb-dev` on Debian.
2. Download and unpack the nginx source of your nginx version:

   ```sh
   curl -fsSLO https://nginx.org/download/nginx-1.31.6.tar.gz
   tar xzf nginx-1.31.6.tar.gz
   cd nginx-1.31.6
   ```

3. Build the modules. `--with-stream` adds the stream module:

   ```sh
   # dynamic modules, objs/ngx_http_geoip2_module.so and objs/ngx_stream_geoip2_module.so
   ./configure --with-compat --with-stream --add-dynamic-module=/path/to/ngx_http_geoip2_module
   make modules

   # or a static http module, built into nginx
   ./configure --add-module=/path/to/ngx_http_geoip2_module
   make
   make install
   ```

4. Load a dynamic module at the top of `nginx.conf`:

   ```nginx
   load_module modules/ngx_http_geoip2_module.so;
   load_module modules/ngx_stream_geoip2_module.so;
   ```

The free GeoLite2 databases are available from
[MaxMind](https://dev.maxmind.com/geoip/geolite2-free-geolocation-data) after sign up.

## Configuration

```nginx
http {
    geoip2 /etc/maxmind-country.mmdb {
        auto_reload 5m;
        $geoip2_metadata_country_build metadata build_epoch;
        $geoip2_data_country_code default=US source=$variable_with_ip country iso_code;
        $geoip2_data_country_name country names en;
    }

    geoip2 /etc/maxmind-city.mmdb {
        $geoip2_data_city_name default=London city names en;
    }

    fastcgi_param COUNTRY_CODE $geoip2_data_country_code;
    fastcgi_param COUNTRY_NAME $geoip2_data_country_name;
    fastcgi_param CITY_NAME    $geoip2_data_city_name;
}

stream {
    geoip2 /etc/maxmind-country.mmdb {
        $geoip2_data_country_code default=US source=$remote_addr country iso_code;
    }
}
```

### geoip2

```nginx
geoip2 <path to .mmdb> { ... }
```

Context: `http`, `stream`. Opens a database. A relative path starts from the nginx prefix. Each
file can have one `geoip2` block per context.

### Variables

```nginx
$variable_name [default=<value>] [source=$variable_with_ip] <path> ...;
```

- `path` is the path of the value in the database record, for example `country iso_code`. An
  array element takes its index: `subdivisions 0 iso_code`.
- `default` is the value when the database has no value at the path. Without it, the variable is
  empty.
- `source` is a variable that holds the address to look up. Without it, the module uses the
  client address. In `http` that is the address after `geoip2_proxy`.

The value of each data type:

| MMDB type | Value |
|---|---|
| utf8_string, bytes | the content |
| boolean | `1` or `0` |
| uint16, uint32, int32, uint64 | the decimal number |
| float, double | the number with 5 decimals, for example `1.50000` |
| uint128 | hex with `0x` and 32 digits |
| map, array | not found: the default value, or empty |

Find the path with [mmdblookup](https://maxmind.github.io/libmaxminddb/mmdblookup.html):

```console
$ mmdblookup --file /usr/share/GeoIP/GeoIP2-Country.mmdb --ip 8.8.8.8 country names en

  "United States" <utf8_string>
```

This is the variable:

```nginx
$country_name "default=United States" source=$remote_addr country names en;
```

### Metadata

```nginx
$variable_name metadata <field>;
```

| Field | Value |
|---|---|
| `build_epoch` | the build time of the database, in seconds since the epoch |
| `last_check` | the last time `auto_reload` checked the file |
| `last_change` | the mtime of the loaded file after a reload, else the nginx start |

### auto_reload

```nginx
auto_reload <interval>;
```

Default: off. The module checks the file at most once per interval, after a request or a stream
session. It loads the file again if the mtime is newer, or if the inode or the size has changed.
If the file is missing or broken, the module logs an error and keeps the loaded database.

### geoip2_proxy, geoip2_proxy_recursive

```nginx
geoip2_proxy <cidr>;
geoip2_proxy_recursive on | off;
```

Context: `http`. They work like
[geoip_proxy](https://nginx.org/en/docs/http/ngx_http_geoip_module.html#geoip_proxy) of the
nginx geoip module. For a request from a trusted address, the lookup uses the address from the
`X-Forwarded-For` header. With `geoip2_proxy_recursive on`, it uses the last address in the
header that is not trusted. A variable with `source=` ignores both directives.

## Development

### Layout

| Path | Content |
|---|---|
| `ngx_geoip2_common.h` | the code both modules share: databases, lookups, value formatting, metadata, `auto_reload` |
| `ngx_http_geoip2_module.c` | the http module: directives, client address, `geoip2_proxy`, variables |
| `ngx_stream_geoip2_module.c` | the stream module: directives, client address, variables |
| `config` | the nginx build configuration of both modules |
| `Dockerfile` | the builds, the test images and the published artifacts |
| `tests/` | `run.sh`, `coverage.sh`, the nginx configurations and the fixture databases |

The Dockerfile stages:

| Stage | Purpose |
|---|---|
| `build` | verifies the nginx source and builds both modules on Debian trixie |
| `test` | `nginx:<nginx>-trixie` with both modules, for `tests/run.sh` |
| `coverage` | a gcov build for `tests/coverage.sh` and SonarCloud |
| `build-alpine`, `test-alpine` | the same build and test image for `nginx:<nginx>-alpine` |
| `binaries`, `binaries-alpine` | the modules as files for the release |
| `module` | the published image, the default stage |

### Build and test

```sh
make test          # build for NGINX_VERSION in the Dockerfile and run tests/run.sh
make test-alpine   # the same for nginx:<nginx>-alpine
make coverage      # run the tests on the gcov build, fail below 100% coverage
make module        # build the module image
make fixtures      # regenerate tests/fixtures/*.mmdb
```

`tests/run.sh` starts nginx in the test image and sends every request from inside the container.
It checks lookups, every data type, metadata, `geoip2_proxy`, `auto_reload` and its errors, and
every configuration error. The stream checks send the client address in a PROXY protocol header.
The fixture databases come from `tests/fixtures/generate`.

`tests/coverage.sh` runs the same tests on the gcov build and fails below 100% line or branch
coverage. `GCOVR_EXCL` comments mark the code no test can reach, such as allocation failures.

### CI and releases

| Event | What runs |
|---|---|
| A pull request | CI builds both modules and runs `tests/run.sh` on Debian and Alpine, on amd64 and arm64 runners. ShellCheck checks the scripts in `tests/`, Hadolint checks the `Dockerfile`. SonarCloud and CodeQL analyze the code. |
| A merge to `master` that changes `config`, `ngx_*.c`, `ngx_*.h`, `Dockerfile` or `keys/` | The publish workflow runs the tests again. It then pushes the image `<nginx>-<n>` and creates the GitHub release with the same tag. |
| A new `nginx:<version>-trixie` image | Renovate opens a pull request that sets the new `NGINX_VERSION` in the `Dockerfile`. Its merge publishes the modules for that nginx version. |

The image and the release files carry a build provenance attestation.

### nginx source signature

The build downloads the nginx source from nginx.org and checks its GPG signature. The public
keys of the nginx release managers are in `keys/`. If a new nginx release is signed with a key
that is not in `keys/`, the build fails on purpose. To fix it:

1. Find the new key on <https://nginx.org/en/pgp_keys.html>.
2. Add the key file to `keys/`.
3. Open a pull request.

## License

BSD-2-Clause, see [LICENSE](LICENSE).

- Copyright (C) Lee Valentine.
- The stream module and the shared code: also Copyright (C) Andrei Belov.
- The modules are based on the nginx geoip modules by Igor Sysoev.
