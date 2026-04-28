#!/usr/bin/env -S lune run

--[[

DemoOutput

Renders mock test and coverage output to preview the visual style of the TextReporter
and CoverageReporter without running real tests. Each scenario shows a different
combination of results.

Usage:
    lune run Scripts/DemoOutput          -- show all scenarios
    lune run Scripts/DemoOutput 1        -- show scenario 1 only
    lune run Scripts/DemoOutput 3        -- show scenario 3 only

--]]

local process = require("@lune/process")

local Ansi = require("../Source/Testable/Ansi")
local Config = require("../Source/Testable/Config")
local CoverageReporter = require("../Source/Testable/Reporters/CoverageReporter")
local TestEnum = require("../Source/Testable/TestEnum")
local TextReporter = require("../Source/Testable/Reporters/TextReporter")

local Success = TestEnum.TestStatus.Success
local Failure = TestEnum.TestStatus.Failure
local Skipped = TestEnum.TestStatus.Skipped

local function makeNode(phrase: string, status: string?, children: { any }?): any
    return {
        planNode = { phrase = phrase },
        status = status,
        children = children or {},
        errors = {},
    }
end

local function makeResults(suites: { any }, counts: { success: number, failure: number, skipped: number }): any
    return {
        planNode = { phrase = "Root" },
        children = suites,
        errors = {},
        successCount = counts.success,
        failureCount = counts.failure,
        skippedCount = counts.skipped,
    }
end

local function makeFile(path: string, executable: number, hit: number): any
    local pct = if executable > 0 then math.floor((hit / executable) * 1000) / 10 else 0
    local name = path:match("([^/]+)$") or path
    return {
        Name = name,
        Path = path,
        Functions = {},
        ExecutableLines = executable,
        HitLines = hit,
        Percentage = pct,
    }
end

local function makeCoverageReport(files: { any }): any
    local totalExecutable = 0
    local totalHit = 0
    for _, file in files do
        totalExecutable += file.ExecutableLines
        totalHit += file.HitLines
    end
    local totalPct = if totalExecutable > 0 then math.floor((totalHit / totalExecutable) * 1000) / 10 else 0
    return {
        Files = files,
        TotalExecutableLines = totalExecutable,
        TotalHitLines = totalHit,
        TotalPercentage = totalPct,
    }
end

type Scenario = {
    name: string,
    printSkipped: boolean,
    results: any,
    coverage: any?,
    coverageThreshold: number?,
}

