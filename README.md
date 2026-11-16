# testable

A Luau testing framework based off of TestEZ. Testable extends TestEZ with parallel test execution and support for [Lune](https://lune-org.github.io/docs), allowing you to run tests outside of the Roblox environment.

## Usage

```luau
local Testable = require("@devpackages/testable")

local testRoot = path.to.Tests
local results, passed = Testable.run({ testRoot })

if passed then
    print("All tests passed!")
else
    print("Some tests failed.")
end
```

See the [TestEZ documentation](https://roblox.github.io/testez/api-reference/) for details on writing tests.

## Configuration

Configure Testable using `Testable.configure()`:

```luau
local Testable = require("@devpackages/testable")

Testable.configure({
    AlphabeticalSort = false,  -- Sort test results alphabetically
    Indent = "   ",            -- Indentation string for test output
    MaxConcurrency = 4,        -- Maximum parallel tests
    Parallel = true,           -- Enable parallel test execution
    PrintSkipped = false,      -- Show skipped tests in output
    Verbose = false,           -- Enable verbose logging
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `AlphabeticalSort` | `boolean` | `false` | Sort test results alphabetically instead of definition order |
| `CoverageRows` | `number` | `20` | File rows listed in the coverage table before the rest fold into a summary row |
| `CoverageSort` | `"Percentage" \| "HitLines"` | `"Percentage"` | Order coverage rows by percentage or by hit lines, both descending |
| `Filter` | `string?` | `nil` | Only run tests whose full name contains this text (see [Filtering Tests](#filtering-tests)) |
| `Indent` | `string` | `"   "` | Indentation string used for nested test output |
| `MaxConcurrency` | `number` | `4` | Maximum number of tests to run in parallel |
| `Parallel` | `boolean` | `true` | Enable or disable parallel test execution |
| `PrintSkipped` | `boolean` | `false` | Include skipped tests in the output |
| `Verbose` | `boolean` | `false` | Enable detailed logging during test execution |

Reset configuration to defaults with `Testable.resetConfig()`.

## Filtering Tests

Set `Filter` to run only the tests whose full name contains the given text. A test's full
name is its module name, the phrases of its `describe` blocks, and its own phrase, joined
by single spaces (e.g., `PlayerTest inventory should stack items`).

```luau
Testable.configure({ Filter = "inventory should stack" })
```

The filter is a case-sensitive plain substring, so characters like `%`, `.`, and `(` have
no special meaning. Matching a module or `describe` name selects every test under it, and
an empty string clears the filter.

The filter narrows the run first, and focus (`fit`, `fdescribe`) then narrows what the
filter left. A focus on tests that the filter excluded has no effect, and a `describe`
block with no selected tests doesn't run its `beforeAll` and `afterAll` hooks. Tests that
the filter excluded are reported as skipped, and the summary and `results.filteredCount`
say how many of the skipped tests it accounts for...

```text
3 passed, 0 failed, 12 skipped (11 filtered out).
```

## Exit Codes

Test failures and tool errors are kept apart. A failing test (or coverage below
`CoverageThreshold`) makes `Testable.run` return `passed` as `false`. A tool error means
the run can't give a meaningful verdict, and `Testable.run` throws a `ToolError` for it
instead. These are the tool errors...

- `EmptyFilter` → `Filter` did not match any test, so nothing would have run.
- `EmptyCoverage` → `CoverageThreshold` is above 0 but coverage measured no executable
  lines.

`Testable.runToExitCode` wraps `Testable.run` and maps the outcome to `0` for a passing
run, `1` for test failures, and `2` for a tool error (also available as
`Testable.ExitCode`). It prints tool errors and rethrows any other error.

```luau
process.exit(Testable.runToExitCode({ testRoot }))
```

To handle tool errors yourself, catch them with `pcall` and check them with
`Testable.ToolError.is`...

```luau
local ok, results, passed = pcall(Testable.run, { testRoot })

if not ok and Testable.ToolError.is(results) then
    print(results.Kind, results.Message)
end
```

## Coverage

In Lune, set `Coverage = true` and `CoverageRoots` to report line coverage for every
module under the roots, including modules that no test required. Modules that tests load
with `luau.load` instead of `require` (e.g., inside a sandbox with a custom environment)
can count too. Register each loaded chunk with its source file path...

```luau
local chunk = luau.load(fs.readFile(path), { debugName = path, environment = sandbox })
Testable.Coverage.track(path, chunk)
local module = chunk()
```

A file can be tracked any number of times, and hits from every load are merged.
