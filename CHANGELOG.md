# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Changes of this project. The history of leev/ngx_http_geoip2_module is in the git log up to
commit `445df24`.

## [Unreleased]

### Changed
- CI pins ShellCheck and sets a timeout on every job; CI and Fuzz cancel superseded pull request runs.

### Security
- Each release carries the SPDX SBOM of the module image for amd64 and arm64, and the image
  holds a signed SBOM attestation on each platform digest.
- CI lints the workflows with actionlint and audits them with zizmor.
- The nginx base images are pinned by the digest of their multi-arch index, for both branches,
  Debian and Alpine. The `Dockerfile` takes the full reference in `NGINX_IMAGE` and
  `NGINX_ALPINE_IMAGE`, and the nginx version comes from its tag. Renovate updates the tag and
  the digest, so each base change goes through a pull request and CI.
- Fuzzing: `fuzz/fuzz_lookup.c` feeds random MaxMind databases to the shared lookup code.
  A workflow runs it in Debian 13 with AddressSanitizer and UndefinedBehaviorSanitizer on
  pull requests and weekly. A first local run of 3.3 million inputs found nothing.
- Each release carries the signed provenance bundles of its files and of its image
  (`*.intoto.jsonl`), so the signatures travel with the downloads.
- `verify-release.yml` runs as a reusable workflow called by `publish.yml` instead of on
  `workflow_run`.
- The test database generator takes `golang.org/x/sys` 0.48.0 (GO-2026-5024). Renovate
  updates the generator again.
- `SECURITY.md` links the private vulnerability report form.

### Fixed
- The publish workflow counts git tags and package tags as taken build numbers, next to the
  releases, and never attaches a release to an existing tag. A deleted release could free its
  number, and the next release would have reused it and its old git tag.
- A float or double beyond the int64 range, NaN or infinity made nginx print undefined digits.
  The lookup now treats such a value as not found.
- A heap overflow in both modules: a uint128 value (34 characters) or a double with 14 or
  more integer digits went into a buffer of 20 bytes. The buffer now holds 64 bytes, and
  the write is bounded.
- `$var metadata` without a field read past the arguments of the directive, and `$var;`
  without arguments read past them as well. Both modules.

### Changed
- Releases and their git tags are named `v<nginx>-<n>` from the next release on, for example
  `v1.31.6-15`. Image tags and file names keep `<nginx>-<n>`. The build counter counts tags
  and releases with and without the `v`.
- The repository gained `.editorconfig`, a disclaimer in the README, and SECURITY.md and
  CONTRIBUTING.md in the shared layout. CI runs on `ubuntu-latest` and `ubuntu-24.04-arm`.
- The GitHub release notes start with a summary of what changed since the previous release of
  the branch: the nginx version move and the new CHANGELOG entries. Before, they listed the files
  only. `.github/scripts/release-notes.sh` writes the summary.
- A variable name that a geoip2 block already defines is a configuration error. Before, the
  last definition replaced the first one without a message.
- A missing database file at an `auto_reload` check is logged as `error`, not `emerg`. The
  module keeps the loaded database, so nginx is not in danger.
- The http and the stream module share their database code in `ngx_geoip2_common.h`:
  opening, lookups with the cache, value formatting, variable arguments, metadata,
  `auto_reload` and the value of a variable. A fix there applies to both modules.
- A `$var metadata` directive with an unknown field or a wrong number of arguments is now a
  configuration error. Before, the variable was empty at run time, and a field matched by
  its prefix only: `build_epochs` gave the build epoch.
- The stream module crashed `nginx -t` on an invalid `auto_reload` interval. It passed the
  string by value to `%V`. Upstream fixed the same line in the http module (#90), not in the
  stream module. Found by SonarCloud (c:S5270).
- `auto_reload` returned the cached lookup result of the old, closed database for the same
  client address after a reload (upstream #134). From upstream PR #138 by Felipe Travi.
- `auto_reload` never loaded a new database whose mtime was older than the nginx start. The
  module now also compares the inode and the size. From upstream PR #138 by Felipe Travi.
- Renovate takes its common rules from the shared preset `github>intechcore/renovate-config`,
  which also turns on OSV vulnerability alerts.

### Added
- `CONTRIBUTING.md`: build and test commands, tests with every change and a failing test first
  for a bug fix, Conventional Commits, signed commits, squash merge, the required checks and how
  to report a vulnerability. The README links it.
- Static analysis in CI with gcc -fanalyzer, clang-tidy and cppcheck (`make analyze`). A finding
  fails the build.
- The module image holds the stream module as well, `/ngx_stream_geoip2_module.so`.
- A workflow verifies the published artifacts after each publish and once a week: checksums,
  license, attestations, and all tests on clean nginx images with the released modules.
- Integration tests with the MaxMind test databases (real GeoLite2 City, Country and ASN
  schema) and behind proxies (a CDN, a load balancer and an upstream application in docker
  compose), and under load while the database is replaced and nginx reloads, for both
  modules, in CI on Debian, Alpine and the sanitizer build (`make integration`).
- The variable option `escape=uri` percent-encodes the value, for example for a request
  header to an upstream server that rejects non-ASCII bytes. Both modules. Upstream #125.
- Tests in `tests/` for the http and the stream module: every MMDB data type, lookups over
  IPv4 and IPv6, the default value, `geoip2_proxy`, metadata, the reload cases and reload
  errors, and invalid configuration. They cover 100% of the lines and branches, and CI
  fails below that. Test databases are generated with MaxMind `mmdbwriter` from
  `tests/fixtures/generate`.
- Docker build of the module inside the official `nginx:<version>-trixie` image. The nginx
  source tarball is verified against the release manager keys in `keys/`.
- CI on native amd64 and arm64 runners, and publishing of the module image
  `ghcr.io/intechcore/ngx_http_geoip2_module:<nginx>-<n>` with a provenance attestation.
- GitHub releases with the http and the stream module for amd64 and arm64, with the same tag
  as the module image, `SHA256SUMS`, `LICENSE` and a provenance attestation. The file names
  hold the release tag and the system, such as `ngx_http_geoip2_module-1.31.6-13-debian-amd64.so`.
- Builds, tests, images and releases for nginx stable as well as mainline. The image tag
  `<nginx>` points to the latest build for that nginx version.
- Renovate also updates the nginx versions in the README examples.
- The publish workflow skips an nginx version whose modules equal its last release, so a
  change of the CI stages in the Dockerfile publishes nothing.
- A CI job runs the tests on nginx and both modules built with AddressSanitizer and
  UndefinedBehaviorSanitizer (`make asan`). It finds the heap overflow fixed above.
- Builds and tests for the `nginx:<version>-alpine` image (musl). The releases hold these
  modules as `*-alpine-<arch>.so`.
- Renovate for the nginx version and the GitHub Actions, pinned by SHA.
- SonarCloud analysis in CI with test coverage. A `coverage` build stage compiles both modules
  with gcov and records the compile commands.