local SCENARIOS: { Scenario } = {
    {
        name = "All tests passing",
        printSkipped = false,
        results = makeResults({
            makeNode("AuthService", nil, {
                makeNode("login()", nil, {
                    makeNode("should authenticate valid credentials", Success),
                    makeNode("should reject invalid password", Success),
                    makeNode("should rate limit after 5 attempts", Success),
                }),
                makeNode("logout()", nil, {
                    makeNode("should clear session token", Success),
                    makeNode("should redirect to login page", Success),
                }),
            }),
            makeNode("UserProfile", nil, {
                makeNode("getDisplayName()", nil, {
                    makeNode("should return full name when set", Success),
                    makeNode("should fall back to username", Success),
                }),
            }),
        }, { success = 7, failure = 0, skipped = 0 }),
    },
    {
        name = "Mixed results with failures",
        printSkipped = false,
        results = makeResults({
            makeNode("DatabaseConnection", nil, {
                makeNode("connect()", nil, {
                    makeNode("should establish connection", Success),
                    makeNode("should retry on timeout", Failure),
                    makeNode("should use connection pool", Success),
                }),
                makeNode("query()", nil, {
                    makeNode("should execute SELECT statements", Success),
                    makeNode("should parameterize inputs", Failure),
                    makeNode("should return typed results", Success),
                }),
            }),
            makeNode("CacheLayer", nil, {
                makeNode("get()", nil, {
                    makeNode("should return cached value", Success),
                    makeNode("should miss on expired entries", Success),
                }),
                makeNode("invalidate()", nil, {
                    makeNode("should remove entry from cache", Success),
                }),
            }),
        }, { success = 7, failure = 2, skipped = 0 }),
    },
    {
        name = "With skipped tests",
        printSkipped = true,
        results = makeResults({
            makeNode("PaymentProcessor", nil, {
                makeNode("charge()", nil, {
                    makeNode("should process valid payment", Success),
                    makeNode("should handle declined card", Success),
                    makeNode("should support international currencies", Skipped),
                }),
                makeNode("refund()", nil, {
                    makeNode("should issue full refund", Success),
                    makeNode("should issue partial refund", Skipped),
                }),
            }),
        }, { success = 3, failure = 0, skipped = 2 }),
    },
    {
        name = "Single suite, all failing",
        printSkipped = false,
        results = makeResults({
            makeNode("MigrationRunner", nil, {
                makeNode("up()", nil, {
                    makeNode("should apply pending migrations", Failure),
                    makeNode("should skip already-applied migrations", Failure),
                    makeNode("should run in transaction", Failure),
                }),
            }),
        }, { success = 0, failure = 3, skipped = 0 }),
    },
    {
        name = "Large suite with deep nesting",
        printSkipped = true,
        results = makeResults({
            makeNode("API", nil, {
                makeNode("v1", nil, {
                    makeNode("/users", nil, {
                        makeNode("GET", nil, {
                            makeNode("should list all users", Success),
                            makeNode("should paginate results", Success),
                            makeNode("should filter by role", Failure),
                        }),
                        makeNode("POST", nil, {
                            makeNode("should create a new user", Success),
                            makeNode("should validate email format", Success),
                            makeNode("should reject duplicate username", Success),
                        }),
                    }),
                    makeNode("/posts", nil, {
                        makeNode("GET", nil, {
                            makeNode("should return published posts", Success),
                            makeNode("should include author data", Success),
                        }),
                        makeNode("DELETE", nil, {
                            makeNode("should require admin role", Success),
                            makeNode("should soft delete by default", Skipped),
                        }),
                    }),
                }),
                makeNode("v2", nil, {
                    makeNode("/users", nil, {
                        makeNode("should use new response format", Success),
                        makeNode("should deprecate old fields", Skipped),
                    }),
                }),
            }),
        }, { success = 9, failure = 1, skipped = 2 }),
    },
    {
        name = "High coverage, all passing",
        printSkipped = false,
        results = makeResults({
            makeNode("CoreLibrary", nil, {
                makeNode("should initialize", Success),
                makeNode("should process events", Success),
                makeNode("should serialize state", Success),
            }),
        }, { success = 3, failure = 0, skipped = 0 }),
        coverage = makeCoverageReport({
            makeFile("Source/CoreLib/EventBus", 85, 82),
            makeFile("Source/CoreLib/Serializer", 62, 59),
            makeFile("Source/CoreLib/StateManager", 120, 114),
            makeFile("Source/CoreLib/Validator", 45, 43),
        }),
        coverageThreshold = 80,
    },
    {
        name = "Mixed coverage with warnings and failures",
        printSkipped = false,
        results = makeResults({
            makeNode("DataPipeline", nil, {
                makeNode("should ingest records", Success),
                makeNode("should transform data", Success),
                makeNode("should handle malformed input", Failure),
            }),
        }, { success = 2, failure = 1, skipped = 0 }),
        coverage = makeCoverageReport({
            makeFile("Source/Pipeline/Ingester", 150, 142),
            makeFile("Source/Pipeline/Transformer", 200, 130),
            makeFile("Source/Pipeline/OutputWriter", 90, 88),
            makeFile("Source/Pipeline/Validators/SchemaValidator", 75, 30),
            makeFile("Source/Pipeline/RetryPolicy", 40, 38),
            makeFile("Source/Pipeline/RateLimiter", 55, 52),
            makeFile("Source/Pipeline/Metrics/MetricsCollector", 110, 60),
        }),
        coverageThreshold = 90,
    },
    {
        name = "Low coverage, below threshold",
        printSkipped = false,
        results = makeResults({
            makeNode("LegacyModule", nil, {
                makeNode("should still work", Success),
            }),
        }, { success = 1, failure = 0, skipped = 0 }),
        coverage = makeCoverageReport({
            makeFile("Source/Legacy/LegacyParser", 300, 45),
            makeFile("Source/Legacy/LegacyFormatter", 180, 20),
            makeFile("Source/Legacy/LegacyBridge", 95, 10),
        }),
        coverageThreshold = 80,
    },
    {
        name = "Long file paths with truncation",
        printSkipped = false,
        results = makeResults({
            makeNode("DeepModule", nil, {
                makeNode("should handle nested paths", Success),
            }),
        }, { success = 1, failure = 0, skipped = 0 }),
        coverage = makeCoverageReport({
            makeFile("Source/Services/Authentication/Providers/OAuth2Handler", 80, 75),
            makeFile("Source/Services/Authentication/Providers/Credentials/PasswordValidator", 60, 58),
            makeFile("Source/Services/DataPipeline/Transformers/JsonNormalizer", 45, 40),
            makeFile("Source/UI/Components/Dashboard/Widgets/ActivityFeed/ActivityFeedController", 120, 95),
            makeFile("Source/GenerateAuthenticationTokenFromCredentialProviderFactory", 30, 28),
        }),
        coverageThreshold = 80,
    },
}

local BOX_WIDTH = 64

local function printScenario(index: number, scenario: Scenario)
    local IS_LUNE = Ansi.isLune()
    local label = `[Scenario {index}]`
    local title = `{label} {scenario.name}`
    local innerWidth = BOX_WIDTH - 2

    -- Truncate if too long
    if #title > innerWidth then
        title = title:sub(1, innerWidth)
        label = title:match("^(%[Scenario %d+%])") or label
    end

    -- Left align with padding
    local pad = innerWidth - #title - 2
    if pad < 0 then
        pad = 0
    end
    local paddedTitle = " " .. title .. string.rep(" ", pad) .. " "

    local coloredPadded
    if IS_LUNE then
        local afterLabel = paddedTitle:sub(#label + 2)
        coloredPadded = " " .. label .. Ansi.dim(afterLabel)
    end

    if IS_LUNE then
        print(Ansi.dim("┌" .. string.rep("─", innerWidth) .. "┐"))
        print(Ansi.dim("│") .. coloredPadded .. Ansi.dim("│"))
        print(Ansi.dim("└" .. string.rep("─", innerWidth) .. "┘"))
    else
        print("+" .. string.rep("-", innerWidth) .. "+")
        print("|" .. paddedTitle .. "|")
        print("+" .. string.rep("-", innerWidth) .. "+")
    end

    Config.set({ PrintSkipped = scenario.printSkipped })
    TextReporter.report(scenario.results)

    if scenario.coverage then
        CoverageReporter.report(scenario.coverage, scenario.coverageThreshold or 0)
    else
        TextReporter.separator()
    end

    Config.reset()
end

local function main()
    local selectedArg = process.args[1]

    if selectedArg then
        local index = tonumber(selectedArg)
        if not index or index < 1 or index > #SCENARIOS then
            print(`Invalid scenario number. Choose 1-{#SCENARIOS}.`)
            process.exit(1)
            return
        end
        printScenario(index, SCENARIOS[index])
    else
        for i, scenario in SCENARIOS do
            printScenario(i, scenario)
        end
    end
end

main()
