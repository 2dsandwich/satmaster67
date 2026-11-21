import SwiftUI

/// Tutor text with a little typography, so a paragraph isn't one flat grey block:
/// - `**term**` → the key term, bold and bright
/// - "quoted words" (from the passage or question) → the same font, a step brighter
/// - `$math$`, and equations found in plain text (a(b)^x, x = 0, 24/n) → monospaced and tinted, with real superscripts,
///   slashed fractions and √ ≤ ≥ · π, so an equation never blends into the sentence around it
/// Everything else stays in the base color.
@MainActor enum Rich {
    /// One color for every equation, so math reads as math at a glance (a teal that reads on light and dark).
    nonisolated static let ink = Color(red: 0.16, green: 0.66, blue: 0.74)

    private struct Key: Hashable { let s: String, size: CGFloat, weight: Font.Weight, color: Color, ink: Color }
    private static var memo: [Key: Text] = [:]

    /// Parsing costs ~0.4 ms a paragraph and views re-render on every store change, so each result is kept.
    /// `ink` colors the equations: the app's teal, or black inside the Bluebook-style test.
    static func text(_ s: String, size: CGFloat = 13.5, weight: Font.Weight = .regular, color: Color = .secondary, ink: Color = Rich.ink) -> Text {
        let k = Key(s: s, size: size, weight: weight, color: color, ink: ink)
        if let t = memo[k] { return t }
        if memo.count > 2000 { memo.removeAll() }   // replies arriving piece by piece add a key each time
        let t = parse(s, size: size, weight: weight, color: color, ink: ink)
        memo[k] = t
        return t
    }

    /// Khan Academy's MathJax delimiters as the app's own: \(x\) → $x$; \[x\] and $$x$$ → $x$ on a line of its own.
    /// A money sign inside math (\$) becomes a stand-in that MathParse and `tidy` turn back into "$".
    nonisolated static func dollars(_ s: String) -> String {
        guard s.contains("\\(") || s.contains("\\[") || s.contains("$$") else { return s }
        var t = s.replacingOccurrences(of: "\\$", with: "\u{E000}")
        t = t.replacingOccurrences(of: #"(?s)\s*(?:\\\[|\$\$)\s*(.+?)\s*(?:\\\]|\$\$)\s*"#, with: "\n\\$$1\\$\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?s)\\\((.+?)\\\)"#, with: "\\$$1\\$", options: .regularExpression)
        return t.trimmingCharacters(in: .newlines)
    }

    private static func parse(_ s: String, size: CGFloat, weight: Font.Weight, color: Color, ink: Color) -> Text {
        var out = Text(verbatim: "")
        var buf = ""
        let chars = Array(dollars(s))
        var i = 0
        func add(_ t: Text) { out = Text("\(out)\(t)") }
        func flush() {
            guard !buf.isEmpty else { return }
            for (part, isMath) in mathRuns(buf) {
                if isMath { add(math(part, size: size, weight: weight, color: ink)); continue }
                for (piece, tint) in names(tidy(part)) {   // section and domain names in their section's color, same font
                    add(Text(verbatim: piece).font(.system(size: size, weight: weight)).foregroundStyle(tint ?? color))
                }
            }
            buf = ""
        }
        func find(_ close: String, from j: Int, limit: Int = 240) -> Int? {
            let c = Array(close)
            var k = j
            while k + c.count <= chars.count, k - j <= limit {
                if Array(chars[k..<k + c.count]) == c { return k }
                k += 1
            }
            return nil
        }
        while i < chars.count {
            let c = chars[i]
            let prev: Character = i > 0 ? chars[i - 1] : " "
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*", let e = find("**", from: i + 2), e > i + 2 {
                flush()
                add(text(String(chars[i + 2..<e]), size: size, weight: .semibold, color: .primary, ink: ink))   // may hold math or quotes
                i = e + 2; continue
            }
            if c == "$", let e = find("$", from: i + 1, limit: 120), e > i + 1 {
                flush()
                add(math(String(chars[i + 1..<e]), size: size, weight: weight, color: ink))
                i = e + 1; continue
            }
            // Quotes: "…", “…”, or '…' that opens after a space (so apostrophes in don't / student's stay text).
            let close: Character? = c == "\"" ? "\"" : c == "“" ? "”" : (c == "'" || c == "‘") && (prev.isWhitespace || "([".contains(prev)) ? (c == "'" ? "'" : "’") : nil
            if let close, let e = find(String(close), from: i + 1), e > i + 1, e + 1 >= chars.count || !chars[e + 1].isLetter {
                flush()
                let inner = String(chars[i + 1..<e])
                let t = inner.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
                if t.hasPrefix("$"), t.hasSuffix("$"), t.count > 2, !t.dropFirst().dropLast().contains("$") {
                    add(math(String(t.dropFirst().dropLast()), size: size, weight: weight, color: ink))   // a quoted equation is just the equation
                } else {   // quoted words stay in quotes, but math, bold and names inside them are still set
                    let q = Text(verbatim: "“").font(.system(size: size, weight: weight)).foregroundStyle(.primary)
                    let close = Text(verbatim: "”").font(.system(size: size, weight: weight)).foregroundStyle(.primary)
                    add(Text("\(q)\(text(inner, size: size, weight: weight, color: .primary, ink: ink))\(close)"))
                }
                i = e + 1; continue
            }
            buf.append(c); i += 1
        }
        flush()
        return out
    }

