import Foundation
import SwiftUI

/// Turns the text of College Board's My Practice "Score Details" page into an `Official`.
/// The real page text has not been seen, so the parser reads anything that looks like rows of
/// "question number, answer, answer, result" and falls back to the AI model when it finds too few.
enum Importer {
    static let expected = 98
    private static let maxQuestion = ["Reading and Writing": 27, "Math": 22]

    // MARK: Deterministic parser

    private struct Row { var n: Int; var tokens: [String] = []; var result: String? }

    static func parse(_ text: String) -> Official {
        if let o = scoreDetails(text) { return o }
        var o = Official()
        o.raw = text
        (o.total, o.readingWriting, o.math) = scores(text)

        var section = "Reading and Writing", module = 1, last = 0
        var row: Row?
        var yoursFirst = false, sawOrder = false

        func flush() {
            defer { row = nil }
            guard let r = row, let first = r.tokens.first else { return }
            let t = r.tokens
            var c = first, y = ""
            if t.count >= 2 { (c, y) = yoursFirst ? (t[1], t[0]) : (t[0], t[1]) }
            else if r.result == "CORRECT" { y = c }
            guard !c.isEmpty else { return }
            o.answers[Session.key(section, module, r.n)] = .init(correct: c, yours: y.isEmpty ? nil : y)
        }

        for line in lines(text) {
            let low = line.lowercased()
            if low.contains("correct answer") || low.contains("correct response") || low.contains("your answer")
                || low.contains("your response") || low.contains("student response") {
                if !sawOrder {   // one header cell per line: the first one seen decides
                    let y = low.range(of: "your") ?? low.range(of: "student"), c = low.range(of: "correct")
                    yoursFirst = y != nil && (c == nil || y!.lowerBound < c!.lowerBound)
                    sawOrder = true
                }
                continue
            }
            if let h = sectionHeader(line) {
                flush()
                section = h.section ?? section
                module = h.module ?? (h.section != nil ? 1 : module)
                last = 0
                continue
            }

            let toks = tokens(line)
            let known = toks.filter { kind($0) != nil }.count
            guard known > 0, known >= toks.count - known else { continue }
            var rest = toks[...]
            if let f = rest.first, let n = number(f) {
                let done = row.map { $0.tokens.count >= 2 || (!$0.tokens.isEmpty && $0.result != nil) } ?? true
                let reset = n == 1 && last > 1
                let tail = rest.dropFirst()
                if done, n <= maxQuestion[section] ?? 22, reset || (tail.isEmpty ? n == last + 1 : n > last) {
                    flush()
                    if reset { if module == 1 { module = 2 } else { section = "Math"; module = 1 } }
                    row = Row(n: n)
                    last = n
                    rest = tail
                }
            }
            for t in rest {
                switch kind(t) {
                case "result": row?.result = t
                case "blank": if let r = row, r.tokens.count < 2 { row?.tokens.append("") }
                case "answer": if let r = row, r.tokens.count < 2 { row?.tokens.append(t) }
                default: break
                }
            }
        }
        flush()
        return o
    }

