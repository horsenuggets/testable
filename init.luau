const Testable = require("@self/Source/Testable")

export type Expect<Custom = {}> = Testable.Expect<Custom>
export type Expectation<Custom = {}> = Testable.Expectation<Custom>
export type Matcher = Testable.Matcher
export type MatcherResult = Testable.MatcherResult

return Testable
