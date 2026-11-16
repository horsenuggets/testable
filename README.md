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

Failed comparisons report `Expected` and `Received` lines. Tables are pretty-printed with
sorted keys, and deeply nested values are shortened to `{...}` in the message only. Using a
matcher on the wrong kind of value (e.g., `greaterThan` with a table) fails the test with
a message that names the matcher, even under `.never`. These names are reserved, so
`expect.extend` rejects custom matchers that reuse them.

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