    /// My Practice "Score Details" → Questions Overview, as copied from the page (checked on a real copy, Nov 2026):
    ///   "3<TAB>Reading and Writing<TAB>[correct answer]<TAB>" / "[your answer] Incorrect" / "Craft and Structure"
    /// Numbering restarts for module 2 of each section. With "Show Correct Answers" off the answer cells are empty,
    /// so the result word alone grades the question.
    static func scoreDetails(_ text: String) -> Official? {
        let rowRE = try! NSRegularExpression(pattern: #"^(\d{1,2})\t+(Reading and Writing|Math)\b\t*(.*)$"#)
        let domains = ["Information and Ideas", "Craft and Structure", "Expression of Ideas", "Standard English Conventions",
                       "Algebra", "Advanced Math", "Problem-Solving and Data Analysis", "Geometry and Trigonometry"]
        var o = Official()
        o.raw = text
        (o.total, o.readingWriting, o.math) = scores(text)
        var last: [String: Int] = [:], module: [String: Int] = [:]
        var key: String?
        for raw in text.replacingOccurrences(of: "\u{00A0}", with: " ").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let ns = raw as NSString
            if let m = rowRE.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) {
                let n = Int(ns.substring(with: m.range(at: 1)))!, sec = ns.substring(with: m.range(at: 2))
                if n <= last[sec, default: 0] { module[sec] = 2 }
                last[sec] = n
                let k = Session.key(sec, module[sec] ?? 1, n)
                let cells = ns.substring(with: m.range(at: 3)).split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                o.answers[k] = .init(correct: cells.first ?? "", yours: cells.count > 1 ? cells[1] : nil)
                key = k
                continue
            }
            guard let k = key, !line.isEmpty else { continue }
            if let d = domains.first(where: { line == $0 }) { o.answers[k]?.domain = d; key = nil; continue }
            let words = line.split(separator: " ").map(String.init)
            guard let w = words.last?.lowercased(), ["correct", "incorrect", "omitted", "unanswered"].contains(w) else { continue }
            o.answers[k]?.right = w == "correct"
            if words.count > 1, o.answers[k]?.yours == nil { o.answers[k]?.yours = words.dropLast().joined(separator: " ") }
            if w == "correct", o.answers[k]?.yours == nil, let c = o.answers[k]?.correct, !c.isEmpty { o.answers[k]?.yours = c }
        }
        return o.answers.count >= 20 ? o : nil
    }

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func sub(_ s: String, _ pattern: String, _ with: String) -> String {
        s.replacingOccurrences(of: pattern, with: with, options: [.regularExpression, .caseInsensitive])
    }

    /// Words and glyphs for the result column become CORRECT / INCORRECT / OMIT so they split like any cell.
    private static func tokens(_ line: String) -> [String] {
        var s = line.replacingOccurrences(of: "|", with: " ")
        s = sub(s, "\\b(no answer|not answered|unanswered|omitted|skipped|no response)\\b", " OMIT ")
        s = sub(s, "\\b(incorrect|wrong)\\b", " INCORRECT ")
        s = sub(s, "\\b(correct|right)\\b", " CORRECT ")
        s = sub(s, "[✓✔]", " CORRECT ")
        s = sub(s, "[✗✘×]", " INCORRECT ")
        var out: [String] = [], join = false
        for w in s.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if w.lowercased() == "or" { join = true; continue }
            if join || w.hasPrefix(",") || out.last?.hasSuffix(",") == true, !out.isEmpty {
                out[out.count - 1] += (out.last!.hasSuffix(",") || w.hasPrefix(",") ? "" : ",") + w
            } else { out.append(w) }
            join = false
        }
        return out
    }

    private static let atom = "(?:-?\\d*\\.?\\d+(?:/\\d+)?|[A-D])"

    private static func kind(_ t: String) -> String? {
        if ["CORRECT", "INCORRECT", "OMIT"].contains(t) { return "result" }
        if t.range(of: "^[—–-]+$", options: .regularExpression) != nil { return "blank" }
        if t.range(of: "^\(atom)(,\(atom))*$", options: .regularExpression) != nil { return "answer" }
        if number(t) != nil || ["question", "q", "#"].contains(t.lowercased()) { return "filler" }
        return nil
    }

    private static func number(_ t: String) -> Int? {
        guard let r = t.range(of: "^[Qq]?(\\d{1,2})[.):]?$", options: .regularExpression) else { return nil }
        return Int(t[r].filter(\.isNumber)).flatMap { (1...27).contains($0) ? $0 : nil }
    }

    /// "Math", "Reading and Writing", "Module 2", "Math: Module 1". Score lines (a 3-digit number) are not headers.
    private static func sectionHeader(_ line: String) -> (section: String?, module: Int?)? {
        let low = line.lowercased()
        var module: Int?
        if let r = low.range(of: "module\\s*([12])", options: .regularExpression) { module = Int(low[r].filter(\.isNumber)) }
        let rest = sub(low, "module\\s*[12]", "").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard !rest.contains(where: \.isNumber), rest.count < 40 else { return nil }
        var section: String?
        if rest.hasPrefix("reading and writing") || rest.hasPrefix("reading & writing") { section = "Reading and Writing" }
        else if rest == "math" || rest == "mathematics" || rest.hasPrefix("math section") || rest.hasPrefix("math:") { section = "Math" }
        guard section != nil || (module != nil && rest.isEmpty) else { return nil }
        return (section, module)
    }

    private static func scores(_ text: String) -> (Int?, Int?, Int?) {
        // Scores sit above the answer table: a grid-in answer in a row like "7  Math  410" is not a section score.
        let lines = text.components(separatedBy: .newlines)
        let stop = lines.firstIndex { l in
            l.trimmingCharacters(in: .whitespaces).lowercased() == "module 1" || l.range(of: #"^\s*\d{1,2}[\t ]+\S"#, options: .regularExpression) != nil
        } ?? lines.count
        let flat = lines[..<stop].joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        func first(_ patterns: [String], _ range: ClosedRange<Int>) -> Int? {
            for p in patterns {
                guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { continue }
                for m in re.matches(in: flat, range: NSRange(flat.startIndex..., in: flat)) {
                    if let r = Range(m.range(at: 1), in: flat), let v = Int(flat[r]), range.contains(v) { return v }
                }
            }
            return nil
        }
        func section(_ name: String) -> Int? {
            first(["\(name)(?: section)?(?: score)?[^0-9]{0,30}?\\b(\\d{3})\\b", "\\b(\\d{3})\\s*(?:/\\s*800\\s*)?\(name)"], 200...800)
        }
        let rw = "(?:reading\\s*(?:and|&)\\s*writing)", math = "(?:math(?:ematics)?)"
        return (first(["total score[^0-9]{0,40}?\\b(\\d{3,4})\\b", "\\b(\\d{3,4})\\s*(?:/\\s*1600\\s*)?total score"], 400...1600),
                section(rw), section(math))
    }

    // MARK: AI fallback

    private static var schema: [String: Any] {
        func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        func obj(_ p: [String: Any]) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "required": Array(p.keys).sorted(), "properties": p]
        }
        // Strings everywhere: the on-device model's guided generation only takes strings and enums.
        let item = obj(["section": ["type": "string", "enum": ["Reading and Writing", "Math"]], "module": s("1 or 2"),
                        "number": s("question number"), "correct": s("official correct answer"),
                        "yours": s("the student's answer, empty if omitted")])
        return obj(["total": s("total score 400-1600, empty if absent"), "reading_writing": s("section score 200-800, empty if absent"),
                    "math": s("section score 200-800, empty if absent"), "answers": ["type": "array", "items": item]])
    }

    private static let system = """
    You read text copied from a College Board SAT practice score page. Return only what the text states: the total score, \
    the two section scores, and one entry per question row with its section, module (1 or 2), question number, the official \
    correct answer and the student's answer. Never guess or invent a value; leave a field empty when it is not in the text.
    """

    /// Used when `parse` finds fewer than 20 answers. nil when the model gave back nothing usable.
    @MainActor static func extract(_ text: String) async -> Official? {
        var o = parse(text)
        let chunks = Brain.provider(for: .extract) != .apple ? [text] : chunk(text, 2500)
        var section = "Reading and Writing", module = 1
        var found = false
        for c in chunks {
            let prompt = "Before this text the page was at: \(section), module \(module).\n\n\(c)"
            let reply: String
            do {
                reply = try await Brain.send(task: .extract, system: system, messages: [["role": "user", "content": [["type": "text", "text": prompt]]]],
                                             schema: schema, base: Store.shared.root, effort: "low")
            } catch { continue }
            if let j = (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any] {
                func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
                if o.total == nil, let v = int(j["total"]), (400...1600).contains(v) { o.total = v }
                if o.readingWriting == nil, let v = int(j["reading_writing"]), (200...800).contains(v) { o.readingWriting = v }
                if o.math == nil, let v = int(j["math"]), (200...800).contains(v) { o.math = v }
                for a in j["answers"] as? [[String: Any]] ?? [] {
                    guard let sec = a["section"] as? String, let m = int(a["module"]), (1...2).contains(m),
                          let n = int(a["number"]), (1...(maxQuestion[sec] ?? 0)).contains(n),
                          let c = (a["correct"] as? String)?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { continue }
                    let y = (a["yours"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let key = Session.key(sec, m, n)
                    if o.answers[key] == nil { o.answers[key] = .init(correct: c, yours: y.isEmpty ? nil : y); found = true }
                }
            }
            for l in lines(c) { if let h = sectionHeader(l) { section = h.section ?? section; module = h.module ?? (h.section != nil ? 1 : module) } }
        }
        return found || o.total != nil || !o.answers.isEmpty ? o : nil
    }

    /// Pieces of about `size` characters, cut only at line breaks.
    static func chunk(_ text: String, _ size: Int) -> [String] {
        var out: [String] = [], cur = ""
        for l in lines(text) {
            if cur.count + l.count > size, !cur.isEmpty { out.append(cur); cur = "" }
            cur += l + "\n"
        }
        return cur.isEmpty ? out : out + [cur]
    }

    @MainActor static func apply(_ o: Official, to sid: String) {
        Store.shared.update(sid) { s in
            var o = o   // a score page without scores keeps the score the student typed in
            if o.total == nil, let old = s.official { o.total = old.total; o.readingWriting = old.readingWriting; o.math = old.math }
            s.official = o
        }
        Tutor.reconcile(sid)
    }

    /// Did the student get it right? A comma list in `correct` means any of those is accepted.
    static func isRight(_ a: Official.Answer) -> Bool? {
        if let r = a.right { return r }
        guard let y = a.yours else { return nil }
        return a.correct.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == y.lowercased() }
    }

    // MARK: Self-check

    /// Empty when every check passes.
    static func selfCheck() -> [String] {
        var fails: [String] = []
        func expect(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
        func ans(_ o: Official, _ k: String) -> String { o.answers[k].map { "\($0.correct)/\($0.yours ?? "-")" } ?? "none" }

        // 1. Tab table, headers per module, result words.
        let t1 = """
        Score Details
        Total Score 1350
        Reading and Writing 680
        Math 670
        Reading and Writing
        Module 1
        Question\tCorrect Answer\tYour Answer\tResult
        1\tB\tB\tCorrect
        2\tD\tA\tIncorrect
        3\tC\t\tOmitted
        Module 2
        1\tA\tA\tCorrect
        Math
        Module 1
        1\t12\t12\tCorrect
        2\t1/24, 0.0417\t0.0417\tCorrect
        3\t-3\t3\tIncorrect
        Module 2
        22\tB\tB\tCorrect
        """
        let a = parse(t1)
        let noScore = parse("Score Details\nSAT Practice 8 - November 3, 2026\nAll Questions\n1\tMath\t\t\n410\n410\nCorrect\n")
        expect(noScore.math == nil && noScore.readingWriting == nil, "table answer read as a score \(String(describing: noScore.math))")
        expect(a.total == 1350 && a.readingWriting == 680 && a.math == 670, "t1 scores \(String(describing: a.total)) \(String(describing: a.readingWriting)) \(String(describing: a.math))")
        expect(ans(a, "R1-1") == "B/B" && ans(a, "R1-2") == "D/A" && ans(a, "R1-3") == "C/-", "t1 R1 \(ans(a, "R1-1")) \(ans(a, "R1-2")) \(ans(a, "R1-3"))")
        expect(ans(a, "R2-1") == "A/A" && ans(a, "M1-1") == "12/12", "t1 R2/M1")
        expect(ans(a, "M1-2") == "1/24,0.0417/0.0417" && isRight(a.answers["M1-2"]!) == true, "t1 list \(ans(a, "M1-2"))")
        expect(ans(a, "M1-3") == "-3/3" && ans(a, "M2-22") == "B/B" && a.answers.count == 8, "t1 rest \(a.answers.count)")

        // 2. One cell per line; numeric answers equal to the next question number; no module headers after the first.
        let t2 = """
        Your Score
        1350
        Total Score
        Math
        670
        Module 1
        Question
        Your Answer
        Correct Answer
        1
        5
        5
        2
        B
        C
        3
        2
        Omitted
        4
        9
        4
        """
        let b = parse(t2)
        expect(ans(b, "M1-1") == "5/5", "t2 q1 \(ans(b, "M1-1"))")
        expect(ans(b, "M1-2") == "C/B", "t2 yours-first order \(ans(b, "M1-2"))")
        expect(ans(b, "M1-3") == "2/-" && ans(b, "M1-4") == "4/9", "t2 omit \(ans(b, "M1-3")) \(ans(b, "M1-4"))")
        expect(b.math == 670, "t2 math score \(String(describing: b.math))")

        // 3. Single-space rows, "Q" prefixes, module reset without headers, section switch.
        let t3 = """
        Q26 C C Correct
        Q27 A B Incorrect
        1 D D Correct
        2 B B Correct
        """
        var lines3 = t3.components(separatedBy: "\n")
        lines3.insert(contentsOf: (1...25).map { "Q\($0) A A Correct" }, at: 0)
        let c = parse(lines3.joined(separator: "\n"))
        expect(ans(c, "R1-27") == "A/B" && ans(c, "R1-26") == "C/C", "t3 end of module 1")
        expect(ans(c, "R2-1") == "D/D" && ans(c, "R2-2") == "B/B", "t3 reset to module 2 \(c.answers.keys.sorted().suffix(4))")
        return fails
    }
}

// MARK: - Sheet

/// Paste the page (or take what the extension sent), read it, check the preview, apply.
/// A small drawing of College Board's Score Details page, so the student knows which page to copy. The controls to
/// set are ringed: the All Questions tab, Show Correct Answers and View: All, or with `khan` the Khan Academy button.
struct ScoreDetailsSketch: View {
    var test = "SAT Practice"   // the test being imported, as the page will title it
    var width: CGFloat = 240
    var khan = false
    private let blue = Color(red: 0.2, green: 0.46, blue: 0.77)
    private var k: CGFloat { width / 240 }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4 * k) {
                    Text("Score Details").font(.system(size: 15 * k))
                    Text(test).font(.system(size: 8 * k))
                }
                Spacer(minLength: 4 * k)
                Text("Practice on Khan Academy").font(.system(size: 6.5 * k, weight: .semibold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6 * k).padding(.vertical, 4 * k)
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1)).ring(khan, k)
            }
            .foregroundStyle(.white).padding(.horizontal, 12 * k).padding(.vertical, 10 * k)
            .frame(maxWidth: .infinity, alignment: .leading).background(blue)
            HStack(spacing: 0) {
                ForEach(["All Questions", "Reading and Writing", "Math"], id: \.self) { t in
                    Text(t).font(.system(size: 7.5 * k, weight: t == "All Questions" ? .bold : .regular)).lineLimit(1).fixedSize()
                        .padding(.vertical, 5 * k).padding(.horizontal, 3 * k)
                        .overlay(alignment: .bottom) { if t == "All Questions" { Rectangle().frame(height: 1.5) } }
                        .ring(!khan && t == "All Questions", k)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4 * k)
            HStack(spacing: 4 * k) {
                Capsule().fill(blue).frame(width: 14 * k, height: 8 * k).overlay(alignment: .trailing) { Circle().fill(.white).padding(1.5 * k) }
                Text("Show Correct Answers")
                    .ring(!khan, k, around: -2)
                Spacer(minLength: 0)
                Text("View:")
                Text("All ▾").padding(.horizontal, 4 * k).padding(.vertical, 1.5 * k)
                    .overlay(RoundedRectangle(cornerRadius: 2 * k).strokeBorder(Color.gray.opacity(0.6), lineWidth: 0.75)).ring(!khan, k)
            }
            .font(.system(size: 6.5 * k)).padding(.horizontal, 12 * k).padding(.vertical, 7 * k)
            VStack(spacing: 4 * k) {
                ForEach(1...4, id: \.self) { i in
                    HStack(spacing: 6 * k) {
                        Text("\(i)").frame(width: 8 * k, alignment: .leading)
                        Text("Reading and Writing")
                        Spacer(minLength: 0)
                        Text(i == 3 ? "Incorrect" : "Correct").foregroundStyle(i == 3 ? Palette.wrong : Palette.right)
                    }
                    .font(.system(size: 6.5 * k)).padding(.bottom, 3 * k)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 0.5) }
                }
            }
            .padding(.horizontal, 12 * k).padding(.bottom, 10 * k)
        }
        .foregroundStyle(.black)
        .frame(width: width)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityLabel(khan ? "The Practice on Khan Academy button on Score Details" : "The Score Details page in My Practice")
    }
}

