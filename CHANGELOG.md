# Changelog

## 0.1.0

### Changed

- Use luau-cicd submodule for CI/CD scripts instead of local copies

## 0.0.5

### Added

- `Testable.configure()` function for runtime configuration of test behavior
  - `AlphabeticalSort`: Sort test output alphabetically
  - `Indent`: Custom indentation string
  - `MaxConcurrency`: Maximum concurrent tests in parallel mode
  - `Parallel`: Enable/disable parallel test execution
  - `PrintSkipped`: Show skipped tests in output
  - `Verbose`: Enable verbose logging
- Static analysis with luau-lsp added to release checks workflow
- All Roblox and TestEZ globals added to `.luaurc`

### Changed

- Improved documentation with better README examples
- Standardized Luau file headers

## 0.0.4

### Changed

- Version tags no longer have a "v" prefix (use `0.0.4` instead of `v0.0.4`)

## 0.0.3

### Fixed

- Fix wally authentication in publish workflow

## 0.0.2

### Changed

- Remove pull_request triggers from test and format workflows
- Compare version against last release tag instead of last commit

### Fixed

- Update tests to use git tags for version comparison

## 0.0.1

### Added

- Initial release of Testable, a Luau testing framework
- TestEZ-style API with `describe`, `it`, `expect`
- ANSI color support for CLI test output
- Parallel test execution support
- Version validation script for semantic versioning
- CI/CD workflows for testing, formatting, and releases
- Automated wally publishing on release
