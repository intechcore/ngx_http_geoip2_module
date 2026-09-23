# Changelog

Changes of this fork. Upstream history is in the git log up to commit `445df24`.

## [Unreleased]

### Fixed
- A heap overflow in both modules: a uint128 value (34 characters) or a double with 14 or
  more integer digits went into a buffer of 20 bytes. The buffer now holds 64 bytes, and
  the write is bounded.
- The stream module crashed `nginx -t` on an invalid `auto_reload` interval. It passed the
  string by value to `%V`. Upstream fixed the same line in the http module (#90), not in the
  stream module. Found by SonarCloud (c:S5270).
- `auto_reload` returned the cached lookup result of the old, closed database for the same
  client address after a reload (upstream #134). From upstream PR #138 by Felipe Travi.
- `auto_reload` never loaded a new database whose mtime was older than the nginx start. The
  module now also compares the inode and the size. From upstream PR #138 by Felipe Travi.

### Added
- Tests in `tests/`: lookups over IPv4 and IPv6, the default value, both reload cases, and
  an invalid `auto_reload` interval in http and stream.
  Test databases are generated with MaxMind `mmdbwriter` from `tests/fixtures/generate`.
- Docker build of the module inside the official `nginx:<version>-trixie` image. The nginx
  source tarball is verified against the release manager keys in `keys/`.
- CI on native amd64 and arm64 runners, and publishing of the module image
  `ghcr.io/intechcore/ngx_http_geoip2_module:<nginx>-<n>` with a provenance attestation.
- Renovate for the nginx version and the GitHub Actions, pinned by SHA.
- SonarCloud analysis in CI with test coverage. A `coverage` build stage compiles both modules
  with gcov and records the compile commands.
