import Testing

@testable import SwaTex

@Suite("KnownCommands")
struct KnownCommandsTests {
    @Test func listsFunctionsSymbolsAndMacros() {
        let known = SwaTexEngine.knownControlSequences
        // a function, a math symbol, a text symbol, a built-in macro
        for name in [#"\frac"#, #"\alpha"#, #"\textbackslash"#, #"\dddot"#] {
            #expect(known.contains(name), "\(name)")
        }
        #expect(!known.contains(#"\fracc"#))
        #expect(known.allSatisfy { $0.hasPrefix("\\") })
        #expect(known.count > 1000)
    }

    /// Everything listed is defined in math mode or, for text symbols such as `\AE`, inside
    /// `\text{…}` — it may still fail for a missing argument, never as an undefined command.
    @Test func everyListedNameIsDefined() {
        func undefined(_ latex: String) -> Bool {
            do {
                _ = try parseLaTeX(latex)
                return false
            } catch {
                return error.message.hasPrefix("Undefined control sequence")
            }
        }
        for name in SwaTexEngine.knownControlSequences {
            #expect(!(undefined(name) && undefined("\\text{\(name)}")), "\(name)")
        }
    }

    @Test func listsEnvironments() {
        let envs = SwaTexEngine.knownEnvironments
        for name in ["aligned", "cases", "pmatrix", "array", "CD"] {
            #expect(envs.contains(name), "\(name)")
        }
    }
}
