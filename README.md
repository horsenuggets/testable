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

## Requiring the Spec API

Specs can require `describe`, `it`, `expect`, and the rest from Testable instead of using
them as injected globals. Required functions are fully typed, work the same on Lune and
Roblox, and don't need a list of globals in `.luaurc`...

```luau
local Testable = require("@devpackages/testable")
local describe, it, expect = Testable.describe, Testable.it, Testable.expect
local beforeEach = Testable.beforeEach

return function()
    describe("parser", function()
        beforeEach(function() end)

        it("reads an empty document", function()
            expect(parse("")).to.be.a("table")
        end)
    end)
end
```

Everything the injected globals offer is exported, including the lifecycle hooks, `fail`,
and the focus and skip variants (`fit`, `xit`, `fdescribe`, `xdescribe`, `itFOCUS`,
`itSKIP`, and so on). Injected globals keep working, and both styles can be mixed in one
run. Once every spec requires its functions, set `InjectGlobals = false` so that Testable
stops rewriting function environments, which lets Luau optimize spec code again.

**Late Registration**

Calling `describe`, `it`, or a hook after its block has been collected (e.g., from inside
a running test) is an error in both styles, rather than a registration that silently
never runs.

**Threads Started by a Test**

Testable ties `expect` and `fail` to a test through the coroutine that runs it, including
across yields. A thread that the test starts itself (e.g., with `task.spawn`) isn't tied
to it, so there `fail` and `expect.extend` raise an error and `expect` only offers the
built-in matchers. Wrap the function with `Testable.bindTest` to tie it to the test that
is running when `bindTest` is called...

```luau
it("fails from another thread", function()
    task.spawn(Testable.bindTest(function()
        fail("This fails the test above.")
    end))
end)
```

Injected globals behave the same way on the test's own coroutine. In other threads they
fall back to the test in their block that started most recently, as they always have.

**Custom Matcher Types**

`Testable.Expect` takes the shape of matchers added with `expect.extend`, so they can be
typed as well...

```luau
type Matchers = { beEven: () -> any }

local expect: Testable.Expect<Matchers> = Testable.expect :: any
```

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
| `InjectGlobals` | `boolean` | `true` | Inject `describe`, `it`, `expect`, and the rest into spec functions as globals |
| `MaxConcurrency` | `number` | `4` | Maximum number of tests to run in parallel |
| `Parallel` | `boolean` | `true` | Enable or disable parallel test execution |
| `PrintSkipped` | `boolean` | `false` | Include skipped tests in the output |
| `ReporterOutputs` | `{ [string]: string }` | `{}` | File paths for machine-readable reports, keyed by reporter name (see [Reporters](#reporters)) |
| `Reporters` | `{ "Text" \| "Json" \| "JUnit" \| "Lcov" }` | `{ "Text" }` | Reports that a run produces (see [Reporters](#reporters)) |
| `SlowestTests` | `number` | `0` | Number of slowest tests listed after the text report, or `0` to leave the list out |
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
the filter excluded are reported as skipped with the skip reason
`Excluded by the filter.`, and the summary and `results.filteredCount` say how many of
the skipped tests it accounts for...

```text
3 passed, 0 failed, 12 skipped (11 filtered out).
```

## Exit Codes

Test failures and tool errors are kept apart. A failing test (or coverage below
`CoverageThreshold`) makes `Testable.run` return `passed` as `false`. A tool error means
the run can't give a meaningful verdict, and `Testable.run` throws a `ToolError` for it
instead. These are the tool errors...

- `EmptyFilter` → `Filter` did not match any test, so nothing would have run.
- `EmptyCoverage` → `Coverage` is enabled with a `CoverageThreshold` above 0, but no
  executable lines were measured. The threshold is ignored while `Coverage` is off.
- `InvalidReporters` → `Reporters` and `ReporterOutputs` describe a combination that
  can't work, such as two reports on standard output.

`Testable.runToExitCode` wraps `Testable.run` and maps the outcome to `0` for a passing
run, `1` for test failures, and `2` for a tool error (also available as
`Testable.ExitCode`). It prints tool errors and rethrows any other error.

```luau
local exitCode = Testable.runToExitCode({ testRoot })
process.exit(exitCode)
```

To handle tool errors yourself, catch them with `pcall` and check them with
`Testable.ToolError.is`...

```luau
local ok, results, passed = pcall(Testable.run, { testRoot })

if not ok and Testable.ToolError.is(results) then
    print(results.Kind, results.Message)
end
```

## Reporters

A run prints the text report by default. Set `Reporters` to choose which reports it
produces, and `ReporterOutputs` to send machine-readable reports to files...

```luau
Testable.configure({
    Reporters = { "Text", "Json", "JUnit" },
    ReporterOutputs = { Json = "reports/results.json", JUnit = "reports/junit.xml" },
    SlowestTests = 5,
})
```

- `Text` → The status tree and summary, always on standard output. `SlowestTests` adds a
  list of the tests that took longest.
- `Json` → The results tree as a JSON document.
- `JUnit` → JUnit XML for CI test annotations, with one `testsuite` per spec root and a
  `classname` built from the describe path.
- `Lcov` → Coverage as an lcov tracefile for coverage services and editor gutters. It
  needs `Coverage` and `CoverageRoots` to be set.

A machine-readable reporter without a path in `ReporterOutputs` writes to standard output
instead. Only one report can use standard output, so that reporter has to be the only one
without a path, and `Text` has to be left out. In Lune, anything your tests print during
such a run goes to standard error instead, along with verbose logging, so standard output
holds nothing but the report. Writing files only works in Lune.

Every reporter is also a pure function from results to a string, which works in Roblox
too...

```luau
local results = Testable.run({ testRoot })
local json = Testable.Reporters.JsonReporter.format(results)
local xml = Testable.Reporters.JUnitReporter.format(results)
local tracefile = Testable.Reporters.LcovReporter.format(coverageReport)
```

**JSON Shape**

The document has a `Version` (currently `1`), the `Totals`, and one node per spec root in
`Suites`. Keys are always written in the same order...

```json
{
  "Version": 1,
  "Totals": { "Total": 3, "Passed": 1, "Failed": 1, "Skipped": 1, "Duration": 0.25 },
  "Suites": [
    {
      "Name": "MathTest",
      "FullName": "MathTest",
      "Type": "Describe",
      "Status": "Failure",
      "Duration": 0.25,
      "Children": [
        {
          "Name": "divides",
          "FullName": "MathTest > divides",
          "Type": "It",
          "Status": "Failure",
          "Duration": 0.125,
          "ErrorMessage": "Expected 2, got 3",
          "Children": []
        }
      ]
    }
  ]
}
```

`Type` is `"Describe"` or `"It"`, `Status` is `"Success"`, `"Failure"`, or `"Skipped"`,
and durations are in seconds. `ErrorMessage` is only present on nodes that failed, and
`SkipReason` is only present on skipped nodes that gave a reason.

**Durations**

Result nodes carry a `duration` field in seconds. Tests and describe blocks record how
long they ran, the results object records the whole run, and skipped tests have none.

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
