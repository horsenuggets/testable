# Testable

A Luau testing framework based off of [TestEZ](https://roblox.github.io/testez/).

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

See the [TestEZ API documentation](https://roblox.github.io/testez/api-reference/) for details on writing tests.

## License

MIT
