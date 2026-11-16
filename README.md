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
| `SnapshotStore` | `table?` | `nil` | Where snapshot files are kept, which defaults to the filesystem in Lune |
| `UpdateSnapshots` | `boolean` | `false` | Accept changed snapshots and remove obsolete ones |
| `Verbose` | `boolean` | `false` | Enable detailed logging during test execution |

Reset configuration to defaults with `Testable.resetConfig()`.

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

## Snapshots

Call `matchSnapshot` to compare a value against the one stored from an earlier run...

```luau
it("renders the summary", function()
    expect(render(report)).to.matchSnapshot()
    expect(render(report, { Compact = true })).to.matchSnapshot("compact layout")
end)
```

A value with nothing stored is written and passes, so review new snapshot files before
committing them. A value that equals the stored one passes, and a different value fails
with a line diff labeled by the snapshot's key. Set `UpdateSnapshots = true` to accept
changed values instead. This repository's own runner turns it on with
`./Scripts/RunTests.exec.luau --update-snapshots`.

Each key is the full test name (the spec name, describe blocks, and test joined by `>`)
followed by the snapshot's number within the test, or by the hint when one is given.
Values are serialized with sorted keys and no depth cap. Functions, threads, and userdata
are written as their type name (e.g., `<function>`), while a cyclic value or a table key
that is not a string, number, or boolean fails the assertion.

In Lune, snapshots live in a plain text file beside the spec, at
`__snapshots__/<spec file name>.snap`, and should be committed with the tests. Pass
`SnapshotPath` on a test root to choose another location...

```luau
Testable.run({
    { Name = "ReportTest", Func = require("./ReportTest.spec"), SnapshotPath = "Snapshots/Report.snap" },
})
```

Roblox has no filesystem, so set `SnapshotStore` to a table with `read(path)` (returning
the contents or `nil`) and `write(path, contents)` functions. Without one, `matchSnapshot`
fails there. `Testable.Snapshots.MemorySnapshotStore.new(files)` keeps files in a table
that you can seed before a run and persist afterward.

Stored snapshots that no test produced are listed as obsolete in the run summary, and
update mode removes them. Detection only covers snapshot files used during the run, and it
is skipped when the run was focused or when a test in the spec failed or was skipped.
