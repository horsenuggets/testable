# Testable

A Luau testing framework with a TestEZ-style API. Provides describe/it blocks, expectation matchers, lifecycle hooks, and parallel test execution support.

## Installation

Add Testable to your `wally.toml`:

```toml
[dev-dependencies]
testable = "cxmeel/testable@0.0.4"
```

Then run:

```bash
wally install
```

## Quick Start

Create a test file (e.g., `MyModule.spec.luau`):

```luau
local MyModule = require("./MyModule")

it("should add two numbers", function()
    expect(MyModule.add(2, 3)).to.equal(5)
end)

it("should return nil for invalid input", function()
    expect(MyModule.add("a", "b")).never.to.be.ok()
end)
```

Run tests using the Testable API:

```luau
local Testable = require("@packages/testable")
local testRoot = script.Parent.Tests

local results, passed = Testable.run({ testRoot })

if not passed then
    error("Tests failed!")
end
```

## Writing Tests

### Describe and It Blocks

Use `describe` to group related tests and `it` to define individual test cases:

```luau
describe("Calculator", function()
    describe("add", function()
        it("should add positive numbers", function()
            expect(Calculator.add(1, 2)).to.equal(3)
        end)

        it("should add negative numbers", function()
            expect(Calculator.add(-1, -2)).to.equal(-3)
        end)
    end)

    describe("subtract", function()
        it("should subtract numbers", function()
            expect(Calculator.subtract(5, 3)).to.equal(2)
        end)
    end)
end)
```

For simple test files, you can omit the top-level describe block since the file name is already used as the test name:

```luau
-- CalculatorTest.spec.luau
it("should add numbers", function()
    expect(Calculator.add(1, 2)).to.equal(3)
end)

it("should subtract numbers", function()
    expect(Calculator.subtract(5, 3)).to.equal(2)
end)
```

### Expectations

The `expect` function creates assertions with a fluent API:

```luau
expect(value).to.equal(expected)
expect(value).to.be.ok()
expect(value).to.be.a("string")
expect(value).to.be.near(expected, tolerance)
expect(fn).to.throw()
expect(fn).to.throw("error message")
```

#### Available Matchers

| Matcher | Description |
|---------|-------------|
| `equal(value)` | Checks strict equality (`==`) |
| `ok()` | Checks that value is not nil |
| `a(type)` / `an(type)` | Checks the value's type |
| `near(value, limit?)` | Checks numeric equality within a tolerance (default: 1e-7) |
| `throw(message?)` | Checks that a function throws an error |

#### Chaining Keywords

These keywords improve readability but don't affect behavior:

- `to`
- `be`
- `been`
- `have`
- `was`
- `at`

```luau
expect(5).to.be.a("number")
expect(result).to.have.been.ok()
```

#### Negation

Use `.never` to negate an expectation:

```luau
expect(5).never.to.equal(6)
expect(nil).never.to.be.ok()
expect(value).never.to.be.a("function")
```

#### Chained Assertions

Matchers return the expectation, allowing chains:

```luau
expect(5)
    .to.be.a("number")
    .to.be.ok()
    .never.to.equal(0)
```

### Custom Matchers

Extend expectations with custom matchers using `expect.extend`:

```luau
expect.extend({
    toBePositive = function(value)
        return {
            pass = type(value) == "number" and value > 0,
            message = string.format("Expected %s to be a positive number", tostring(value)),
        }
    end,

    toContain = function(value, substring)
        return {
            pass = type(value) == "string" and string.find(value, substring, 1, true) ~= nil,
            message = string.format("Expected %q to contain %q", tostring(value), tostring(substring)),
        }
    end,
})

it("should use custom matchers", function()
    expect(42).toBePositive()
    expect("hello world").toContain("world")
end)
```

### Lifecycle Hooks

Control test setup and teardown with lifecycle hooks:

