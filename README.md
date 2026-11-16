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
| `Verbose` | `boolean` | `false` | Enable detailed logging during test execution |

Reset configuration to defaults with `Testable.resetConfig()`.

## Timeouts

A test that yields forever (e.g., one waiting on a signal that never fires) would
otherwise hang the whole run. Set the `Timeout` option to give every test a time budget in
seconds. It's off by default, so tests may run for as long as they like until you set
it...

```luau
Testable.configure({ Timeout = 5 })
```

A single test can raise or lower its budget with an options table as the third argument
of `it` (or `itFOCUS` and `fit`). Use `math.huge` to turn the limit off for that test. The
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
- The `beforeAll` and `afterAll` hooks have no budget, since they often do slow one-time
  setup and belong to no single test.
- Only code that yields can be interrupted. A busy loop that never yields blocks the Luau
  scheduler, so the budget can't stop it and the run still hangs. Work that doesn't yield
  but does return still counts against the budget, so a test that finishes over budget is
  reported as timed out.
- Cancelling a test stops its own thread only. Threads that the test started with
  `task.spawn` or `task.delay` keep running.

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
