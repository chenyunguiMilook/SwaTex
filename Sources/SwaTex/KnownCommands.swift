extension SwaTexEngine {
    /// Every control sequence the engine understands before any `\def` / `\newcommand`: functions,
    /// math and text symbols and built-in macros, each with its leading backslash (`"\\frac"`).
    /// Hosts use it to suggest a spelling for an undefined command, or to tell a string-escape
    /// accident (`"\theta"` arriving as TAB + `heta`) from intended whitespace.
    public static let knownControlSequences: Set<String> = {
        var names = Set(Functions.registry.keys)
        names.formUnion(SymbolMaps.mathByName.keys)
        names.formUnion(SymbolMaps.textByName.keys)
        names.formUnion(MacroExpander.builtinMacroTable.keys)
        return names.filter { $0.hasPrefix("\\") && $0.count > 1 }
    }()

    /// Every environment name `\begin{…}` accepts (`"aligned"`, `"pmatrix"`, …).
    public static let knownEnvironments: Set<String> = Set(Environments.registry.keys)
}
