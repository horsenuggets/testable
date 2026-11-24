# testable

A Luau testing framework based off of TestEZ. Testable extends TestEZ with parallel test
execution and support for [Lune](https://lune-org.github.io/docs), allowing you to run
tests outside of the Roblox environment.

## Usage

A spec is a module that returns a function. It requires `describe`, `it`, `expect`, and
whatever else it needs from Testable...

```luau
const Testable = require("@devpackages/testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

return function()
    describe("parser", function()
        it("reads an empty document", function()
            expect(parse("")).to.be.a("table")
        end)
    end)
end
```

A test script prints a report and receives the results along with whether every test
passed. On Roblox, `Testable.run` takes an instance whose `.spec` modules are collected.
On Lune, [Spec Discovery](#spec-discovery) finds the spec paths for `Testable.runFiles`,
which can run them locally or in isolated worker VMs...

```luau
const Testable = require("@devpackages/testable")

const files = Testable.Discovery.findSpecs({ Include = { "Tests/**/*.spec.luau" } })
const results, passed = Testable.runFiles(files)

if passed then
    print("All tests passed!")
else
    print("Some tests failed.")
end
```

`Testable.run` also accepts already-loaded test roots. A root can be a table with a `Name`
and a `Func`, which works on both platforms (e.g.,
`{ Name = "ParserTest", Func = require("./ParserTest.spec") }`). See the
[TestEZ documentation](https://roblox.github.io/testez/api-reference/) for the basics of
writing tests. The sections below cover what Testable adds, and their examples assume that
the functions they call were required as shown above.

## Writing Specs

Everything a spec can call is exported from Testable, including the lifecycle hooks
(`beforeAll`, `beforeEach`, `afterEach`, and `afterAll`), `fail`, and the focus and skip
variants (`fit`, `xit`, `fdescribe`, `xdescribe`, `itFOCUS`, `itSKIP`, and so on).
Required functions are fully typed, work the same on Lune and Roblox, and don't need a
list of globals in `.luaurc`.

**Injected Globals**

Specs written for TestEZ use the same functions as globals that Testable injects into the
spec function, without requiring anything. That style keeps working, and both styles can
be mixed in one run. Once every spec requires its functions, set `InjectGlobals = false`
so that Testable stops rewriting function environments, which lets Luau optimize spec code
again.

**Late Registration**

Calling `describe`, `it`, or a hook after its block has been collected (e.g., from inside
a running test) is an error in both styles, rather than a registration that silently never
runs.

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

const expect: Testable.Expect<Matchers> = Testable.expect :: any
```

## Matchers

On top of the TestEZ matchers (`equal`, `ok`, `near`, `throw`, and `a`), `expect` offers a
richer vocabulary in the same chain style. All of them can be negated with `.never`...

```luau
expect({ 1, { 2 } }).to.deepEqual({ 1, { 2 } })
expect("hello world").to.contain("world")
expect({ 1, 2, 3 }).to.have.length(3)
expect("abc123").to.match("%a+%d+")
expect(5).to.be.greaterThan(3)
expect(nil).never.to.be.truthy()
```

- `deepEqual(expected)` → Compares tables recursively by contents. NaN equals NaN, and
  cyclic tables are safe.
- `contain(item)` → Finds a plain substring in a string, or a deeply equal element in an
  array.
- `length(count)` → Checks `#value` for a string or a table.
- `match(pattern)` → Matches a string against a Luau string pattern.
- `greaterThan(bound)`, `greaterThanOrEqual(bound)`, `lessThan(bound)`, and
  `lessThanOrEqual(bound)` → Order two numbers or two strings.
- `truthy()` and `falsy()` → Check whether the value is anything but `false` and `nil`, or
  one of those two.
- `none()` → Checks that the value is exactly `nil`.
- `a(typeName)` → Accepts either the `typeof` name (e.g., `"Vector3"`) or the `type` name
  (e.g., `"userdata"`).
- `matchSnapshot(hint)` → Compares the value against the one stored from an earlier run
  (see [Snapshots](#snapshots)).

Failed comparisons report `Expected` and `Received` lines. Tables are pretty-printed with
sorted keys, and deeply nested values are shortened to `{...}` in the message only. Using
a matcher on the wrong kind of value (e.g., `greaterThan` with a table) fails the test
with a message that names the matcher, even under `.never`. These names are reserved, so
`expect.extend` rejects custom matchers that reuse them.

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
- `itTODO` → Record a test you intend to write. It takes a name only, so passing a body is
  an error, and it is reported as skipped with the reason `todo`.

**Focus Guard**

A test or block marked with `itFOCUS`, `fit`, `describeFOCUS`, `fdescribe`, or `FOCUS()`
skips every other test, and those tests get the reason `excluded by focus`. The summary
always says how many tests focus excluded. Because a focus modifier that gets committed by
accident would otherwise leave the run green, set `ForbidFocus` in CI to fail the run
whenever focus excluded a test...

```luau
Testable.configure({ ForbidFocus = process.env.CI ~= nil })
```

The failure counts as one failed test in the results, so `passed` is `false` and
`results.failureCount` goes up by one. Results also expose `results.focusExcludedCount`,
and each skipped result node carries its reason in `skipReason`.

## Timeouts

A test that yields forever (e.g., one waiting on a signal that never fires) would
otherwise hang the whole run. Set the `Timeout` option to give every test a time budget in
seconds. It's off by default, so tests may run for as long as they like until you set
it...

```luau
Testable.configure({ Timeout = 5 })
```

A single test can raise or lower its budget with an options table as the third argument of
`it` (or `itFOCUS` and `fit`). Use `math.huge` to turn the limit off for that test. The
option on a test works even when no `Timeout` is configured...

```luau
it("waits for a slow service", function()
    -- ...
end, { Timeout = 30 })
```

A test that runs past its budget is reported as failed with a message naming the budget,
its thread is cancelled, its `afterEach` hooks still run, and the rest of the run carries
on. Here's what else to know...

- Every `beforeEach` and `afterEach` hook gets the same budget as the test it surrounds,
  counted separately for each hook, so a slow hook doesn't use up the time of the test.
- The `beforeAll` and `afterAll` hooks get the configured budget, since they belong to no
  single test.
- Only code that yields can be interrupted. A busy loop that never yields blocks the Luau
  scheduler, so the budget can't stop it and the run still hangs. Work that doesn't yield
  but does return still counts against the budget, so a test that finishes over budget is
  reported as timed out.
- Cancelling a test stops its own thread only. Threads that the test started with
  `task.spawn` or `task.delay` keep running.

Any hook can set a budget of its own with an options table as its second argument, which
wins over the one it would inherit. Use `math.huge` to turn the limit off for that hook...

```luau
beforeAll(function()
    -- ...
end, { Timeout = 30 })
```

## Serial Tests

Tests run in parallel by default, so tests that share global state (a module-level
variable, `Testable.configure`, a file on disk) can see each other's changes. Mark a test
or a whole describe block as `Serial` to run it with no other test of the run executing at
the same time...

```luau
it("writes the shared fixture", function()
    -- ...
end, { Serial = true })

describe("configuration", function()
    -- ...
end, { Serial = true })
```

- A serial test waits for the tests that are already running to finish, and keeps new ones
  from starting until it is done.
- Every test under a serial describe block runs one at a time, and the block as a whole
  waits for the rest of the run.
- Serial tests anywhere in the run wait for each other, even across specs.
- Ordinary tests keep running in parallel, so only mark what shares state, since serial
  tests trade speed for isolation.

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
is skipped when the run was focused or filtered, or when a test or describe block in the
spec failed or was skipped.

## Configuration

Options are set with `Testable.configure()` before a run. Only the keys you pass change,
and `Testable.resetConfig()` puts every option back to its default...

```luau
const Testable = require("@devpackages/testable")

Testable.configure({
    MaxConcurrency = 8,
    PrintSkipped = true,
    Timeout = 5,
})
```

| Option              | Type                                        | Default        | Description                                                                                                                                |
| ------------------- | ------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `AlphabeticalSort`  | `boolean`                                   | `false`        | Sorts test results alphabetically instead of in definition order.                                                                          |
| `Coverage`          | `boolean`                                   | `false`        | Measures line coverage during the run, which only works in Lune (see [Coverage](#coverage)).                                               |
| `CoverageRoots`     | `any?`                                      | `nil`          | Script instances or string paths, optionally in a named dictionary, whose modules coverage is reported for.                                |
| `CoverageRows`      | `number`                                    | `20`           | File rows listed in the coverage table before the rest fold into a summary row.                                                            |
| `CoverageSort`      | `"Percentage" \| "HitLines"`                | `"Percentage"` | Orders coverage rows by percentage or by hit lines, both descending.                                                                       |
| `CoverageThreshold` | `number`                                    | `0`            | Fails the run when total coverage is below this percentage, from `0` to `100`.                                                             |
| `Filter`            | `string?`                                   | `nil`          | Only runs tests whose full name contains this text (see [Filtering Tests](#filtering-tests)).                                              |
| `ForbidFocus`       | `boolean`                                   | `false`        | Fails the run when a focus modifier excluded any test.                                                                                     |
| `Indent`            | `string`                                    | `"   "`        | Indentation string used for nested test output.                                                                                            |
| `InjectGlobals`     | `boolean`                                   | `true`         | Injects `describe`, `it`, `expect`, and the rest into spec functions as globals.                                                           |
| `MaxConcurrency`    | `number`                                    | `4`            | Maximum number of tests to run in parallel within each VM.                                                                                 |
| `Parallel`          | `boolean`                                   | `true`         | Runs tests in parallel instead of one after another.                                                                                       |
| `PrintSkipped`      | `boolean`                                   | `false`        | Includes skipped tests in the output.                                                                                                      |
| `ReporterOutputs`   | `{ [string]: string }`                      | `{}`           | File paths for machine-readable reports, keyed by reporter name (see [Reporters](#reporters)).                                             |
| `Reporters`         | `{ "Text" \| "Json" \| "JUnit" \| "Lcov" }` | `{ "Text" }`   | Reports that a run produces (see [Reporters](#reporters)).                                                                                 |
| `SlowestTests`      | `number`                                    | `0`            | Number of slowest tests listed after the text report, or `0` to leave the list out.                                                        |
| `SnapshotStore`     | `table?`                                    | `nil`          | Where snapshot files are kept, which defaults to the filesystem in Lune (see [Snapshots](#snapshots)).                                     |
| `SuiteOrder`        | `{ string }`                                | `{}`           | Preferred spec identities, followed by unlisted specs in alphabetical order.                                                               |
| `Timeout`           | `number?`                                   | `nil`          | Time budget in seconds for every test, or `nil` for no limit (see [Timeouts](#timeouts)).                                                  |
| `UpdateSnapshots`   | `boolean`                                   | `false`        | Accepts changed snapshots and removes obsolete ones (see [Snapshots](#snapshots)).                                                         |
| `Verbose`           | `boolean`                                   | `false`        | Logs details about the run while it executes.                                                                                              |
| `WorkerGroups`      | `{ { string } }`                            | `{}`           | Dense arrays of nonblank spec paths to keep in one worker. Overlapping groups are allowed (see [File-Oriented Runs](#file-oriented-runs)). |
| `WorkerSetup`       | `string?`                                   | `nil`          | Nonblank setup module path relative to the file run's root, called before specs are required, including with one worker.                   |
| `Workers`           | `number`                                    | `1`            | Finite positive integer worker limit for file-oriented runs. One uses the local pipeline; larger values use isolated actors.               |

A preferred suite order can put heavyweight tool checks before fixtures allocate their
place caches...

```luau
Testable.configure({ Parallel = false, SuiteOrder = { "ToolChecks", "BuildChecks" } })
```

Each identity is the case-sensitive spec name. Nested spec paths join their parent names
and spec name with single spaces. Preferences never rename, add, exclude, or duplicate
suites, and unknown identities are ignored so the same list can be used with a subset of
specs. Unlisted specs remain alphabetical. Ordering does not disable parallel execution;
set `Parallel = false` when suites must execute one after another. The list is copied when
configured and snapshotted before each run's discovery.

## Filtering Tests

Set `Filter` to run only the tests whose full name contains the given text. A test's full
name is its module name, the phrases of its `describe` blocks, and its own phrase, joined
by single spaces (e.g., `PlayerTest inventory should stack items`)...

```luau
Testable.configure({ Filter = "inventory should stack" })
```

The filter is a case-sensitive plain substring, so characters like `%`, `.`, and `(` have
no special meaning. Matching a module or `describe` name selects every test under it, and
an empty string clears the filter.

The filter narrows the run first, and focus (`fit`, `fdescribe`) then narrows what the
filter left. A focus on tests that the filter excluded has no effect, and a `describe`
block with no selected tests doesn't run its `beforeAll` and `afterAll` hooks. Tests that
the filter excluded are reported as skipped with the reason `excluded by filter`, and they
never count as excluded by focus. The summary and `results.filteredCount` say how many of
the skipped tests the filter accounts for...

```text
3 passed, 0 failed, 12 skipped (11 filtered out).
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
const results = Testable.run({ testRoot })
const json = Testable.Reporters.JsonReporter.format(results)
const xml = Testable.Reporters.JUnitReporter.format(results)
const tracefile = Testable.Reporters.LcovReporter.format(coverageReport)
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
`SkipReason` is only present on skipped nodes that gave a reason. A run that carries a
snapshot summary also has a `Snapshots` object with its counts (`Written`, `Updated`,
`Removed`, `Matched`, and `Failed`) and an `Obsolete` list of `Key` and `Path` pairs. In
JUnit, the same summary appears as properties of a `Snapshots` testsuite without cases.
When the focus guard fails a run, both reports include a failed `Focus guard` test, so
they always agree with the exit code.

**Durations**

Result nodes carry a `duration` field in seconds. Tests and describe blocks record how
long they ran, the results object records the whole run, and skipped tests have none.

## Coverage

In Lune, set `Coverage = true` and `CoverageRoots` to report line coverage for every
module under the roots, including modules that no test required. `CoverageRoots` accepts
one script reference, a filesystem path, or a dictionary of named references or paths.
Relative coverage paths resolve against the working directory, independently of the
optional file run root. Paths are resolved locally without requiring their source...

```luau
Testable.configure({
    Coverage = true,
    CoverageRoots = script.Parent.Parent.Source,
    CoverageThreshold = 80,
})
```

The report is a table with one row per file. `CoverageRows` limits how many rows are
listed before the rest fold into a summary row, and `CoverageSort` orders them. A total
below `CoverageThreshold` fails the run.

Modules that tests load with `luau.load` instead of `require` (e.g., inside a sandbox with
a custom environment) can count too. Register each loaded chunk with its source file
path...

```luau
const chunk = luau.load(fs.readFile(path), { debugName = path, environment = sandbox })
Testable.Coverage.track(path, chunk)
const module = chunk()
```

A file can be tracked any number of times, and hits from every load are merged.

## Spec Discovery

On Lune, `Testable.Discovery` finds spec files from include globs, so a test script
doesn't have to list every spec by hand. It is only loaded on Lune and is `nil` on Roblox,
where specs are discovered from instances instead. Globs are relative to `Root`, which
defaults to the working directory. A `*` stops at a directory boundary, `**` spans any
depth, hidden files and directories are skipped, and the results are sorted. A set of
globs that matches nothing is an error. Here is everything the module offers...

- `discover(options)` → Finds the specs and requires them, returning test roots for
  `Testable.run`. Pass `Files` to narrow the run to specific spec files.
- `findSpecs(options)` → Returns the matching spec file paths without requiring them. Pass
  `Files` to narrow the selection, just as with `discover`; selected files must match the
  include and exclude globs. An explicit empty list selects nothing.
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

`findAffected`, `findChanged`, and `watch` also track shared execution dependencies.
Pass `WorkerSetup` in their options to override the current configured setup path. It
resolves relative to `Root`, using the same extension and `init.luau` directory resolution
as file execution. Changing setup or any helper it transitively requires selects every
matching spec. Missing and alternate resolution candidates are tracked too, so creating,
deleting, or replacing a setup module also updates selection and watch behavior. The
library's own actor entrypoint and its transitive string requires are always shared
dependencies, even with `Workers = 1`, because specs can start nested actor runs. Graph
construction scans source only and never requires specs or setup modules.

### File-Oriented Runs

Use `Testable.runFiles(files, root?)` to run selected spec paths on Lune without loading
specs in the caller first. It returns the same `results, passed` pair as `Testable.run`.
Paths and `WorkerSetup` resolve relative to `root`, which defaults to the working
directory. `Testable.runFilesToExitCode(files, options?, root?)` applies optional
configuration and maps the result to an [Exit Code](#exit-codes)...

```luau
Testable.configure({ Workers = 4 })
const files = Testable.Discovery.findSpecs({ Include = { "Tests/**/*.spec.luau" } })
process.exit(Testable.runFilesToExitCode(files))
```

The default `Workers = 1` loads specs locally through the existing pipeline. With more
than one worker, Testable partitions files before requiring them and executes jobs in
isolated Lune actor VMs. `MaxConcurrency` and `Parallel` control test execution within
each VM, not the worker count. Names, suite ordering, focus, and filtering are resolved
across the whole run. A file containing a `Serial` test or block runs exclusively across
all workers, including its outer lifecycle hooks. Ordinary files can still overlap even
when their VM also owns a Serial-bearing file. Actor execution requires a Lune runtime
providing `@lune/actor`. The ordinary `Testable.run` and `Testable.runToExitCode` APIs are
unchanged and do not use these worker settings.

**Shared State & Setup**

Actor VMs do not inherit parent VM state, module caches, functions, or fixtures. Set
`WorkerSetup` to a module path relative to the run's root when initialization must happen
before specs are required. The module **must return a function**, called with `Testable`
and a context table containing `Files`, `JobId`, and `Root`. The same contract applies
when `Workers = 1`, so setup always runs before spec requires...

```luau
-- Tests/Setup.luau
return function(Testable, _context)
    Testable.configure({ Timeout = 5 })
end
```

```luau
Testable.configure({ WorkerSetup = "Tests/Setup.luau", Workers = 4 })
```

Keep specs that share mutable module state, fake installations, or snapshot files in one
job with `WorkerGroups`. Both array levels must be dense, every group must contain at
least one nonblank path, and configuration deep-copies the groups and normalizes slashes
and dot segments...

```luau
Testable.configure({
    WorkerGroups = {
        { "Tests/InstallFakes.spec.luau", "Tests/SharedFixture.spec.luau" },
        { "Tests/SharedFixture.spec.luau", "Tests/UseFakes.spec.luau" },
    },
    Workers = 4,
})
```

Overlapping groups are merged transitively before selecting files. In this example,
`InstallFakes` and `UseFakes` stay together even if `SharedFixture` is not selected.
Grouping guarantees common worker ownership, not an execution order or a transfer of
parent state. Initialize required state in setup rather than depending on another spec.

**Storage & Coverage Boundaries**

A function-valued `SnapshotStore` configured in the parent is supported locally with
`Workers = 1`, but rejected with a clear configuration error when `Workers > 1` because
its functions cannot cross the actor boundary. A custom store created by setup is an
independent worker-local store, not shared parent memory. If such stores need persistence
or coordination, the store implementation must provide it explicitly.

For default filesystem snapshots in actor mode, the planning barrier requires every
snapshot path to have exactly one worker owner before storage access. Specs sharing a path
must be grouped into one worker. Undeclared nested default snapshot paths fail before
storage access instead of silently letting workers write the same file.

String `CoverageRoots` pass across the actor boundary normally. Instance-valued roots
cannot be transferred from the parent and must be created inside the worker through setup.
Coverage from workers is merged for the final report and threshold check.

### Changed-Only Runs

Only the specs affected by a branch need to run when `findChanged` narrows the list. A ref
that does not exist, or a root outside a git repository, raises an error. An empty result
means that nothing is affected, which is a clean outcome and not a failure...

```luau
const affected = Testable.Discovery.findChanged({
    Include = { "Tests/**/*.spec.luau" },
    Ref = "origin/main",
})

if #affected == 0 then
    print("No specs are affected.")
    process.exit(0)
end

process.exit(Testable.runFilesToExitCode(affected))
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

The child script receives the spec files in `process.args`, selects paths with
`findSpecs({ Files = specFiles, Include = ... })`, and passes them to `runFilesToExitCode`
without eagerly requiring them. Changes are debounced (`Debounce`, in seconds), and files
are polled every `Interval` seconds. Hidden files are ignored, except for `.luaurc` and
explicit shared execution dependencies, including packages in hidden install directories.
Every spec runs once at the start unless `RunOnStart` is `false`.

This repository's own `Scripts/RunTests.exec.luau` is a complete example. It accepts
`--changed <ref>`, `--watch`, `--workers <count>`, `--worker-setup <path>`, and a list of
spec files. Worker flags can be combined with changed-only runs or watch mode. Watch
tracks `--worker-setup` and its helpers in the parent graph, and passes the worker,
reporter, filter, and snapshot flags to each fresh child...

```sh
./Scripts/RunTests.exec.luau --workers 4 --worker-setup Tests/Setup.luau
./Scripts/RunTests.exec.luau --changed origin/main --workers 4
./Scripts/RunTests.exec.luau --watch --workers 4 --worker-setup Tests/Setup.luau
```

The worker count must be a finite positive integer. Both worker flags require a value and
can only be given once. The `--watch` and `--changed` flags remain mutually exclusive, and
`--changed` cannot be combined with explicit spec files.

## Exit Codes

Test failures and tool errors are kept apart. A failing test (or coverage below
`CoverageThreshold`) makes `Testable.run` return `passed` as `false`. A tool error means
the run can't give a meaningful verdict, and `Testable.run` throws a `ToolError` for it
instead. These are the tool errors...

- `EmptyFilter` → `Filter` did not match any test, so nothing would have run.
- `EmptyCoverage` → `Coverage` is enabled with a `CoverageThreshold` above 0, but no
  executable lines were measured. The threshold is ignored while `Coverage` is off.
- `InvalidReporters` → `Reporters` and `ReporterOutputs` describe a combination that can't
  work, such as two reports on standard output.

`Testable.runToExitCode` wraps `Testable.run` and maps the outcome to `0` for a passing
run, `1` for test failures, and `2` for a tool error (also available as
`Testable.ExitCode`). It prints tool errors and rethrows any other error. The
file-oriented `Testable.runFilesToExitCode(files, options?, root?)` uses the same exit
codes, including for worker configuration and execution failures...

```luau
const exitCode = Testable.runToExitCode(testRoots)
process.exit(exitCode)
```

To handle tool errors yourself, catch them with `pcall` and check them with
`Testable.ToolError.is`...

```luau
const ok, results, passed = pcall(Testable.run, testRoots)

if not ok and Testable.ToolError.is(results) then
    print(results.Kind, results.Message)
end
```
