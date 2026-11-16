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
