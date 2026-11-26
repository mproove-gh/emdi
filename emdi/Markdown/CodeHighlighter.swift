import Foundation

enum CodeTokenKind: Equatable, Sendable {
    case keyword, type, string, number, comment
    /// HTML/XML attribute names, Swift `@attributes`, decorators.
    case attribute
    /// JSON/YAML keys, CSS properties, shell `$variables`.
    case property
}

struct CodeToken: Equatable, Sendable {
    var kind: CodeTokenKind
    /// UTF-16 range inside the code that was tokenized.
    var range: NSRange
}

/// A small, dependency-free syntax highlighter: one scanner driven by per-language rules
/// (keywords, comment and string syntax), plus a dedicated scanner for HTML/XML.
/// It aims for "good enough to read", not for a full parser. Unknown languages get no colors.
enum CodeHighlighter {
    static func tokens(in code: String, language: String?) -> [CodeToken] {
        guard let name = language?.split(separator: " ").first?.lowercased(), !name.isEmpty else { return [] }
        let chars = Array(code.utf16)
        if markupLanguages.contains(name) {
            var scanner = MarkupScanner(chars: chars)
            return scanner.scan()
        }
        guard let spec = LanguageSpec.named(name) else { return [] }
        var scanner = Scanner(chars: chars, spec: spec)
        return scanner.scan()
    }

    static let markupLanguages: Set<String> = ["html", "htm", "xml", "svg", "plist", "xhtml", "vue"]
}

// MARK: - Language rules

struct LanguageSpec: Sendable {
    var keywords: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var stringDelimiters: Set<unichar> = [quote]
    /// `"""` (Swift, Python, Kotlin) and `'''` (Python) strings.
    var tripleQuotedStrings = false
    /// Backtick strings may span lines (JavaScript templates, Go raw strings).
    var multilineBackticks = false
    /// Capitalized identifiers are types (Swift, Java, Rust, …).
    var capitalizedTypes = false
    var caseInsensitiveKeywords = false
    /// A string followed by `:` is a key (JSON).
    var stringKeys = false
    /// An identifier followed by `:` is a key (YAML, CSS).
    var identifierKeys = false
    /// `$name` / `${name}` are variables (shell, PHP).
    var dollarVariables = false
    /// `@name` is an attribute (Swift, Kotlin, Java, Python decorators).
    var atAttributes = false
    /// Characters allowed inside identifiers besides letters, digits and `_`.
    var extraIdentifierCharacters: Set<unichar> = []

    static func named(_ name: String) -> LanguageSpec? {
        switch name {
        case "swift": swift
        case "python", "py", "python3": python
        case "javascript", "js", "jsx", "mjs", "cjs", "typescript", "ts", "tsx": javascript
        case "java", "kotlin", "kt", "kts", "scala", "dart", "groovy": jvm
        case "c", "h", "cpp", "c++", "cc", "cxx", "hpp", "objc", "objective-c", "objectivec", "m", "mm": cFamily
        case "csharp", "cs", "c#": csharp
        case "go", "golang": go
        case "rust", "rs": rust
        case "php": php
        case "ruby", "rb": ruby
        case "bash", "sh", "zsh", "shell", "console", "shellscript", "fish": shell
        case "json", "jsonc", "json5", "geojson": json
        case "yaml", "yml": yaml
        case "toml", "ini", "conf", "properties": toml
        case "sql", "mysql", "postgresql", "postgres", "sqlite", "plsql": sql
        case "css", "scss", "sass", "less": css
        case "lua": lua
        default: nil
        }
    }

