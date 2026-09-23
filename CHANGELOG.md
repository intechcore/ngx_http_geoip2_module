# Changelog

Changes of this fork. Upstream history is in the git log up to commit `445df24`.

## [Unreleased]

### Fixed
- A heap overflow in both modules: a uint128 value (34 characters) or a double with 14 or
  more integer digits went into a buffer of 20 bytes. The buffer now holds 64 bytes, and
  the write is bounded.
- `$var metadata` without a field read past the arguments of the directive, and `$var;`
  without arguments read past them as well. Both modules.

### Changed
- The http and the stream module share their database code in `ngx_geoip2_common.h`:
  opening, lookups with the cache, value formatting, variable arguments, metadata and
  `auto_reload`. A fix there applies to both modules.
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

### Added
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
  as the module image, `SHA256SUMS`, `LICENSE` and a provenance attestation.
- Builds, tests, images and releases for nginx stable as well as mainline. A Renovate bump of
  one branch publishes only that branch. The image tag `<nginx>` points to the latest build
  for that nginx version.
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
