--[[

DictSyntaxTest.spec

Tests that Testable.run supports dictionary syntax for test roots
alongside the existing array syntax.

--]]

local Testable = require("../Source/Testable")

return function()
    describe("Dictionary syntax for test roots", function()
        it("should run tests passed as dictionary entries", function()
            local ran = false
            local miniTests = {
                {
                    Name = "MiniTest",
                    Func = function()
                        describe("Mini", function()
                            it("runs", function()
                                ran = true
                                expect(true).to.be.ok()
                            end)
                        end)
                    end,
                },
            }

            local _, passed = Testable.run(miniTests)
            expect(passed).to.equal(true)
            expect(ran).to.equal(true)
        end)

        it("should accept dictionary format { Name = func }", function()
            local ran = false
            local dictTests = {
                InlineTest = function()
                    describe("Inline", function()
                        it("runs from dict", function()
                            ran = true
                            expect(1 + 1).to.equal(2)
                        end)
                    end)
                end,
            }

            local _, passed = Testable.run(dictTests)
            expect(passed).to.equal(true)
            expect(ran).to.equal(true)
        end)

        it("should sort dictionary entries alphabetically", function()
            local order = {}
            local dictTests = {
                ZTest = function()
                    describe("ZTest", function()
                        it("runs", function()
                            table.insert(order, "Z")
                        end)
                    end)
                end,
                ATest = function()
                    describe("ATest", function()
                        it("runs", function()
                            table.insert(order, "A")
                        end)
                    end)
                end,
            }

            Testable.run(dictTests)
            expect(order[1]).to.equal("A")
            expect(order[2]).to.equal("Z")
        end)

        it("should error on empty table", function()
            expect(function()
                Testable.run({})
            end).to.throw()
        end)
    end)
end
