# Testable

A Luau testing framework based off of TestEZ.

## Installation

Add Testable to your `wally.toml`:

```toml
[dev-dependencies]
testable = "horsenuggets/testable@0.0.4"
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

```luau
describe("Calculator", function()
    it("should add numbers", function()
        expect(Calculator.add(1, 2)).to.equal(3)
    end)

    it("should subtract numbers", function()
        expect(Calculator.subtract(5, 3)).to.equal(2)
    end)
end)
```

### Expectations

```luau
expect(value).to.equal(expected)
expect(value).to.be.ok()
expect(value).to.be.a("string")
expect(value).to.be.near(expected, tolerance)
expect(fn).to.throw()
expect(fn).to.throw("error message")
```

Use `.never` to negate:

```luau
expect(5).never.to.equal(6)
expect(nil).never.to.be.ok()
```

### Lifecycle Hooks

```luau
describe("Database", function()
    beforeAll(function()
        -- Runs once before all tests
    end)

    afterAll(function()
        -- Runs once after all tests
    end)

    beforeEach(function()
        -- Runs before each test
    end)

    afterEach(function()
        -- Runs after each test
    end)
end)
```

### Focus and Skip

```luau
fdescribe("focused suite", function() end)
fit("focused test", function() end)
xdescribe("skipped suite", function() end)
xit("skipped test", function() end)
```

## License

MIT