    private static let cStyle = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"),
                                             stringDelimiters: [quote, apostrophe], capitalizedTypes: true)

    static let swift: LanguageSpec = {
        var spec = cStyle
        spec.stringDelimiters = [quote]
        spec.tripleQuotedStrings = true
        spec.atAttributes = true
        spec.keywords = words("""
            actor any as associatedtype async await break case catch class continue convenience default defer \
            deinit didSet do dynamic else enum extension fallthrough false fileprivate final for func get guard \
            if import in indirect init inout internal is isolated lazy let mutating nil nonisolated nonmutating \
            open operator optional override package private protocol public repeat required rethrows return self \
            Self set some static struct subscript super switch throw throws true try typealias unowned var weak \
            where while willSet consume borrowing consuming sending
            """)
        return spec
    }()

    static let python: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["#"], stringDelimiters: [quote, apostrophe])
        spec.tripleQuotedStrings = true
        spec.capitalizedTypes = true
        spec.atAttributes = true
        spec.keywords = words("""
            and as assert async await break class continue def del elif else except False finally for from global \
            if import in is lambda None nonlocal not or pass raise return True try while with yield match case self
            """)
        return spec
    }()

    static let javascript: LanguageSpec = {
        var spec = cStyle
        spec.stringDelimiters = [quote, apostrophe, backtick]
        spec.multilineBackticks = true
        spec.atAttributes = true
        spec.extraIdentifierCharacters = [dollar]
        spec.keywords = words("""
            abstract as async await break case catch class const continue debugger declare default delete do else \
            enum export extends false finally for from function get if implements import in instanceof interface \
            keyof let new null of private protected public readonly return set static super switch this throw true \
            try type typeof undefined var void while with yield
            """)
        return spec
    }()

    static let jvm: LanguageSpec = {
        var spec = cStyle
        spec.tripleQuotedStrings = true
        spec.atAttributes = true
        spec.keywords = words("""
            abstract as boolean break byte case catch char class companion const continue data def default do \
            double else enum extends false final finally float for fun if implements import in instanceof int \
            interface internal is long native new null object open override package private protected public \
            return sealed short static super switch synchronized this throw throws true try val var void volatile \
            when while
            """)
        return spec
    }()

    static let cFamily: LanguageSpec = {
        var spec = cStyle
        spec.atAttributes = true  // Objective-C @interface, @property, …
        spec.lineComments = ["//", "#"]  // # lines are preprocessor directives, shown like comments.
        spec.keywords = words("""
            auto bool break case catch char class const constexpr continue default delete do double else enum \
            explicit extern false float for friend goto if inline int long namespace new noexcept nullptr \
            operator private protected public register return short signed sizeof static struct switch template \
            this throw true try typedef typename union unsigned using virtual void volatile while id nil NULL YES NO \
            self super instancetype
            """)
        return spec
    }()

    static let csharp: LanguageSpec = {
        var spec = cStyle
        spec.keywords = words("""
            abstract as async await base bool break byte case catch char class const continue decimal default \
            delegate do double else enum event explicit false finally float for foreach get if implicit in int \
            interface internal is lock long namespace new null object out override params private protected \
            public readonly record ref return sealed set short static string struct switch this throw true try \
            typeof uint ulong using var virtual void while yield
            """)
        return spec
    }()

    static let go: LanguageSpec = {
        var spec = cStyle
        spec.stringDelimiters = [quote, apostrophe, backtick]
        spec.multilineBackticks = true
        spec.keywords = words("""
            break case chan const continue default defer else fallthrough false for func go goto if import \
            interface iota map nil package range return select struct switch true type var bool byte error \
            float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 any
            """)
        return spec
    }()

    static let rust: LanguageSpec = {
        var spec = cStyle
        spec.stringDelimiters = [quote]  // ' is also used for lifetimes
        spec.keywords = words("""
            as async await break const continue crate dyn else enum extern false fn for if impl in let loop \
            match mod move mut pub ref return self Self static struct super trait true type unsafe use where \
            while bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize Some None Ok Err
            """)
        return spec
    }()

    static let php: LanguageSpec = {
        var spec = cStyle
        spec.lineComments = ["//", "#"]
        spec.dollarVariables = true
        spec.capitalizedTypes = false
        spec.keywords = words("""
            abstract and array as break case catch class clone const continue declare default do echo else \
            elseif empty enum extends false final finally fn for foreach function global if implements include \
            instanceof interface isset list match namespace new null or print private protected public readonly \
            require return static switch throw trait true try unset use var while yield
            """)
        return spec
    }()

    static let ruby: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["#"], stringDelimiters: [quote, apostrophe])
        spec.capitalizedTypes = true
        spec.keywords = words("""
            alias and begin break case class def defined? do else elsif end ensure false for if in module next \
            nil not or redo rescue retry return self super then true undef unless until when while yield \
            attr_accessor attr_reader attr_writer require private protected public
            """)
        return spec
    }()

    static let shell: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["#"], stringDelimiters: [quote, apostrophe])
        spec.dollarVariables = true
        spec.extraIdentifierCharacters = [hyphen]
        spec.keywords = words("""
            if then else elif fi case esac for select while until do done in function return exit export local \
            readonly declare unset source alias set shift break continue echo printf cd eval exec test true false
            """)
        return spec
    }()

    static let json: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
        spec.stringKeys = true
        spec.keywords = ["true", "false", "null"]
        return spec
    }()

    static let yaml: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["#"], stringDelimiters: [quote, apostrophe])
        spec.identifierKeys = true
        spec.stringKeys = true
        spec.extraIdentifierCharacters = [hyphen, dot]
        spec.keywords = ["true", "false", "null", "yes", "no", "on", "off", "~"]
        return spec
    }()

    static let toml: LanguageSpec = {
        var spec = yaml
        spec.lineComments = ["#", ";"]
        spec.tripleQuotedStrings = true
        spec.keywords = ["true", "false"]
        return spec
    }()

    static let sql: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["--"], blockComment: ("/*", "*/"), stringDelimiters: [apostrophe, quote])
        spec.caseInsensitiveKeywords = true
        spec.keywords = words("""
            add all alter and as asc begin between by case check column commit constraint create cross database \
            default delete desc distinct drop else end exists false foreign from full group having if in index \
            inner insert into is join key left like limit not null offset on or order outer primary references \
            returning right rollback select set table then transaction true union unique update using values \
            view when where with integer int text varchar boolean real date timestamp count sum avg min max
            """)
        return spec
    }()

    static let css: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: [quote, apostrophe])
        spec.identifierKeys = true
        spec.atAttributes = true  // @media, @import, …
        spec.extraIdentifierCharacters = [hyphen]
        spec.keywords = ["important", "inherit", "initial", "none", "auto", "unset"]
        return spec
    }()

    static let lua: LanguageSpec = {
        var spec = LanguageSpec(lineComments: ["--"], stringDelimiters: [quote, apostrophe])
        spec.keywords = words("""
            and break do else elseif end false for function goto if in local nil not or repeat return then true \
            until while self
            """)
        return spec
    }()

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
    }
}

