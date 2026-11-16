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
| `Indent` | `string` | `"   "` | Indentation string used for nested test output |
| `InjectGlobals` | `boolean` | `true` | Inject `describe`, `it`, `expect`, and the rest into spec functions as globals |
| `MaxConcurrency` | `number` | `4` | Maximum number of tests to run in parallel |
| `Parallel` | `boolean` | `true` | Enable or disable parallel test execution |
| `PrintSkipped` | `boolean` | `false` | Include skipped tests in the output |
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
