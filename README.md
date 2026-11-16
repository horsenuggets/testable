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
| `Indent` | `string` | `"   "` | Indentation string used for nested test output |
| `MaxConcurrency` | `number` | `4` | Maximum number of tests to run in parallel |
| `Parallel` | `boolean` | `true` | Enable or disable parallel test execution |
| `PrintSkipped` | `boolean` | `false` | Include skipped tests in the output |
| `ReporterOutputs` | `{ [string]: string }` | `{}` | File paths for machine-readable reports, keyed by reporter name (see [Reporters](#reporters)) |
| `Reporters` | `{ "Text" \| "Json" \| "JUnit" \| "Lcov" }` | `{ "Text" }` | Reports that a run produces (see [Reporters](#reporters)) |
| `SlowestTests` | `number` | `0` | Number of slowest tests listed after the text report, or `0` to leave the list out |
| `Verbose` | `boolean` | `false` | Enable detailed logging during test execution |

Reset configuration to defaults with `Testable.resetConfig()`.

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

## Spec Discovery

On Lune, `Testable.Discovery` finds spec files from include globs, so a test script
doesn't have to list every spec by hand. It is only loaded on Lune and is `nil` on Roblox,
where specs are discovered from instances instead. Globs are relative to `Root`, which
defaults to the working directory. A `*` stops at a directory boundary, `**` spans any
depth, hidden files and directories are skipped, and the results are sorted. A set of
globs that matches nothing is an error.

```luau
const Testable = require("@devpackages/testable")

const testRoots = Testable.Discovery.discover({ Include = { "Tests/**/*.spec.luau" } })
const _, passed = Testable.run(testRoots)
```

Here is everything the module offers...

- `discover(options)` → Finds the specs and requires them, returning test roots for
  `Testable.run`. Pass `Files` to narrow the run to specific spec files.
- `findSpecs(options)` → Returns the matching spec file paths without requiring them.
- `findAffected(options)` → Returns the specs that changed or that transitively require
  one of the files in `Changed`.
- `findChanged(options)` → Returns the specs affected by everything that changed since the
  git ref in `Ref`, including uncommitted and untracked files.
- `watch(options)` → Calls `Run` with the affected specs whenever a file they depend on
  changes, and returns a handle with a `Stop` function.
- `runInChild(options)` → Runs a script in a child Lune process, passing spec files as
  trailing arguments.

Every function takes `Include`, and optionally `Exclude` and `Root`. Affected specs are
found through a graph of string requires that is built by scanning source files. It
follows `./` and `../` paths, `@self`, `init.luau` directories, and `.luaurc` aliases. A
changed `.luaurc` affects every spec.

### Changed-Only Runs

Only the specs affected by a branch need to run when `findChanged` narrows the list. A ref
that does not exist, or a root outside a git repository, raises an error. An empty result
means that nothing is affected, which is a clean outcome and not a failure.

```luau
const affected = Testable.Discovery.findChanged({
    Include = { "Tests/**/*.spec.luau" },
    Ref = "origin/main",
})

if #affected == 0 then
    print("No specs are affected.")
    process.exit(0)
end

const testRoots = Testable.Discovery.discover({
    Files = affected,
    Include = { "Tests/**/*.spec.luau" },
})
```

### Watch Mode

Lune caches required modules for as long as a process lives, so specs that run again in
the watching process would keep seeing the code it loaded first. Run each pass in a child
process instead. The watcher stays in the parent and hands the affected specs to the test
script, which loads them fresh...

```luau
Testable.Discovery.watch({
    Include = { "Tests/**/*.spec.luau" },
    Run = function(specFiles)
        Testable.Discovery.runInChild({
            Files = specFiles,
            Script = "Scripts/RunTests.exec.luau",
        })
    end,
})
```

The child script receives the spec files in `process.args` and passes them to `discover`
as `Files`. Changes are debounced (`Debounce`, in seconds), and files are polled every
`Interval` seconds. Hidden files are ignored, except for `.luaurc`. Every spec runs once
at the start unless `RunOnStart` is `false`.

This repository's own `Scripts/RunTests.exec.luau` is a complete example. It accepts
`--changed <ref>`, `--watch`, and a list of spec files.
