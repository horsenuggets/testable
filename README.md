# Testable

A Luau testing framework based off of [TestEZ](https://roblox.github.io/testez/). Testable extends TestEZ with parallel test execution and support for [Lune](https://lune-org.github.io/docs), allowing you to run tests outside of the Roblox environment.

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

## Usage

```luau
local Testable = require("@devpackages/testable")
local testRoot = script.Parent.Tests

local results, passed = Testable.run({ testRoot })

if not passed then
    error("Tests failed!")
end
```

See the [TestEZ documentation](https://roblox.github.io/testez/api-reference/) for details on writing tests.
