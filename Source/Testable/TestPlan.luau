--[[

TestPlan

Represents a tree of tests that have been loaded but not necessarily executed yet.
TestPlan objects are produced by TestPlanner.

--]]

const Config = require("./Config")
const Expectation = require("./Expectation")
const TestEnum = require("./TestEnum")
const TestScope = require("./TestScope")

--[[
    Builds the skip reason for a test marked as broken, with or without a message.
]]
const function fixmeReason(message)
    if message == nil or message == "" then
        return TestEnum.SkipReason.Fixme
    end
    return `{TestEnum.SkipReason.Fixme}, {message}`
end

--[[
    Builds the table of functions that a spec uses to declare tests under the given node.
    This table is the single source of truth for the spec API. It is injected into spec
    functions as globals, and SpecApi derives the requirable API from its keys, so an
    entry added here is available both ways.
]]
const function newEnvironment(currentNode, extraEnvironment)
    const env = {}

    if extraEnvironment then
        if type(extraEnvironment) ~= "table" then
            error(("Bad argument #2 to newEnvironment. Expected table, got %s"):format(typeof(extraEnvironment)), 2)
        end

        for key, value in pairs(extraEnvironment) do
            env[key] = value
        end
    end

    const function addChild(phrase, callback, nodeType, nodeModifier, skipReason)
        -- A node stops accepting children once its own callback has returned. Anything
        -- registered after that (e.g., from inside a running test) could never be
        -- planned properly, so it is an error instead of a registration that vanishes.
        if currentNode.collected then
            const isHook = nodeType ~= TestEnum.NodeType.Describe and nodeType ~= TestEnum.NodeType.It
            const registered = if isHook
                then `a "{string.lower(string.sub(nodeType, 1, 1))}{string.sub(nodeType, 2)}" hook`
                else `"{phrase}"`
            error(
                `Cannot register {registered} because "{currentNode:getFullName()}" has already been collected. `
                    .. "Tests, describe blocks, and hooks must be registered while the spec is being collected, "
                    .. "not from inside a running test or hook.",
                3
            )
        end

        const node = currentNode:addChild(phrase, nodeType, nodeModifier)
        node.callback = callback
        node.skipReason = skipReason
        if nodeType == TestEnum.NodeType.Describe then
            node:expand()
        end
        return node
    end

    --[[
        Validates an optional skip reason passed to one of the skip variants and returns
        it unchanged.
    ]]
    const function checkReason(name, reason)
        if reason ~= nil and type(reason) ~= "string" then
            error(`The reason passed to "{name}" must be a string, got {typeof(reason)}.`, 3)
        end
        return reason
    end

    function env.describeFOCUS(phrase, callback)
        addChild(phrase, callback, TestEnum.NodeType.Describe, TestEnum.NodeModifier.Focus)
    end

    --[[
        Skips every test under the describe block. The optional reason is reported for
        each of those tests unless a test carries a reason of its own.
    ]]
    function env.describeSKIP(phrase, callback, reason)
        addChild(
            phrase,
            callback,
            TestEnum.NodeType.Describe,
            TestEnum.NodeModifier.Skip,
            checkReason("describeSKIP", reason)
        )
    end

    function env.describe(phrase, callback, nodeModifier)
        addChild(phrase, callback, TestEnum.NodeType.Describe, TestEnum.NodeModifier.None)
    end

    function env.itFOCUS(phrase, callback)
        addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.Focus)
    end

    function env.itSKIP(phrase, callback, reason)
        addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.Skip, checkReason("itSKIP", reason))
    end

    --[[
        Skips a test that is known to be broken. It is reported with the reason "fixme",
        followed by the optional message.
    ]]
    function env.itFIXME(phrase, callback, message)
        const reason = fixmeReason(checkReason("itFIXME", message))
        addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.Skip, reason)
    end

    --[[
        Records a test that still needs to be written. It takes a name only and is
        reported as skipped with the reason "todo".
    ]]
    function env.itTODO(phrase, ...)
        if select("#", ...) > 0 then
            error(`"itTODO" only takes a name, so use "it" for "{phrase}" once it has a body.`, 2)
        end
        addChild(phrase, nil, TestEnum.NodeType.It, TestEnum.NodeModifier.Skip, TestEnum.SkipReason.Todo)
    end

    function env.it(phrase, callback, nodeModifier)
        addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.None)
    end

    -- Incrementing counter used to ensure that beforeAll, afterAll, beforeEach, afterEach have unique phrases
    local lifecyclePhaseId = 0

    const lifecycleHooks = {
        [TestEnum.NodeType.BeforeAll] = "beforeAll",
        [TestEnum.NodeType.AfterAll] = "afterAll",
        [TestEnum.NodeType.BeforeEach] = "beforeEach",
        [TestEnum.NodeType.AfterEach] = "afterEach",
    }

    for nodeType, name in pairs(lifecycleHooks) do
        env[name] = function(callback)
            addChild(name .. "_" .. tostring(lifecyclePhaseId), callback, nodeType, TestEnum.NodeModifier.None)
            lifecyclePhaseId = lifecyclePhaseId + 1
        end
    end

    function env.FIXME(optionalMessage)
        currentNode.skipReason = fixmeReason(checkReason("FIXME", optionalMessage))
        currentNode.modifier = TestEnum.NodeModifier.Skip
    end

    function env.FOCUS()
        currentNode.modifier = TestEnum.NodeModifier.Focus
    end

    function env.SKIP(reason)
        currentNode.skipReason = checkReason("SKIP", reason)
        currentNode.modifier = TestEnum.NodeModifier.Skip
    end

    --[[
        This function is deprecated. Calling it is a no-op beyond generating a
        warning.
    ]]
    function env.HACK_NO_XPCALL()
        warn(
            "HACK_NO_XPCALL is deprecated. It is now safe to yield in an "
                .. "xpcall, so this is no longer necessary. It can be safely deleted."
        )
    end

    env.fit = env.itFOCUS
    env.xit = env.itSKIP
    env.fdescribe = env.describeFOCUS
    env.xdescribe = env.describeSKIP

    env.expect = setmetatable({
        extend = function(...)
            error('Cannot call "expect.extend" from within a "describe" node.')
        end,
    }, {
        __call = function(_self, ...)
            return Expectation.new(...)
        end,
    })

    return env
