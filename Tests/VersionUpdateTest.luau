local fs = require("@lune/fs")
local process = require("@lune/process")

-- Atomic counter for unique test IDs (works with parallel execution)
local testCounter = 0

-- Shared template directory - created once, copied for each test
local templateDir: string? = nil
local templateLock = { locked = false }

local function getTempDirectory(): string
    -- Check for Windows temp directory first, then Unix
    local tempDir = process.env.TEMP or process.env.TMP or process.env.TMPDIR or "/tmp"
    return tempDir
end

local function createTempDir(): string
    testCounter += 1
    local timestamp = os.time()
    local baseTempDir = getTempDirectory()
    local random = math.random(100000, 999999)
    -- Use counter + clock + random to ensure uniqueness even in parallel
    local tempPath = `{baseTempDir}/version-test-{timestamp}-{testCounter}-{random}`

    -- Keep trying with different random values if directory already exists
    while fs.isDir(tempPath) do
        random = math.random(100000, 999999)
        tempPath = `{baseTempDir}/version-test-{timestamp}-{testCounter}-{random}`
    end

    fs.writeDir(tempPath)
    return tempPath
end

local function cleanupTempDir(path: string)
    if fs.isDir(path) then
        fs.removeDir(path)
    end
end

local function copyDir(src: string, dest: string)
    fs.writeDir(dest)
    for _, entry in ipairs(fs.readDir(src)) do
        local srcPath = `{src}/{entry}`
        local destPath = `{dest}/{entry}`
        if fs.isDir(srcPath) then
            copyDir(srcPath, destPath)
        else
            fs.writeFile(destPath, fs.readFile(srcPath))
        end
    end
end

local function initGitRepo(repoPath: string)
    local result = process.exec("git", { "init" }, { cwd = repoPath })
    if not result.ok then
        error(`Failed to init git repo at {repoPath}: {result.stderr}`)
    end
    process.exec("git", { "config", "user.email", "test@test.com" }, { cwd = repoPath })
    process.exec("git", { "config", "user.name", "Test User" }, { cwd = repoPath })
end

local function setupRokitTemplate(): string
    local baseTempDir = getTempDirectory()
    local templatePath = `{baseTempDir}/version-test-template-{os.time()}`
    fs.writeDir(templatePath)

    local rokitToml = [[
        [tools]
        lune = "horsenuggets/lune@0.10.5"
    ]]
    -- Strip leading whitespace from each line for proper TOML format
    rokitToml = string.gsub(rokitToml, "\n%s+", "\n")
    rokitToml = string.gsub(rokitToml, "^%s+", "")
    fs.writeFile(`{templatePath}/rokit.toml`, rokitToml)

    -- Retry rokit install a few times in case of transient failures
    local maxRetries = 3
    for i = 1, maxRetries do
        local result = process.exec("rokit", { "install", "--no-trust-check" }, { cwd = templatePath })
        if result.ok then
            return templatePath
        end
        if i < maxRetries then
            -- Delay with jitter before retry
            local delay = 0.1 * i + math.random() * 0.1
            local start = os.clock()
            while os.clock() - start < delay do
            end
        end
    end
    return templatePath
end

local function getOrCreateTemplate(): string
    -- Simple spinlock to ensure only one thread creates the template
    while templateLock.locked do
        local task = require("@lune/task")
        task.wait()
    end

    if templateDir and fs.isDir(templateDir) then
        return templateDir
    end

    templateLock.locked = true
    -- Double-check after acquiring lock
    if templateDir and fs.isDir(templateDir) then
        templateLock.locked = false
        return templateDir
    end

    templateDir = setupRokitTemplate()
    templateLock.locked = false
    return templateDir
end

local function setupRokit(repoPath: string)
    -- Copy from template instead of running rokit install
    local template = getOrCreateTemplate()
    fs.writeFile(`{repoPath}/rokit.toml`, fs.readFile(`{template}/rokit.toml`))
    -- Copy the .rokit directory with installed tools
    if fs.isDir(`{template}/.rokit`) then
        copyDir(`{template}/.rokit`, `{repoPath}/.rokit`)
    end
end

local function commitVersion(repoPath: string, version: string, message: string?)
    fs.writeFile(`{repoPath}/VERSION`, version)
    process.exec("git", { "add", "VERSION" }, { cwd = repoPath })
    process.exec("git", { "commit", "-m", message or `Set version to {version}` }, { cwd = repoPath })
end

local function setWorkingVersion(repoPath: string, version: string)
    fs.writeFile(`{repoPath}/VERSION`, version)
end

local function runVersionCheck(repoPath: string): (boolean, string)
    local result = process.exec("lune", { "run", "Scripts/EnsureProperVersionUpdate" }, {
        cwd = repoPath,
        stdio = {
            stdout = "default",
            stderr = "default",
        },
    })
    local stdout = result.stdout or ""
    local stderr = result.stderr or ""
    return result.ok, stdout .. stderr
end