private let quote = unichar(UInt8(ascii: "\""))
private let apostrophe = unichar(UInt8(ascii: "'"))
private let backtick = unichar(UInt8(ascii: "`"))
private let backslash = unichar(UInt8(ascii: "\\"))
private let newline = unichar(UInt8(ascii: "\n"))
private let dollar = unichar(UInt8(ascii: "$"))
private let hyphen = unichar(UInt8(ascii: "-"))
private let dot = unichar(UInt8(ascii: "."))
private let colon = unichar(UInt8(ascii: ":"))
private let at = unichar(UInt8(ascii: "@"))
private let underscore = unichar(UInt8(ascii: "_"))
private let lessThan = unichar(UInt8(ascii: "<"))
private let greaterThan = unichar(UInt8(ascii: ">"))
private let equals = unichar(UInt8(ascii: "="))
private let slash = unichar(UInt8(ascii: "/"))
private let openBrace = unichar(UInt8(ascii: "{"))
private let closeBrace = unichar(UInt8(ascii: "}"))

private func isLetter(_ c: unichar) -> Bool {
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == underscore || c > 127
}

private func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

private func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }

// MARK: - Generic scanner

private struct Scanner {
    let chars: [unichar]
    let spec: LanguageSpec
    var tokens: [CodeToken] = []
    let lineComments: [[unichar]]
    let blockOpen: [unichar]?
    let blockClose: [unichar]?

    init(chars: [unichar], spec: LanguageSpec) {
        self.chars = chars
        self.spec = spec
        lineComments = spec.lineComments.map { Array($0.utf16) }
        blockOpen = spec.blockComment.map { Array($0.open.utf16) }
        blockClose = spec.blockComment.map { Array($0.close.utf16) }
    }

    func matches(_ pattern: [unichar], at index: Int) -> Bool {
        guard index + pattern.count <= chars.count else { return false }
        for (offset, c) in pattern.enumerated() where chars[index + offset] != c { return false }
        return true
    }

    mutating func emit(_ kind: CodeTokenKind, _ start: Int, _ end: Int) {
        if end > start { tokens.append(CodeToken(kind: kind, range: NSRange(location: start, length: end - start))) }
    }

    func endOfLine(from index: Int) -> Int {
        var i = index
        while i < chars.count, chars[i] != newline { i += 1 }
        return i
    }

    /// The next non-blank character after `index` on the same line is a `:` (but not `::`).
    func isFollowedByColon(_ index: Int) -> Bool {
        var i = index
        while i < chars.count, isSpace(chars[i]) { i += 1 }
        return i < chars.count && chars[i] == colon && (i + 1 >= chars.count || chars[i + 1] != colon)
    }

