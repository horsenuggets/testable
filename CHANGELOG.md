# Changelog

## 1.0.0
- Added code coverage support via `debug.getcoverage` with `CoverageRoots` dictionary config
- Added `Coverage`, `CoverageRoots`, and `CoverageThreshold` configuration options
- Added `CoverageReporter` for formatted coverage output with ANSI colors and threshold checking
- Added dictionary syntax for test roots (`{ TestName = func }` alongside `{ { Name, Func } }`)
- Added Roblox cloud E2E tests via Open Cloud Luau Execution API (7 remote tests)
- Added coverage unit tests (14 tests for resolveRoots, collect, Config, and integration)
- Fixed TestBootstrap to support dict and array syntax in Roblox (not just Lune)
- Fixed coverage to gracefully degrade when `debug.iscoverageenabled` doesn't exist (Roblox VM)

## 0.1.2
- Added Roblox cloud E2E tests via Open Cloud Luau Execution API
- Added PublishE2EPlace script and E2E Rojo project
- Fixed TestBootstrap to support dict and array syntax in Roblox (not just Lune)
- Fixed coverage to gracefully degrade when debug.iscoverageenabled doesn't exist (Roblox VM)

## 0.1.1
- Added code coverage support via `debug.getcoverage` (requires lune 0.10.4-horse.14.2+)
- Added `Coverage`, `CoverageRoots`, and `CoverageThreshold` configuration options
- Added `CoverageReporter` for formatted coverage output with ANSI colors
- Added dictionary syntax for test roots (`{ TestName = func }` alongside `{ { Name, Func } }`)
- Added `DictSyntaxTest` test suite

## 0.1.0
- Changed to use luau-cicd submodule for CI/CD scripts instead of local copies

## 0.0.5
- Added `Testable.configure()` function for runtime configuration of test behavior
- Added `AlphabeticalSort` option to sort test output alphabetically
- Added `Indent` option for custom indentation string
- Added `MaxConcurrency` option for maximum concurrent tests in parallel mode
- Added `Parallel` option to enable/disable parallel test execution
- Added `PrintSkipped` option to show skipped tests in output
- Added `Verbose` option to enable verbose logging
- Added static analysis with luau-lsp to release checks workflow
- Added all Roblox and TestEZ globals to `.luaurc`
- Improved documentation with better README examples
- Standardized Luau file headers

## 0.0.4
- Changed version tags to no longer have a "v" prefix (use `0.0.4` instead of `v0.0.4`)

## 0.0.3
- Fixed wally authentication in publish workflow

## 0.0.2
- Removed pull_request triggers from test and format workflows
- Changed to compare version against last release tag instead of last commit
- Fixed tests to use git tags for version comparison

## 0.0.1
- Initial release of Testable, a Luau testing framework
- Added TestEZ-style API with `describe`, `it`, `expect`
- Added ANSI color support for CLI test output
- Added parallel test execution support
- Added version validation script for semantic versioning
- Added CI/CD workflows for testing, formatting, and releases
- Added automated wally publishing on release
