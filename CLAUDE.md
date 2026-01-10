# Claude Code Guidelines

## Commits

- Always break commits down into logical parts
- Do not co-author yourself in commits

## Formatting

- Run `stylua .` often to ensure that code is formatted properly
- Every file should end in a single newline
- Text should be LF normalized
- Prefer Luau string interpolation using backticks, like `` `Here is a string with an interpolated {value}.` ``
- Always read through existing code to match style

## Luau File Headers

Every Luau file should have this at the top:

```luau
--[[

<File name without extension>

<Description in a few sentences, wrapping by word at column 90>

--]]
```

## Comments

- All comments should word-wrap at column 90

## Functions

- Always add runtime typechecking to function parameters using assert

## Operators

- Use compound assignment operators (`+=`, `-=`, `*=`, `/=`) instead of expanded form

## Print Statements

- Avoid using colons `:` in prints for stylistic reasons
- Structure everything in complete sentences
- Surround strings of interest in quotation marks `"`
- Use `[Usage]` instead of `Usage:` for usage messages

## Lune Documentation

You can read Lune documentation as needed to understand the Lune code you're writing:

- https://lune-org.github.io/docs/api-reference/fs
- https://lune-org.github.io/docs/api-reference/net
- https://lune-org.github.io/docs/api-reference/process
- https://lune-org.github.io/docs/api-reference/*
