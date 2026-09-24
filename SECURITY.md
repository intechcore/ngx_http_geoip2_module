# Security policy

## Reporting a vulnerability

Report a vulnerability privately through GitHub:
https://github.com/intechcore/ngx_http_geoip2_module/security/advisories/new
(the **Security** tab, **Report a vulnerability**). Do not open a public issue for it.

We answer within a week. The fix goes into the next release, and its release notes name it.

## Supported versions

Only the latest release of each nginx branch, mainline and stable, gets fixes: the image
`ghcr.io/intechcore/ngx_http_geoip2_module:<nginx>` and the release files for the nginx version
the official nginx images ship. A new nginx version or base image publishes the modules again.

## Scope

This repository covers the module sources (`ngx_*.c`, `ngx_*.h`, `config`), the `Dockerfile`,
the scripts and the workflows.

Vulnerabilities in upstream software (nginx, libmaxminddb, the nginx base images) belong to the
upstream project. Tell us as well if this project is affected, so we can release a fix when the
upstream fix is out. Where an issue exists in leev/ngx_http_geoip2_module too, we also report it
there.
