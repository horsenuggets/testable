--[[

Git

Asks git which files changed since a ref. The command runner is injected, so the
decisions about which commands to run and how to read their output are tested without a
real repository.

--]]

export type ExecResult = {
    Ok: boolean,
    Stderr: string,
    Stdout: string,
}
export type Exec = (arguments: { string }, workingDirectory: string) -> ExecResult

const Git = {}

--[[
    Splits the NUL-separated output of a git command run with "-z" into paths.

    @param output - The raw standard output of the command
    @return The listed paths, in order
]]
function Git.parseNameList(output: string): { string }
    assert(type(output) == "string", "output must be a string")

    const names = {}
    for name in string.gmatch(output, "[^%z]+") do
        table.insert(names, name)
    end
    return names
end

--[[
    Lists the files that differ between a ref and the working tree, including changes
    that are not committed yet and files that are not tracked yet. Only files under the
    root are reported.

    @param exec - Runs git with the given arguments in the given directory
    @param root - The project root, which must be inside a git repository
    @param ref - The git ref to compare against, such as "origin/main"
    @return Sorted, root-relative paths of the changed files
]]
function Git.changedFiles(exec: Exec, root: string, ref: string): { string }
    assert(type(exec) == "function", "exec must be a function")
    assert(type(root) == "string", "root must be a string")
    assert(type(ref) == "string", "ref must be a string")

    -- A ref that starts with a dash would be read by git as an option.
    if ref == "" or string.sub(ref, 1, 1) == "-" then
        error(`"{ref}" is not a valid git ref.`, 0)
    end

    if not exec({ "rev-parse", "--is-inside-work-tree" }, root).Ok then
        error(`Changed files can't be found because "{root}" is not inside a git repository.`, 0)
    end
    if not exec({ "rev-parse", "--verify", "--quiet", `{ref}^\{commit}` }, root).Ok then
        error(`"{ref}" is not a valid git ref.`, 0)
    end

    const diff = exec({ "diff", "--name-only", "--relative", "-z", ref, "--" }, root)
    if not diff.Ok then
        error(`Git could not compare the working tree against "{ref}". {diff.Stderr}`, 0)
    end
    const untracked = exec({ "ls-files", "--others", "--exclude-standard", "-z" }, root)
    if not untracked.Ok then
        error(`Git could not list the untracked files. {untracked.Stderr}`, 0)
    end

    const seen: { [string]: boolean } = {}
    const files = {}
    for _, output in { diff.Stdout, untracked.Stdout } do
        for _, name in Git.parseNameList(output) do
            if not seen[name] then
                seen[name] = true
                table.insert(files, name)
            end
        end
    end
    table.sort(files)

    return files
end

return Git