    /// Splits plain text into prose and equations. A word is math if it holds = ^ / √ ≤ ≥ < >, looks like 3x, f(x) or 24/n;
    /// operators and the numbers or single letters next to them join the run. Trailing punctuation stays prose.
    static func mathRuns(_ s: String) -> [(String, Bool)] {
        let words = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let punct = CharacterSet(charactersIn: ".,;:!?")
        func core(_ w: String) -> String { w.trimmingCharacters(in: punct) }
        func op(_ w: String) -> Bool { ["=", "<", ">", "≤", "≥", "≠", "+", "-", "−", "×", "÷", "·", "*", "/", "<=", ">="].contains(core(w)) }
        func mathy(_ w: String) -> Bool {
            let c = core(w)
            guard !c.isEmpty, c.count <= 40, c.range(of: #"^\([A-D]\)$"#, options: .regularExpression) == nil else { return false }
            return c.range(of: #"[=^√≤≥<>]|^[0-9.]+[a-rt-zA-Z]$|^[a-zA-Z]?\([^()]*[a-z0-9][^()]*\)|[0-9)]/|/[0-9(]|^[a-z]/[a-z]$"#,
                           options: .regularExpression) != nil
        }
        func joinable(_ w: String) -> Bool { let c = core(w); return !c.isEmpty && (Double(c) != nil || (c.count == 1 && c.first!.isLetter)) }
        var m = words.map { mathy($0) || op($0) }
        for (i, w) in words.enumerated() where !m[i] && joinable(w) {
            if (i > 0 && op(words[i - 1])) || (i + 1 < words.count && op(words[i + 1])) { m[i] = true }
        }
        for (i, w) in words.enumerated() where m[i] && op(w) {   // a lone operator with no math beside it is prose ("-" as a dash)
            if !((i > 0 && m[i - 1] && !op(words[i - 1])) || (i + 1 < words.count && m[i + 1] && !op(words[i + 1]))) { m[i] = false }
        }
        var out: [(String, Bool)] = []
        func push(_ t: String, _ isMath: Bool) {
            if let l = out.last, l.1 == isMath { out[out.count - 1].0 += t } else { out.append((t, isMath)) }
        }
        for (i, w) in words.enumerated() {
            if i > 0 { push(" ", m[i] && m[i - 1]) }
            if m[i], w.hasPrefix(core(w)) {   // "x = 0." → math "x = 0", prose "."
                push(core(w), true)
                if w.count > core(w).count { push(String(w.dropFirst(core(w).count)), false) }
            } else { push(w, m[i]) }
        }
        return out
    }

    /// SAT section and domain names, longest first, with their section.
    static let sectionNames: [(String, String)] = [
        ("Problem-Solving and Data Analysis", "Math"), ("Standard English Conventions", "Reading and Writing"),
        ("Geometry and Trigonometry", "Math"), ("Information and Ideas", "Reading and Writing"), ("Expression of Ideas", "Reading and Writing"),
        ("Craft and Structure", "Reading and Writing"), ("Reading and Writing", "Reading and Writing"), ("Reading & Writing", "Reading and Writing"),
        ("Advanced Math", "Math"), ("Algebra", "Math"), ("Math", "Math"), ("R&W", "Reading and Writing"),
    ]

    /// Splits text around section and domain names (whole words, case as written) so each can wear its section color.
    static func names(_ s: String) -> [(String, Color?)] {
        var out: [(String, Color?)] = [], rest = Substring(s)
        while !rest.isEmpty {
            var best: (Range<Substring.Index>, String)?
            for (n, sec) in sectionNames {
                var from = rest.startIndex
                while let r = rest.range(of: n, range: from..<rest.endIndex) {
                    let before = r.lowerBound == rest.startIndex ? " " : rest[rest.index(before: r.lowerBound)]
                    let after = r.upperBound == rest.endIndex ? " " : rest[r.upperBound]
                    if !before.isLetter && !after.isLetter {
                        if best == nil || r.lowerBound < best!.0.lowerBound { best = (r, sec) }
                        break
                    }
                    from = r.upperBound
                }
            }
            guard let (r, sec) = best else { out.append((String(rest), nil)); break }
            if r.lowerBound > rest.startIndex { out.append((String(rest[..<r.lowerBound]), nil)) }
            out.append((String(rest[r]).replacingOccurrences(of: " ", with: "\u{00A0}"), sectionColor(sec)))
            rest = rest[r.upperBound...]
        }
        return out
    }

    /// Same colors as `Sec.color`, kept here so this file stands alone.
    static func sectionColor(_ s: String) -> Color { s == "Math" ? .cyan : .purple }

    /// Small plain-text math fixes that read better everywhere.
    static func tidy(_ s: String) -> String {
        var t = s
        for (a, b) in [("<=", "≤"), (">=", "≥"), ("!=", "≠"), ("sqrt(", "√("), ("+/-", "±"), ("\u{E000}", "$")] { t = t.replacingOccurrences(of: a, with: b) }
        // Never break "choice A", "Q7 of 22", "35 min", "12 questions" across lines.
        t = t.replacingOccurrences(of: #"\b(choice|Choice|choices|Question|question|Module|module|Q|Q\d+) (\w)"#, with: "$1\u{00A0}$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\d) (s|sec|seconds|min|minutes|%|points|questions|of)\b"#, with: "$1\u{00A0}$2", options: .regularExpression)
        // x^2 → x², 10^-3 → 10⁻³
        let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        var out = "", chars = Array(t), i = 0
        while i < chars.count {
            if chars[i] == "^", i + 1 < chars.count, sup[chars[i + 1]] != nil {
                i += 1
                while i < chars.count, let u = sup[chars[i]] { out.append(u); i += 1 }
                continue
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    /// The subset of LaTeX the tutor writes: \frac{a}{b}, \sqrt{x}, ^ and _ (with or without braces), and named symbols.
    /// An equation set like the SAT's (STIX, italic letters, stacked fractions, raised exponents, √ with a bar),
    /// drawn once as a crisp image and placed in the line, so it reads as math and never breaks across lines.
    static func math(_ m: String, size: CGFloat, scale: CGFloat = 1, weight: Font.Weight = .regular, color: Color = ink) -> Text {
        let nodes = MathParse.row(m)
        let view = MathRow(nodes: nodes, size: size * 1.08, color: color).padding(.horizontal, 1).fixedSize()
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage else { return Text(verbatim: m).foregroundStyle(color) }
        let h = img.size.height
        return Text(Image(nsImage: img)).baselineOffset(-(h / 2 - size * 0.32))   // centre on the text's math axis
    }
}


// MARK: - Math typesetting

/// The pieces of an equation.
indirect enum MathNode: Hashable {
    case text(String, italic: Bool)
    case op(String)
    case frac([MathNode], [MathNode])
    case sqrt([MathNode])
    case script(MathNode, sup: [MathNode]?, sub: [MathNode]?)
}

/// The LaTeX the tutor writes ($\frac{a}{b}$, $x^2$, $\sqrt{x}$, \le, \cdot …) or plain text math (a(b)^x, 24/n).
enum MathParse {
    static let symbols: [(String, String)] = [("\\left", ""), ("\\right", ""), ("\\dfrac", "\\frac"), ("\\tfrac", "\\frac"),
        ("\\cdots", "⋯"), ("\\ldots", "…"), ("\\dots", "…"), ("\\lt", "<"), ("\\gt", ">"), ("\\approx", "≈"), ("\\angle", "∠"),
        ("\\triangle", "△"), ("\\%", "%"), ("\u{E000}", "$"), ("\\neq", "≠"), ("\\ne", "≠"), ("\\leq", "≤"), ("\\geq", "≥"), ("\\le", "≤"), ("\\ge", "≥"),
        ("\\cdot", "·"), ("\\times", "×"), ("\\div", "÷"), ("\\pi", "π"), ("\\theta", "θ"), ("\\pm", "±"), ("\\infty", "∞"),
        ("^\\circ", "°"), ("\\circ", "°"), ("\\,", ""), ("\\ ", ""), ("<=", "≤"), (">=", "≥")]

    static func row(_ m: String) -> [MathNode] {
        var s = m
        for (a, b) in symbols { s = s.replacingOccurrences(of: a, with: b) }
        let c = Array(s)
        var i = 0
        return parse(c, &i, until: nil)
    }

    private static func group(_ c: [Character], _ i: inout Int) -> [MathNode] {
        guard i < c.count else { return [] }
        if c[i] == "{" { i += 1; return parse(c, &i, until: "}") }
        var j = 0   // an index into the one-character array, not into c (x^2 lost its 2)
        let one = parse([c[i]], &j, until: nil) // a single character
        i += 1
        return one
    }

    private static func parse(_ c: [Character], _ i: inout Int, until end: Character?) -> [MathNode] {
        var out: [MathNode] = []
        func word(_ w: String) -> Bool { i + w.count <= c.count && String(c[i..<i + w.count]) == w }
        while i < c.count {
            let ch = c[i]
            if let end, ch == end { i += 1; break }
            if word("\\frac") { i += 5; let a = group(c, &i), b = group(c, &i); out.append(.frac(a, b)); continue }
            if word("\\sqrt") { i += 5; out.append(.sqrt(group(c, &i))); continue }
            if word("\\text{") || word("\\mathrm{") {   // words inside math stay upright, spaces and all
                i += word("\\text{") ? 6 : 8
                var t = ""
                while i < c.count, c[i] != "}" { t.append(c[i]); i += 1 }
                i += 1
                out.append(.text(t, italic: false)); continue
            }
            if ch == "^" || ch == "_" {
                i += 1
                let g = group(c, &i), base = out.popLast() ?? .text("", italic: false)
                if case .script(let b, let sup, let sub) = base {
                    out.append(ch == "^" ? .script(b, sup: g, sub: sub) : .script(b, sup: sup, sub: g))
                } else {
                    out.append(ch == "^" ? .script(base, sup: g, sub: nil) : .script(base, sup: nil, sub: g))
                }
                continue
            }
            if ch == "\\" {   // \sin, \cos, \log … upright with a thin space after; any other unknown command is dropped
                var name = ""
                i += 1
                while i < c.count, c[i].isLetter { name.append(c[i]); i += 1 }
                if ["sin", "cos", "tan", "log", "ln", "exp"].contains(name) { out.append(.text(name + "\u{2009}", italic: false)) }
                continue
            }
            if ch == "{" || ch == "}" || ch == " " { i += 1; continue }
            let shown = ch == "-" ? "−" : ch == "*" ? "·" : String(ch)
            // A sign at the start, or after "(" or another operator, is part of the number ("−12"), not a spaced operator.
            let unary = (shown == "−" || shown == "+") && (out.isEmpty || { if case .op = out.last! { return true }; if case .text("(", _) = out.last! { return true }; return false }())
            if "=<>≤≥≠+−·×÷±".contains(shown), !unary { out.append(.op(shown)) }
            else { out.append(.text(shown, italic: ch.isLetter && ch.isASCII)) }
            i += 1
        }
        return out
    }
}

/// Lays an equation out like a textbook: STIX Two, italic variables, upright numbers, spaced operators.
struct MathRow: View {
    let nodes: [MathNode]
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, n in piece(n) }
        }
        .foregroundStyle(color)
    }

    private func font(_ italic: Bool) -> Font { .custom(italic ? "STIXTwoText-Italic" : "STIXTwoText", size: size) }

    @ViewBuilder private func piece(_ n: MathNode) -> some View {
        switch n {
        case .text(let t, let italic):
            Text(verbatim: t).font(font(italic))
        case .op(let o):
            Text(verbatim: o).font(.custom("STIXTwoMath-Regular", size: size)).padding(.horizontal, size * 0.22)
        case .frac(let a, let b):
            VStack(spacing: size * 0.08) {
                MathRow(nodes: a, size: size * 0.82, color: color)
                Rectangle().frame(height: max(1, size * 0.055))
                MathRow(nodes: b, size: size * 0.82, color: color)
            }
            .fixedSize()
            .padding(.horizontal, size * 0.08)
        case .sqrt(let a):
            HStack(alignment: .bottom, spacing: 0) {
                Text(verbatim: "√").font(.custom("STIXTwoMath-Regular", size: size * 1.05))
                MathRow(nodes: a, size: size, color: color)
                    .padding(.top, size * 0.12)
                    .overlay(alignment: .top) { Rectangle().frame(height: max(1, size * 0.055)) }
            }
        case .script(let base, let sup, let sub):
            HStack(alignment: .center, spacing: size * 0.03) {
                MathRow(nodes: [base], size: size, color: color)
                VStack(alignment: .leading, spacing: 0) {
                    if let sup { MathRow(nodes: sup, size: size * 0.66, color: color) } else { Color.clear.frame(width: 1, height: size * 0.4) }
                    Color.clear.frame(width: 1, height: size * 0.32)
                    if let sub { MathRow(nodes: sub, size: size * 0.66, color: color) } else { Color.clear.frame(width: 1, height: size * 0.3) }
                }
            }
        }
    }
}