extension View {
    /// The control a page sketch points at.
    func ring(_ on: Bool, _ k: CGFloat, around: CGFloat = -3) -> some View {
        overlay { if on { RoundedRectangle(cornerRadius: 4 * k, style: .continuous).strokeBorder(.orange, lineWidth: 2).padding(around * k) } }
    }
}

struct ImportView: View {
    let sid: String?
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var target = ""
    @State private var reading = false
    @State private var result: Official?
    @State private var failed = false

    init(sid: String?) { self.sid = sid }

    private var chosen: String { sid ?? target }

    var body: some View {
        VStack(alignment: .leading, spacing: L.gap) {
            HStack {
                if result != nil { Text("Official answers").font(T.section) }   // before that, the paste screen's own title is the one
                Spacer()
                if sid == nil {
                    Picker("", selection: $target) {
                        ForEach(store.sessions) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden().frame(maxWidth: 240)
                }
            }
            if let o = result { preview(o) } else { input }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if let o = result {
                    Button("Back") { result = nil }
                    Button("Apply") { Importer.apply(o, to: chosen); dismiss() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(chosen.isEmpty || (o.answers.isEmpty && o.total == nil))
                }
            }
        }
        .padding(L.inset)
        .frame(width: 760, height: result == nil ? nil : 620)
        .onAppear {
            if target.isEmpty { target = store.sessions.first?.id ?? "" }
        }
    }

    /// No text box to fill: one Paste button reads the copied Score Details page straight away.
    private var input: some View {
        VStack(spacing: 14) {
            if failed {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(Palette.wrong).frame(height: 56)
            } else {
                ScoreDetailsSketch(test: store.session(chosen)?.test ?? "SAT Practice")
            }
            Text(failed ? "No answers in what you pasted" : "Paste your Score Details").font(T.title)
            Text("⌘A ⌘C on the page. Turn on Show Correct Answers for the letters.")
                .font(T.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Open My Practice") { NSWorkspace.shared.open(URL(string: "https://mypractice.collegeboard.org/")!) }
                    .controlSize(.large)
                Button { paste() } label: {
                    Group {
                        if reading { ProgressView().controlSize(.small).frame(width: 60) } else { Label("Paste", systemImage: "doc.on.clipboard") }
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 28)
                    .background(Color.accentColor, in: Capsule())   // accent whether or not the sheet is key
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain).keyboardShortcut("v").disabled(reading)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, L.inset)
    }

    private func paste() {
        guard let page = NSPasteboard.general.string(forType: .string), !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { failed = true; return }
        text = page
        read()
    }

    private func preview(_ o: Official) -> some View {
        VStack(alignment: .leading, spacing: L.gap) {
            HStack(spacing: L.gap) {
                score("Total", o.total)
                score("Reading and Writing", o.readingWriting)
                score("Math", o.math)
                Spacer()
                Text("\(o.answers.count) of \(Importer.expected)").font(T.value)
                    .foregroundStyle(o.answers.count == Importer.expected ? Palette.right : .secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: L.gap) {
                    ForEach(["R1", "R2", "M1", "M2"], id: \.self) { p in
                        let keys = o.answers.keys.filter { $0.hasPrefix(p + "-") }
                            .sorted { (Int($0.split(separator: "-")[1]) ?? 0) < (Int($1.split(separator: "-")[1]) ?? 0) }
                        if !keys.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(Session.section(of: p)) · Module \(p.suffix(1))").font(T.card)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                                    ForEach(keys, id: \.self) { cell(o.answers[$0]!, $0) }
                                }
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    private func score(_ name: String, _ v: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v.map(String.init) ?? "–").font(T.big)
            Text(name).font(T.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private func cell(_ a: Official.Answer, _ key: String) -> some View {
        let right = Importer.isRight(a)
        return HStack(spacing: 6) {
            Text(key.split(separator: "-").last.map(String.init) ?? "").font(T.caption).foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
            Text(a.correct.isEmpty ? (right == true ? "Right" : right == false ? "Wrong" : "–") : a.correct).font(T.body.weight(.semibold)).lineLimit(1)
            if right != true { Text(a.yours ?? "–").font(T.body).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 0)
            Image(systemName: right == true ? "checkmark.circle.fill" : right == false ? "xmark.circle.fill" : "minus.circle")
                .foregroundStyle(right == true ? Palette.right : right == false ? Palette.wrong : Palette.unknown)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    private func read() {
        let page = text
        reading = true
        failed = false
        Task {
            var o = Importer.parse(page)
            if o.answers.count < 20, let ai = await Importer.extract(page) { o = ai }
            reading = false
            if o.answers.isEmpty && o.total == nil { failed = true } else { result = o }
        }
    }
}
