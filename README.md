# ngx_http_geoip2_module (intechcore fork)

[![CI](https://github.com/intechcore/ngx_http_geoip2_module/actions/workflows/ci.yml/badge.svg)](https://github.com/intechcore/ngx_http_geoip2_module/actions/workflows/ci.yml)
[![License: BSD-2-Clause](https://img.shields.io/badge/License-BSD_2--Clause-orange.svg)](LICENSE)

A maintained fork of [leev/ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module).
Upstream has had no commits since 2024-04. This fork adds:

- Fixes for `auto_reload`, from upstream PR [#138](https://github.com/leev/ngx_http_geoip2_module/pull/138)
  by Felipe Travi:
  - After a reload the module returned the cached lookup result of the old, closed database
    for the same client address ([#134](https://github.com/leev/ngx_http_geoip2_module/issues/134)).
  - A new database file with an older mtime than the nginx start was never loaded. The
    module now also checks the inode and the size.
- A fix for the stream module: an invalid `auto_reload` interval crashed `nginx -t`. Upstream
  fixed the same line in the http module only.
- Fixes found by the tests: a heap overflow for uint128 and large double values, and an
  out of bounds read for `$var metadata` without a field.
- Tests for the http and the stream module with 100% line and branch coverage: every data
  type, lookups, `geoip2_proxy`, metadata, `auto_reload` and its errors, and invalid
  configuration. See `tests/`.
- Prebuilt module images for the official nginx images (Debian trixie), amd64 and arm64.

The module code otherwise stays as in upstream. Fixes go back upstream where possible.

## Prebuilt module image

`ghcr.io/intechcore/ngx_http_geoip2_module:<nginx version>-<n>` holds only
`/ngx_http_geoip2_module.so`, built for `nginx:<nginx version>-trixie`. `<n>` counts the builds
for one nginx version. A dynamic module loads only into the nginx version it was built for.

```dockerfile
FROM nginx:1.31.6-trixie
RUN apt-get update && apt-get install -y --no-install-recommends libmaxminddb0 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/intechcore/ngx_http_geoip2_module:1.31.6-1 \
     /ngx_http_geoip2_module.so /usr/lib/nginx/modules/
```

Each image carries a build provenance attestation:

```sh
gh attestation verify oci://ghcr.io/intechcore/ngx_http_geoip2_module:1.31.6-1 \
  --owner intechcore
```

The image holds the http module only. The stream module is built and tested, but it is not
published.

## Build and test

```sh
make test            # build the module for NGINX_VERSION in the Dockerfile, run tests/run.sh
make coverage        # run the tests on a gcov build, fail below 100% coverage
make module          # build the module image
make fixtures        # regenerate tests/fixtures/*.mmdb
```

SonarCloud analyzes every pull request and `master`, with the coverage of `tests/run.sh`:
the `coverage` build stage compiles both modules with gcov, and CI runs the same tests on it.
CI fails below 100% line or branch coverage. `GCOVR_EXCL` comments in the sources mark the
code no test can reach, such as allocation failures.

Renovate bumps `NGINX_VERSION` when a new `nginx:<version>-trixie` image appears. CI builds
and tests the module on native amd64 and arm64 runners. A merge to `master` publishes the
module image for that nginx version.

The build verifies the nginx source tarball against the release manager keys in `keys/`.
A release signed by another key fails the build. Check the new key on
https://nginx.org/en/pgp_keys.html, then add it.

---

The upstream README follows.

Description
===========

**ngx_http_geoip2_module** - creates variables with values from the maxmind geoip2 databases based on the client IP (default) or from a specific variable (supports both IPv4 and IPv6)

The module now supports nginx streams and can be used in the same way the http module can be used.

## Installing
First install [libmaxminddb](https://github.com/maxmind/libmaxminddb) as described in its [README.md
file](https://github.com/maxmind/libmaxminddb/blob/main/README.md#installing-from-a-tarball).

#### Download nginx source
```
wget http://nginx.org/download/nginx-VERSION.tar.gz
tar zxvf nginx-VERSION.tar.gz
cd nginx-VERSION
```

##### To build as a dynamic module (nginx 1.9.11+):
```
./configure --with-compat --add-dynamic-module=/path/to/ngx_http_geoip2_module
make modules
```

This will produce ```objs/ngx_http_geoip2_module.so```. It can be copied to your nginx module path manually if you wish.

Add the following line to your nginx.conf:
```
load_module modules/ngx_http_geoip2_module.so;
```

##### To build as a static module:
```
./configure --add-module=/path/to/ngx_http_geoip2_module
make
make install
```

##### If you need stream support, make sure to compile with stream:
```
./configure --add-dynamic-module=/path/to/ngx_http_geoip2_module --with-stream
OR
./configure --add-module=/path/to/ngx_http_geoip2_module --with-stream
```


## Download Maxmind GeoLite2 Database (optional)
The free GeoLite2 databases are available from [Maxminds website](http://dev.maxmind.com/geoip/geoip2/geolite2/) (requires signing up)

## Example Usage:
```
http {
    ...
    geoip2 /etc/maxmind-country.mmdb {
        auto_reload 5m;
        $geoip2_metadata_country_build metadata build_epoch;
        $geoip2_data_country_code default=US source=$variable_with_ip country iso_code;
        $geoip2_data_country_name country names en;
    }

    geoip2 /etc/maxmind-city.mmdb {
        $geoip2_data_city_name default=London city names en;
    }
    ....

    fastcgi_param COUNTRY_CODE $geoip2_data_country_code;
    fastcgi_param COUNTRY_NAME $geoip2_data_country_name;
    fastcgi_param CITY_NAME    $geoip2_data_city_name;
    ....
}

stream {
    ...
    geoip2 /etc/maxmind-country.mmdb {
        $geoip2_data_country_code default=US source=$remote_addr country iso_code;
    }
    ...
}
```

##### Metadata:
Retrieve metadata regarding the geoip database.
```
$variable_name metadata <field>
```
Available fields:
  - build_epoch: the build timestamp of the maxmind database.
  - last_check: the last time the database was checked for changes (when using auto_reload)
  - last_change: the last time the database was reloaded (when using auto_reload)

An unknown field or a missing field is a configuration error.

##### Autoreload (default: disabled):
Enabling auto reload will have nginx check the modification time of the database at the specified
interval and reload it if it has changed.
```
auto_reload <interval>
```

##### GeoIP:
```
$variable_name [default=<value] [source=$variable_with_ip] path ...
```
If default is not specified, the variable will be empty if not found.

If source is not specified, $remote_addr will be used to perform the lookup.

To find the path of the data you want (eg: country names en), use the [mmdblookup tool](https://maxmind.github.io/libmaxminddb/mmdblookup.html):

```
$ mmdblookup --file /usr/share/GeoIP/GeoIP2-Country.mmdb --ip 8.8.8.8

  {
    "country":
      {
        "geoname_id":
          6252001 <uint32>
        "iso_code":
          "US" <utf8_string>
        "names":
          {
            "de":
              "USA" <utf8_string>
            "en":
              "United States" <utf8_string>
          }
      }
  }

$ mmdblookup --file /usr/share/GeoIP/GeoIP2-Country.mmdb --ip 8.8.8.8 country names en

  "United States" <utf8_string>
```

This translates to:

```
$country_name "default=United States" source=$remote_addr country names en
```

##### Additional Commands:
These commands works the same as the original ngx_http_geoip_module documented here: http://nginx.org/en/docs/http/ngx_http_geoip_module.html#geoip_proxy.

However, if you provide the `source=$variable_with_ip` option on a variable, these settings will be ignored for that particular variable.

```
geoip2_proxy < cidr >
```
Defines trusted addresses.  When a request comes from a trusted address, an address from the "X-Forwarded-For" request header field will be used instead.

```
geoip2_proxy_recursive < on | off >
```
If recursive search is disabled then instead of the original client address that matches one of the trusted addresses, the last address sent in "X-Forwarded-For" will be used. If recursive search is enabled then instead of the original client address that matches one of the trusted addresses, the last non-trusted address sent in "X-Forwarded-For" will be used.