    mutating func scan() -> [CodeToken] {
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if let blockOpen, let blockClose, matches(blockOpen, at: i) {
                var j = i + blockOpen.count
                while j < chars.count, !matches(blockClose, at: j) { j += 1 }
                j = min(j + blockClose.count, chars.count)
                emit(.comment, i, j)
                i = j
                continue
            }

            if let comment = lineComments.first(where: { matches($0, at: i) }),
               comment != [unichar(UInt8(ascii: "#"))] || i == 0 || isSpace(chars[i - 1]) || chars[i - 1] == newline {
                let end = endOfLine(from: i)
                emit(.comment, i, end)
                i = end
                continue
            }

            if spec.tripleQuotedStrings, c == quote || c == apostrophe,
               matches([c, c, c], at: i) {
                var j = i + 3
                while j < chars.count, !matches([c, c, c], at: j) { j += chars[j] == backslash ? 2 : 1 }
                j = min(j + 3, chars.count)
                emit(.string, i, j)
                i = j
                continue
            }

            if spec.stringDelimiters.contains(c) {
                let multiline = c == backtick && spec.multilineBackticks
                var j = i + 1
                while j < chars.count, chars[j] != c, multiline || chars[j] != newline {
                    j += chars[j] == backslash ? 2 : 1
                }
                j = min(j + 1, chars.count)
                emit(spec.stringKeys && isFollowedByColon(j) ? .property : .string, i, j)
                i = j
                continue
            }

            if isDigit(c), i == 0 || !isIdentifierCharacter(chars[i - 1]) {
                var j = i + 1
                while j < chars.count, isDigit(chars[j]) || isLetter(chars[j]) || chars[j] == dot {
                    if chars[j] == dot, j + 1 < chars.count, !isDigit(chars[j + 1]) { break }
                    j += 1
                }
                emit(.number, i, j)
                i = j
                continue
            }

            if spec.dollarVariables, c == dollar, i + 1 < chars.count {
                var j = i + 1
                if chars[j] == openBrace {
                    while j < chars.count, chars[j] != closeBrace, chars[j] != newline { j += 1 }
                    j = min(j + 1, chars.count)
                } else {
                    while j < chars.count, isLetter(chars[j]) || isDigit(chars[j]) { j += 1 }
                    if j == i + 1, j < chars.count, !isSpace(chars[j]) { j += 1 }  // $1, $?, $@
                }
                emit(.property, i, j)
                i = j
                continue
            }

            if spec.atAttributes, c == at, i + 1 < chars.count, isLetter(chars[i + 1]) {
                var j = i + 1
                while j < chars.count, isIdentifierCharacter(chars[j]) { j += 1 }
                emit(.attribute, i, j)
                i = j
                continue
            }

            if isLetter(c) {
                var j = i + 1
                while j < chars.count, isIdentifierCharacter(chars[j]) { j += 1 }
                let word = String(utf16CodeUnits: Array(chars[i..<j]), count: j - i)
                let keyword = spec.caseInsensitiveKeywords ? spec.keywords.contains(word.lowercased())
                                                           : spec.keywords.contains(word)
                if spec.identifierKeys, isFollowedByColon(j), !keyword {
                    emit(.property, i, j)
                } else if keyword {
                    emit(.keyword, i, j)
                } else if spec.capitalizedTypes, c >= 65, c <= 90 {
                    emit(.type, i, j)
                }
                i = j
                continue
            }

            i += 1
        }
        return tokens
    }

    func isIdentifierCharacter(_ c: unichar) -> Bool {
        isLetter(c) || isDigit(c) || spec.extraIdentifierCharacters.contains(c)
    }
}

// MARK: - HTML / XML

private struct MarkupScanner {
    let chars: [unichar]
    var tokens: [CodeToken] = []

    mutating func emit(_ kind: CodeTokenKind, _ start: Int, _ end: Int) {
        if end > start { tokens.append(CodeToken(kind: kind, range: NSRange(location: start, length: end - start))) }
    }

    func starts(with string: String, at index: Int) -> Bool {
        let pattern = Array(string.utf16)
        guard index + pattern.count <= chars.count else { return false }
        return Array(chars[index..<index + pattern.count]) == pattern
    }

    mutating func scan() -> [CodeToken] {
        var i = 0
        while i < chars.count {
            guard chars[i] == lessThan else { i += 1; continue }

            if starts(with: "<!--", at: i) {
                var j = i + 4
                while j < chars.count, !starts(with: "-->", at: j) { j += 1 }
                j = min(j + 3, chars.count)
                emit(.comment, i, j)
                i = j
                continue
            }

            // Tag name, after `<`, `</`, `<?` or `<!`.
            var j = i + 1
            if j < chars.count, chars[j] == slash || chars[j] == unichar(UInt8(ascii: "?")) || chars[j] == unichar(UInt8(ascii: "!")) {
                j += 1
            }
            let nameStart = j
            while j < chars.count, isLetter(chars[j]) || isDigit(chars[j]) || chars[j] == hyphen || chars[j] == colon {
                j += 1
            }
            guard j > nameStart else { i += 1; continue }
            emit(.keyword, nameStart, j)

            // Attributes up to `>`.
            while j < chars.count, chars[j] != greaterThan {
                let c = chars[j]
                if c == quote || c == apostrophe {
                    var k = j + 1
                    while k < chars.count, chars[k] != c { k += 1 }
                    k = min(k + 1, chars.count)
                    emit(.string, j, k)
                    j = k
                } else if isLetter(c) {
                    var k = j + 1
                    while k < chars.count, isLetter(chars[k]) || isDigit(chars[k]) || chars[k] == hyphen || chars[k] == colon {
                        k += 1
                    }
                    emit(.attribute, j, k)
                    j = k
                } else {
                    j += 1
                }
            }
            i = j
        }
        return tokens
    }
}