end

const TestNode = {}
TestNode.__index = TestNode

--[[
    Create a new test node. A pointer to the test plan, a phrase to describe it
    and the type of node it is are required. The modifier is optional and will
    be None if left blank.
]]
function TestNode.new(plan, phrase, nodeType, nodeModifier)
    nodeModifier = nodeModifier or TestEnum.NodeModifier.None

    const node = {
        plan = plan,
        phrase = phrase,
        type = nodeType,
        modifier = nodeModifier,
        children = {},
        callback = nil,
        parent = nil,
        skipReason = nil,
    }

    node.environment = newEnvironment(node, plan.extraEnvironment)
    return setmetatable(node, TestNode)
end

const function getModifier(name, pattern, modifier)
    if pattern and (modifier == nil or modifier == TestEnum.NodeModifier.None) then
        if name:match(pattern) then
            return TestEnum.NodeModifier.Focus
        else
            return TestEnum.NodeModifier.Skip
        end
    end
    return modifier
end

function TestNode:addChild(phrase, nodeType, nodeModifier)
    if nodeType == TestEnum.NodeType.It then
        for _, child in pairs(self.children) do
            if child.phrase == phrase then
                error("Duplicate it block found: " .. child:getFullName())
            end
        end
    end

    const childName = self:getFullName() .. " " .. phrase
    nodeModifier = getModifier(childName, self.plan.testNamePattern, nodeModifier)
    const child = TestNode.new(self.plan, phrase, nodeType, nodeModifier)
    child.parent = self
    table.insert(self.children, child)
    return child
