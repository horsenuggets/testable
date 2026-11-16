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
| `ForbidFocus` | `boolean` | `false` | Fail the run when a focus modifier excluded any test |
| `Indent` | `string` | `"   "` | Indentation string used for nested test output |
| `MaxConcurrency` | `number` | `4` | Maximum number of tests to run in parallel |
| `Parallel` | `boolean` | `true` | Enable or disable parallel test execution |
| `PrintSkipped` | `boolean` | `false` | Include skipped tests in the output |
| `ReporterOutputs` | `{ [string]: string }` | `{}` | File paths for machine-readable reports, keyed by reporter name (see [Reporters](#reporters)) |
| `Reporters` | `{ "Text" \| "Json" \| "JUnit" \| "Lcov" }` | `{ "Text" }` | Reports that a run produces (see [Reporters](#reporters)) |
| `SlowestTests` | `number` | `0` | Number of slowest tests listed after the text report, or `0` to leave the list out |
| `Verbose` | `boolean` | `false` | Enable detailed logging during test execution |

Reset configuration to defaults with `Testable.resetConfig()`.

## Skipping, Todo Tests & Focus

Skipped tests never affect whether a run passes. Every skip variant takes an optional
reason as its last argument, and the reason is shown next to the test when `PrintSkipped`
is on...

```luau
itSKIP("retries the upload", function() end, "waiting on the new API")

describeSKIP("matchmaking", function()
    it("fills a lobby", function() end)
end, "needs a live server")

describe("trading", function()
    SKIP("blocked on the inventory rewrite")
end)

itFIXME("rounds prices", function() end, "off by one cent")
itTODO("rejects expired offers")
```

- `itSKIP` and `xit` → Skip one test.
- `describeSKIP`, `xdescribe`, and `SKIP()` → Skip a whole block. Its tests inherit the
  block's reason unless they carry their own.
- `itFIXME` and `FIXME()` → Skip a broken test with the reason `fixme`, followed by the
  optional message.
- `itTODO` → Record a test you intend to write. It takes a name only, so passing a body
  is an error, and it is reported as skipped with the reason `todo`.

**Focus Guard**

Focusing with `itFOCUS`, `fit`, `describeFOCUS`, `fdescribe`, or `FOCUS()` skips every
other test, and those tests get the reason `excluded by focus`. The summary always says
how many tests focus excluded. Because a focus modifier that gets committed by accident
would otherwise leave the run green, set `ForbidFocus` in CI to fail the run whenever
focus excluded a test...

```luau
Testable.configure({ ForbidFocus = process.env.CI ~= nil })
```

The failure counts as one failed test in the results, so `passed` is `false` and
`results.failureCount` goes up by one. Results also expose `results.focusExcludedCount`,
and each skipped result node carries its reason in `skipReason`.

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
