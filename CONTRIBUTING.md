# Contributing

Issues and pull requests are welcome. Open an issue first for a larger change, so we can agree on
the approach before you write code.

## Build and test

Everything builds in Docker, you need no local nginx. The `Makefile` wraps the `Dockerfile`
stages:

```sh
make test          # build for nginx mainline and run tests/run.sh
make test-alpine   # the same for nginx:<nginx>-alpine (musl)
make integration   # the MaxMind test databases, the proxy topology and the load test
make asan          # the tests with AddressSanitizer and UndefinedBehaviorSanitizer
make analyze       # gcc -fanalyzer, clang-tidy and cppcheck; a finding fails
make coverage      # the tests on the gcov build; fails below 100% line or branch coverage
make module        # build the module image
make fixtures      # regenerate tests/fixtures/*.mmdb from tests/fixtures/generate
```

Add `NGINX_BRANCH=stable` to build and test for nginx stable, for example
`make test NGINX_BRANCH=stable`. The README section "Development" describes the stages and the
test suites.

Fuzzing: `fuzz/fuzz_lookup.c` is a libFuzzer target for the shared lookup code. CI runs it on each
pull request that changes the module. The README section "Fuzzing" shows how to run it locally.

CI runs ShellCheck, Hadolint, actionlint, zizmor, the `test` jobs for mainline and stable on
Debian and Alpine, amd64 and arm64, `asan`, `analyze`, `sonar` and CodeQL for every pull request.

## Tests

1. New behavior comes with tests in `tests/run.sh`, for the http and the stream module where both
   have it.
2. A bug fix starts with a test that fails without the fix. Commit the test with the fix.
3. Coverage stays at 100% of lines and branches. Mark code that no test can reach, such as an
   allocation failure, with a `GCOVR_EXCL` comment and say why.
4. A new database value or type needs a fixture: extend `tests/fixtures/generate` and run
   `make fixtures`.

## Pull requests

1. Branch from the default branch `master` as `type/description`, for example
   `fix/empty-metadata`.
2. Keep one change per pull request. New behavior comes with tests; a bug fix adds a test that
   fails without it.
3. Write commit messages as [Conventional Commits](https://www.conventionalcommits.org/) without a
   scope: `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`, `test: ...`, `build: ...`,
   `ci: ...`, `chore: ...`.
4. Sign your commits. The default branch accepts verified signatures only.
5. Add an entry under `## [Unreleased]` in `CHANGELOG.md`, written for users: the release notes
   quote it. Update the README when behavior or configuration changes.

Pull requests are squash-merged once all required checks are green.

## Releases

Releases are automatic when a build input changes: the module sources, `config`, the
`Dockerfile` or `keys/`. The publish workflow skips a branch whose modules equal its last
release. The notes take the Unreleased entries added since the previous release of the branch,
see `.github/scripts/release-notes.sh`. To give a release its own heading, cut a
`## [<nginx>-<n>] - <date>` section, for example `## [1.31.6-15]`.

Keep `## [Unreleased]` on top of `CHANGELOG.md`. Its entries stay there across releases: the
notes compare it with the previous release, so no per-release section is needed.
