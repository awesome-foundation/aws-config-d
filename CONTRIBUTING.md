# Contributing

Pull requests are very welcome, especially those that:

- Fix bugs or resolve open issues
- Improve shell compatibility or portability
- Drive the mission forward: making it easy to manage per-organization AWS CLI config files

## Before you start

- Check existing issues and PRs to avoid duplicate work
- For larger changes, open an issue first to discuss the approach

## Submitting a PR

1. Fork the repo and create a feature branch from `master`
2. Make your changes
3. Run `./test.sh` and make sure all tests pass (requires Docker)
4. Add tests for new functionality
5. Open a PR with a clear description of what and why

## What we're looking for

- Bug fixes with a test that reproduces the issue
- New shell support (nushell, etc.)
- Improvements to the install/upgrade experience
- Better error messages and edge case handling

## What we'll probably decline

- Changes that add external dependencies (this is a single bash script by design)
- Features that make the tool opinionated about how you organize your AWS config
- Scope creep beyond managing `~/.aws/config` from `config.d/`

## Code style

- Bash, `set -euo pipefail`
- Keep it simple and portable (macOS + Linux)
- Functions prefixed with `_` are internal
- Tests run in Docker containers to verify across shells

## License

By contributing, you agree that your contributions will be licensed under the [MPL-2.0](LICENSE).