local function copyScriptsToRepo(repoPath: string)
    fs.writeDir(`{repoPath}/Scripts`)
    fs.writeDir(`{repoPath}/Scripts/Helpers`)
    local scriptContent = fs.readFile("Scripts/EnsureProperVersionUpdate.luau")
    fs.writeFile(`{repoPath}/Scripts/EnsureProperVersionUpdate.luau`, scriptContent)
    local helperContent = fs.readFile("Scripts/Helpers/parseVersion.luau")
    fs.writeFile(`{repoPath}/Scripts/Helpers/parseVersion.luau`, helperContent)
end

local function setupTestRepo(): string
    local tempDir = createTempDir()
    initGitRepo(tempDir)
    setupRokit(tempDir)
    copyScriptsToRepo(tempDir)
    return tempDir
end

return function()
    describe("Version format validation", function()
        it("should reject VERSION file that does not exist", function()
            local tempDir = setupTestRepo()
            -- Don't create VERSION file
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "VERSION file does not exist")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject invalid version format (missing patch)", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "1.2")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "MAJOR.MINOR.PATCH")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject invalid version format (extra component)", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "1.2.3.4")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "MAJOR.MINOR.PATCH")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject invalid version format (non-numeric)", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "1.2.beta")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "MAJOR.MINOR.PATCH")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should accept valid version format with no git history", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "1.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Version format is valid")).to.be.ok()
            cleanupTempDir(tempDir)
        end)
    end)

    describe("Valid version bumps", function()
        it("should accept valid patch bump (1.0.0 -> 1.0.1)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "1.0.1")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Valid patch version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should accept valid minor bump (1.0.5 -> 1.1.0)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.5")
            setWorkingVersion(tempDir, "1.1.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Valid minor version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should accept valid major bump (1.5.3 -> 2.0.0)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.5.3")
            setWorkingVersion(tempDir, "2.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Valid major version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should accept patch bump from 0.0.0 -> 0.0.1", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "0.0.0")
            setWorkingVersion(tempDir, "0.0.1")
            local success, output = runVersionCheck(tempDir)
            if not success then
                error(`Expected success but got failure. Output: "{output}"`)
            end
            expect(string.find(output, "Valid patch version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)
    end)

    describe("Invalid version bumps", function()
        it("should reject unchanged version", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "1.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Version has not been updated")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject skipping patch versions (1.0.0 -> 1.0.2)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "1.0.2")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject skipping minor versions (1.0.0 -> 1.2.0)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "1.2.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject skipping major versions (1.0.0 -> 3.0.0)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "3.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject changing multiple components (1.0.0 -> 1.1.1)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "1.1.1")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject minor bump without resetting patch (1.0.5 -> 1.1.5)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.5")
            setWorkingVersion(tempDir, "1.1.5")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject major bump without resetting minor/patch (1.5.3 -> 2.5.3)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.5.3")
            setWorkingVersion(tempDir, "2.5.3")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject version decrement (1.0.1 -> 1.0.0)", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.1")
            setWorkingVersion(tempDir, "1.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "Invalid version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)
    end)

    describe("Edge cases", function()
        it("should handle version with leading/trailing whitespace", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "1.0.0")
            setWorkingVersion(tempDir, "  1.0.1  \n")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Valid patch version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should handle previous version with malformed format", function()
            local tempDir = setupTestRepo()
            -- Commit a malformed version first
            fs.writeFile(`{tempDir}/VERSION`, "not-a-version")
            process.exec("git", { "add", "VERSION" }, { cwd = tempDir })
            process.exec("git", { "commit", "-m", "Bad version" }, { cwd = tempDir })

            -- Now set a valid version
            setWorkingVersion(tempDir, "1.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Previous VERSION was not in proper format")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should handle large version numbers", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "100.200.300")
            setWorkingVersion(tempDir, "100.200.301")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Valid patch version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject ridiculously high version numbers", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "999999.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "MAJOR.MINOR.PATCH")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject negative version numbers", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "-1.0.0")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            if not string.find(output, "MAJOR.MINOR.PATCH") then
                error(`Expected output to contain "MAJOR.MINOR.PATCH", got: "{output}"`)
            end
            cleanupTempDir(tempDir)
        end)

        it("should accept version at exact max boundary", function()
            local tempDir = setupTestRepo()
            commitVersion(tempDir, "99999.99999.99998")
            setWorkingVersion(tempDir, "99999.99999.99999")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(true)
            expect(string.find(output, "Valid patch version bump")).to.be.ok()
            cleanupTempDir(tempDir)
        end)

        it("should reject version exceeding max boundary", function()
            local tempDir = setupTestRepo()
            setWorkingVersion(tempDir, "99999.99999.100000")
            local success, output = runVersionCheck(tempDir)
            expect(success).to.equal(false)
            expect(string.find(output, "MAJOR.MINOR.PATCH")).to.be.ok()
            cleanupTempDir(tempDir)
        end)
    end)
end