```luau
describe("Database", function()
    local db

    beforeAll(function()
        -- Runs once before all tests in this describe block
        db = Database.connect()
    end)

    afterAll(function()
        -- Runs once after all tests in this describe block
        db:disconnect()
    end)

    beforeEach(function()
        -- Runs before each test
        db:beginTransaction()
    end)

    afterEach(function()
        -- Runs after each test
        db:rollback()
    end)

    it("should insert a record", function()
        db:insert({ name = "test" })
        expect(db:count()).to.equal(1)
    end)

    it("should delete a record", function()
        db:insert({ name = "test" })
        db:delete({ name = "test" })
        expect(db:count()).to.equal(0)
    end)
end)
```

### Context

Share data between lifecycle hooks and tests using context:

```luau
describe("User", function()
    beforeEach(function(context)
        context.user = User.create({ name = "Test" })
    end)

    afterEach(function(context)
        context.user:destroy()
    end)

    it("should have a name", function(context)
        expect(context.user.name).to.equal("Test")
    end)
end)
```

Context is write-once per key to prevent accidental overwrites.

### Focus and Skip

Focus on specific tests using `fdescribe` and `fit`, or skip tests using `xdescribe` and `xit`:

```luau
fdescribe("Focused suite", function()
    fit("only this test runs", function()
        expect(true).to.be.ok()
    end)

    it("this test is skipped", function()
        expect(true).to.be.ok()
    end)
end)

xdescribe("Skipped suite", function()
    it("this entire suite is skipped", function()
        expect(true).to.be.ok()
    end)
end)
```

When any focused tests exist, only those tests run.

### Failing Tests Explicitly

Use `fail()` to explicitly fail a test:

```luau
it("should not reach this point", function()
    if someCondition then
        fail("Unexpected condition occurred")
    end
end)
```

## Parallel Execution

Testable runs tests in parallel by default using `task.spawn`. This significantly speeds up test execution for large test suites.

Configure parallel execution:

```luau
local TestRunner = require("@packages/testable").TestRunner

-- Disable parallel execution
TestRunner.parallelEnabled = false

-- Adjust max concurrent tests (default: 4)
TestRunner.maxConcurrency = 8

-- Enable verbose logging
TestRunner.verbose = true
```

## API Reference

### Testable

| Function | Description |
|----------|-------------|
| `Testable.run(testRoots)` | Runs all tests from the given roots and returns `(results, passed)` |

### Test Functions

| Function | Description |
|----------|-------------|
| `describe(name, fn)` | Creates a test suite |
| `fdescribe(name, fn)` | Creates a focused test suite |
| `xdescribe(name, fn)` | Creates a skipped test suite |
| `it(name, fn)` | Creates a test case |
| `fit(name, fn)` | Creates a focused test case |
| `xit(name, fn)` | Creates a skipped test case |
| `beforeAll(fn)` | Runs once before all tests in the suite |
| `afterAll(fn)` | Runs once after all tests in the suite |
| `beforeEach(fn)` | Runs before each test in the suite |
| `afterEach(fn)` | Runs after each test in the suite |
| `expect(value)` | Creates an expectation for assertions |
| `fail(message?)` | Explicitly fails the current test |

### TestRunner Configuration

| Property | Default | Description |
|----------|---------|-------------|
| `parallelEnabled` | `true` | Enable/disable parallel test execution |
| `maxConcurrency` | `4` | Maximum concurrent tests when parallel is enabled |
| `verbose` | `false` | Enable detailed logging output |

## Project Structure

```
testable/
├── Source/
│   └── Testable/
│       ├── init.luau           # Main module entry point
│       ├── Context.luau        # Test context management
│       ├── Expectation.luau    # Expectation matchers
│       ├── ExpectationContext.luau
│       ├── LifecycleHooks.luau # beforeEach, afterEach, etc.
│       ├── TestBootstrap.luau  # Module loading
│       ├── TestEnum.luau       # Node types and modifiers
│       ├── TestPlan.luau       # Test plan structure
│       ├── TestPlanner.luau    # Test plan creation
│       ├── TestResults.luau    # Result aggregation
│       ├── TestRunner.luau     # Test execution engine
│       ├── TestSession.luau    # Session state management
│       └── Reporters/
│           └── TextReporter.luau
└── Tests/
    └── *.spec.luau            # Test files
```

## License

MIT