end

--[[
    Join the names of all the nodes back to the parent.
]]
function TestNode:getFullName()
    if self.parent then
        const parentPhrase = self.parent:getFullName()
        if parentPhrase then
            return parentPhrase .. " " .. self.phrase
        end
    end
    return self.phrase
end

--[[
    Expand a node by setting its callback environment and then calling it. Any
    further it and describe calls within the callback will be added to the tree.
]]
function TestNode:expand()
    if Config.InjectGlobals then
        const originalEnv = getfenv(self.callback)
        const callbackEnv = setmetatable({}, { __index = originalEnv })
        for key, value in pairs(self.environment) do
            callbackEnv[key] = value
        end
        -- Copy 'script' directly to new env to make Studio debugger happy.
        -- Studio debugger does not look into __index, because of security reasons
        callbackEnv.script = originalEnv.script
        setfenv(self.callback, callbackEnv)
    end

    -- Collection is synchronous, so the node stays on top of this coroutine's scope stack
    -- for exactly as long as its callback runs. That is how the requirable spec API finds
    -- the node to register under.
    self.collected = false
    TestScope.enterCollection(self)

    const success, result = xpcall(self.callback, function(message)
        return debug.traceback(tostring(message), 2)
    end)

    TestScope.exit()
    self.collected = true

    if not success then
        self.loadError = result
    end
end

const TestPlan = {}
TestPlan.__index = TestPlan

TestPlan.newEnvironment = newEnvironment

--[[
    Create a new, empty TestPlan.
]]
function TestPlan.new(testNamePattern, extraEnvironment)
    const plan = {
        children = {},
        testNamePattern = testNamePattern,
        extraEnvironment = extraEnvironment,
        -- Snapshot the focus guard before any spec code runs, since a describe block or
        -- a test may call Config.reset() which would turn it back off.
        forbidFocus = Config.ForbidFocus,
    }

    return setmetatable(plan, TestPlan)
end

--[[
    Add a new child under the test plan's root node.
]]
function TestPlan:addChild(phrase, nodeType, nodeModifier)
    nodeModifier = getModifier(phrase, self.testNamePattern, nodeModifier)
    const child = TestNode.new(self, phrase, nodeType, nodeModifier)
    table.insert(self.children, child)
    return child
end

--[[
    Add a new describe node with the given method as a callback. Generates or
    reuses all the describe nodes along the path. Returns the node that owns the method.
]]
function TestPlan:addRoot(path, method)
    local curNode = self
    for i = #path, 1, -1 do
        local nextNode = nil

        for _, child in ipairs(curNode.children) do
            if child.phrase == path[i] then
                nextNode = child
                break
            end
        end

        if nextNode == nil then
            nextNode = curNode:addChild(path[i], TestEnum.NodeType.Describe)
        end

        curNode = nextNode
    end

    curNode.callback = method
    curNode:expand()

    return curNode
end

--[[
    Calls the given callback on all nodes in the tree, traversed depth-first.
]]
function TestPlan:visitAllNodes(callback, root, level)
    root = root or self
    level = level or 0

    for _, child in ipairs(root.children) do
        callback(child, level)

        self:visitAllNodes(callback, child, level + 1)
    end
end

--[[
    Visualizes the test plan in a simple format, suitable for debugging the test
    plan's structure.
]]
function TestPlan:visualize()
    const buffer = {}
    self:visitAllNodes(function(node, level)
        table.insert(buffer, (" "):rep(3 * level) .. node.phrase)
    end)
    return table.concat(buffer, "\n")
end

--[[
    Gets a list of all nodes in the tree for which the given callback returns
    true.
]]
function TestPlan:findNodes(callback)
    const results = {}
    self:visitAllNodes(function(node)
        if callback(node) then
            table.insert(results, node)
        end
    end)
    return results
end

return TestPlan
