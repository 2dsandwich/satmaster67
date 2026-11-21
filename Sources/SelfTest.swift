import AppKit
import FoundationModels
import SwiftUI
import WebKit

enum GenerationSchemaCheck {
    static func make(_ s: [String: Any]) throws -> Bool { _ = try GenerationSchema(root: Apple.dynamic(s, name: "Reply"), dependencies: []); return true }
}

/// `--selftest` checks the logic, `--snapshot <dir>` renders the UI off screen,
/// `--live` sends one rendered question to Claude. Set SAT_DATA to keep tests out of real data.
@MainActor enum SelfTest {
    static func handled(_ args: [String]) -> Bool {
        if args.contains("--selftest") { run(); return true }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { snapshot(URL(fileURLWithPath: args[i + 1])); return true }
        if let i = args.firstIndex(of: "--snapshot-plan"), i + 1 < args.count { planStates(URL(fileURLWithPath: args[i + 1])); return true }
        if let i = args.firstIndex(of: "--parse"), i + 1 < args.count,   // read a pasted score page from a file and summarize it
           let page = try? String(contentsOfFile: args[i + 1], encoding: .utf8) {
            let o = Importer.parse(page)
            let keys = o.answers.keys.sorted()
            print("answers \(o.answers.count), right \(o.answers.values.filter { Importer.isRight($0) == true }.count), wrong \(o.answers.values.filter { Importer.isRight($0) == false }.count)")
            for p in ["R1", "R2", "M1", "M2"] { print(p, keys.filter { $0.hasPrefix(p + "-") }.count) }
            print("R2-3:", o.answers["R2-3"].map { "\($0)" } ?? "-")
            return true
        }
        if let i = args.firstIndex(of: "--layout") {   // print the layout of screenshot files
            for f in args[(i + 1)...] {
                guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: f) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
                let t = Date(), l = Capture.layout(img)
                print((f as NSString).lastPathComponent, "covered:", l.covered, "pane:", l.pane.map { String(format: "%.2f %.2f %.2f %.2f", $0.minX, $0.minY, $0.width, $0.height) } ?? "-", String(format: "%.0f ms", Date().timeIntervalSince(t) * 1000))
            }
            return true
        }
        if args.contains("--track-test") {
            Task { await trackTest(); exit(0) }
            RunLoop.main.run()
        }
        if let i = args.firstIndex(of: "--redo"), i + 1 < args.count {   // re-explain one saved test, headless
            let one = i + 2 < args.count ? args[i + 2] : nil   // optional question key, e.g. M2-7
            Task {
                if one == "Math" || one == "Reading and Writing" {   // re-explain one section only
                    if let full = Store.shared.session(args[i + 1]) { await Tutor.explain(args[i + 1], full.keys.filter { Session.section(of: $0) == one && full.explainable($0) }) }
                } else if one == "debrief" { for sec in Store.shared.session(args[i + 1])?.sections ?? [] { await Tutor.debrief(args[i + 1], sec) } }
                else if let k = one { await Tutor.analyze(args[i + 1], k) } else { await Tutor.redo(args[i + 1]) }
                print("redone with \(Brain.name)"); exit(0)
            }
            RunLoop.main.run()
        }
        if let i = args.firstIndex(of: "--desmos-check"), i + 1 < args.count { desmosCheck(URL(fileURLWithPath: args[i + 1])) }
        if args.contains("--live") {
            Task { await live(); exit(0) }
            RunLoop.main.run()
        }
        return false
    }

    static func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok   \(what)" : "FAIL \(what)")
        if !ok { exit(1) }
    }

    /// A Bluebook-like page: header, a question with one choice highlighted, bottom bar.
    static func sampleQuestion(number: Int = 4, chosen: Int = 1) -> CGImage {
        let size = NSSize(width: 1568, height: 980)
        let img = NSImage(size: size, flipped: true) { r in
            NSColor.white.setFill(); r.fill()
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ pt: CGFloat, bold: Bool = false) {
                (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: pt) : NSFont.systemFont(ofSize: pt), .foregroundColor: NSColor.black])
            }
            text("Section 1, Module 1: Math", 40, 30, 22, bold: true)
            text("31:05", 740, 30, 22, bold: true)
            text("If 3x + 7 = 22, what is the value of 6x − 4 ?", 820, 200, 24)
            for (i, c) in ["A  26", "B  30", "C  32", "D  36"].enumerated() {
                let box = NSRect(x: 820, y: 280 + CGFloat(i) * 90, width: 600, height: 64)
                (i == chosen ? NSColor.systemBlue.withAlphaComponent(0.25) : NSColor(white: 0.95, alpha: 1)).setFill()
                NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
                text(c, 850, box.minY + 18, 22)
            }
            NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 900, width: 1568, height: 80).fill()
            text("Question \(number) of 22", 690, 925, 22, bold: true)
            text("Next", 1440, 925, 22, bold: true)
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    static func run() {
        // Parsing
        var d = Detected.parse("Section 2, Module 1: Math\n34:59\nQuestion 7 of 22\nBack Next")
        check(d.number == 7 && d.of == 22 && d.module == 1 && d.section == "Math" && d.timer == "34:59", "parse Bluebook math screen")
        d = Detected.parse("Section 1, Module 2: Reading and Writing\nQuestion 27 of 27")
        check(d.number == 27 && d.module == 2 && d.section == "Reading and Writing", "parse Reading and Writing screen")
        d = Detected.parse("Check Your Work\nOn test day, you won't be able to move on to the next module until time expires.")
        check(d.number == nil && d.reviewPage, "review page is not a question")
        do {   // My Practice Score Details, copied as text (real layout, Nov 2026): numbering restarts per module
            var page = "Questions Overview\nQuestion\nSection\tCorrect Answer\t\nYour Answer\nActions\t\nDomain\n"
            for (sec, n) in [("Reading and Writing", 27), ("Reading and Writing", 27), ("Math", 22), ("Math", 22)] {
                for q in 1...n { page += "\(q)\t\(sec)\t\t\n\(q == 3 ? "Incorrect" : "Correct")\n\n\(sec == "Math" ? "Algebra" : "Craft and Structure")\n" }
            }
            let o = Importer.parse(page)
            check(o.answers.count == 98 && o.answers["R2-3"]?.right == false && o.answers["M2-22"]?.right == true
                  && o.answers["M1-5"]?.domain == "Algebra" && Importer.isRight(o.answers["R1-3"]!) == false, "score details page: results without letters")
            var s = Session(id: "t", start: Date()); s.official = o
            check(s.correct("R2-3") == false && s.correct("R2-4") == true && s.grade("R2-4") == .official, "official result grades without letters")
            let letters = Importer.parse(page.replacingOccurrences(of: "1\tMath\t\t\n", with: "1\tMath\tB\tB\t\n"))
            check(letters.answers["M1-1"]?.correct == "B", "score details page: letters when shown")
            let shown = Importer.parse(page.replacingOccurrences(of: "3\tMath\t\t\nIncorrect", with: "3\tMath\tC\t\nA Incorrect")
                .replacingOccurrences(of: "4\tMath\t\t\nCorrect", with: "4\tMath\t1/24, .0417\t\n.0417 Correct"))
            check(shown.answers.count == 98 && shown.answers["M2-3"].map { $0.correct == "C" && $0.yours == "A" && $0.right == false } == true
                  && shown.answers["M1-4"].map { $0.correct == "1/24, .0417" && $0.yours == ".0417" } == true, "score details page: your answer read from its row")
        }
        check(Rich.tidy("x^2 <= 3, y^-1 >= 0") == "x² ≤ 3, y⁻¹ ≥ 0", "plain math tidied")
        check(ScoreSheet.section("720").value == 720 && ScoreSheet.section("725").problem != nil && ScoreSheet.section("900").problem != nil
              && ScoreSheet.section("abc").problem != nil && ScoreSheet.section("").value == nil, "SAT section scores checked")
        check(QuestionView.steps("1. Find the claim. 2. Look for the line. 3. Only A does this.").count == 3 && QuestionView.steps("1. Find \"worked.\" 2. Then this.").count == 2 && QuestionView.steps("1. Costs 3. Then stop.").count == 1, "run-together steps split")
        check(LogTestSheet.heading("Score Details\nSAT Practice 10 - November 5, 2026\nMy Tests")?.test == "SAT Practice 10"
              && LogTestSheet.heading("SAT Practice 10 - November 5, 2026")?.date.map { Calendar.current.component(.day, from: $0) } == 5, "logged test name and date read from the page")
        do {   // a logged test: questions, sections and modules come from the official record
            var s = Session(id: "log", start: Date()); var o = Official()
            o.answers = ["R1-1": .init(correct: "", yours: nil, right: true), "R2-3": .init(correct: "", yours: nil, right: false), "M1-2": .init(correct: "", yours: nil, right: true)]
            s.official = o
            check(s.logged && s.keys.count == 3 && s.sections == ["Reading and Writing", "Math"] && s.only("Math").keys == ["M1-2"] && s.modules == [1, 2]
                  && s.correct("R2-3") == false, "logged test has questions without visits")
        }
        do {   // Log a test, step by step: Khan Academy's module pages into College Board's record
            let r = Khan.parse(khanReading, max: 27), m = Khan.parse(khanMath, max: 22)
            check(r.count == 3 && r[1]?.choices == ["overlook", "celebrate", "duplicate", "predict"] && r[1]?.skill == "Words in context"
                  && r[1]?.question?.hasPrefix("Which choice completes") == true && r[1]?.passage?.hasPrefix("Marine biologist") == true, "Khan page: repeated choice letters read once")
            check(r[2]?.choices?.count == 4 && r[2]?.choices?[3] == "All three parks had more species in 2020." && r[2]?.passage?.contains("Riverside\t42\t51") == true,
                  "Khan page: letters on their own lines, table kept in the passage")
            check(r[3]?.choices == ["license,", "license;", "license", "license, and"], "Khan page: letter and choice on one line")
            check(m.count == 3 && m[1]?.choices?.first == "(−14,0)" && m[1]?.passage == "y = 2x + 6\ny = −x" && m[1]?.skill == "Systems of two linear equations in two variables"
                  && m[2]?.choices == nil && m[2]?.question == "If 3x + 7 = 22, what is the value of 6x − 4 ?" && m[2]?.passage == nil
                  && m[3]?.choices?[1] == "$(1, 3)$", "Khan page: Math choices, a grid-in, LaTeX kept")
            let fields = (Array(r.values) + Array(m.values)).flatMap { [$0.passage, $0.question, $0.skill] + ($0.choices ?? []).map { Optional($0) } }.compactMap { $0 }
            check(!fields.contains { f in ["Check", "Explain", "Hint", "Report a problem", "Show calculator", "About", "Up next", "Donate"].contains { f.contains($0) } }, "Khan page words left out")
            check(Khan.parse(khanMath, max: 2).count == 2 && Khan.parse("Search\nDonate\nLog in").isEmpty, "question numbers past the module and pages without questions")
            let tex = Khan.parse(#"""
            Question 1 | Nonlinear functions
            If \(f(x)=x^2\), what is \[\sqrt{f(3)}\]?
            Choose 1 answer:
            A \(3\)
            B \(9\)
            C \(\sqrt{3}\)
            D \(\frac{x^2}{2}\)
            Check
            Question 2 | Linear equations in one variable
            What is the value of \(x\) if \(2x = 8\)?
            Check
            Up next: article
            """#, max: 22)
            check(tex[1]?.question == "If $f(x)=x^2$, what is $\\sqrt{f(3)}$?" && tex[1]?.choices == ["$3$", "$9$", "$\\sqrt{3}$", "$\\frac{x^2}{2}$"]
                  && tex[2]?.question == "What is the value of $x$ if $2x = 8$?" && tex[2]?.choices == nil, "Khan page: MathJax LaTeX kept, a grid-in without format help")
            let like = Khan.parse("Question 1 | Inferences\nA researcher found that animals, like bees, carry pollen.\nWhich choice is supported?\nChoose 1 answer:\nA one\nB two\nC three\nD four")
            check(like[1]?.passage?.contains("like bees") == true && like[1]?.question == "Which choice is supported?" && like[1]?.choices?.count == 4,
                  "Khan page: a passage's \", like\" is not a grid-in's format help")
            var f: [String: Official.Answer] = [:]
            for (n, a) in r { f["R1-\(n)"] = a }
            for (n, a) in m { f["M1-\(n)"] = a }
            f["M2-30"] = m[1]   // not on the Score Details page: dropped, or it would count as wrong
            let res = LogTestSheet.results(khanResults)!
            let o = Khan.merge(f, into: res.o)
            check(res.test == "SAT Practice 4" && o.answers.count == 98 && o.answers["R1-1"]?.choices?.count == 4 && o.answers["R1-2"]?.right == false
                  && o.answers["R1-2"]?.question != nil && o.answers["M1-2"]?.correct == "26" && o.answers["M1-1"]?.skill == m[1]?.skill && o.answers["M2-30"] == nil,
                  "Khan questions merged into the official record by key")
            var s = Session(id: "khan", start: Date()); s.official = o
            check(s.logged && s.correct("R1-2") == false && s.correct("R1-1") == true && s.explainable("R1-1") && !s.explainable("R2-1"), "text-only explanation allowed with the official question")
            let ctx = Tutor.context(s.only(Sec.math), "M1-1")
            check(ctx.contains("Official question text:\ny = 2x + 6\ny = −x") && ctx.contains("At which point") && ctx.contains("B. (−2,2)") && ctx.contains("correct answer B"),
                  "official passage, question and choices in the tutor's context")
            check((try? JSONDecoder().decode(Official.Answer.self, from: Data(#"{"correct":"B","yours":"A"}"#.utf8))).map { $0.choices == nil && $0.passage == nil } == true,
                  "official answers saved before still load")
            check((try? GenerationSchemaCheck.make(Khan.schema)) == true, "Khan reading schema works on device")
        }
        do {   // Khan's text for a graph or table: drawn as the figure, the axis tick echo dropped, the rest kept as the passage
            let (bar, src, text) = Figure.split(khanBar)
            check(bar?.kind == .bar && bar?.title == "Metal Content of Plants with and without Kanamycin Exposure" && bar?.x == "Experimental condition"
                  && bar?.y == "Metal content, in parts per million" && bar?.yScale == [0, 700, 100] && bar?.series == ["Zinc", "Iron"] && bar?.data.count == 4
                  && bar?.data.last == .init(group: "With kanamycin", name: "Iron", value: 225) && text.hasPrefix("Many plants lose") && !text.contains("\\[")
                  && src.hasPrefix("Bar graph titled") && src.contains("\\[700\\]"), "Khan bar graph read into a grouped chart")
            let q = Khan.parse("Question 12 | Command of evidence: quantitative\n\(khanBar)\nWhich choice best describes data from the graph?\nChoose 1 answer:\nA a\nB b\nC c\nD d")[12]
            check(q?.passage?.hasPrefix("Bar graph titled") == true && q?.passage?.contains("$700$") == false && q?.passage?.contains("* Iron: 225") == true
                  && q?.question == "Which choice best describes data from the graph?", "Khan reader drops tick lines, keeps the description for the tutor")
            let (table, _, ttext) = Figure.split(khanTable)
            check(table?.kind == .table && table?.title == "Bird Species Counted in Three City Parks" && table?.rows.count == 4 && table?.rows[2] == ["Hilltop", "37", "35"]
                  && ttext.hasPrefix("A researcher claims"), "Khan table titled …, tab-separated rows")
            check(Figure.split(khanReading.components(separatedBy: "Question 2 | ")[1]).figure?.rows.first == ["Park", "2015", "2020"], "a table copied without a title")
            let (line, _, ltext) = Figure.split(khanLine)
            check(line?.kind == .line && line?.series == ["City A", "City B"] && line?.yScale == [0, 30, 5] && line?.data.count == 8
                  && line?.data[5] == .init(group: "City B", name: "2", value: 12) && ltext.hasPrefix("A student compared"), "Khan line graph: a line per city")
            let page = Khan.parse(khanOdd, max: 27), graph = Khan.parse(khanGraph, max: 22)
            check(page.count == 5 && page[5]?.passage?.hasPrefix("A growing number, like") == true && page[5]?.choices?.count == 4
                  && page[6]?.skill == "Transitions" && page[6]?.passage?.contains("\n1850\n") == true && page[6]?.choices?.count == 4
                  && page[7]?.question == "Which choice best states the main idea of the text?" && page[7]?.choices?.count == 4
                  && page[8]?.skill == "Boundaries" && page[8]?.choices?.count == 4 && page[9]?.passage?.hasPrefix("An okapi, like") == true,
                  "Khan page: odd passage lines, header and answer-line variants skip no question")
            check(graph[1]?.question == "Which of the following could be the equation of the graph?" && graph[1]?.passage?.contains("\n−10\nO") == true
                  && Figure.pictured(graph[1]?.passage) && Figure.split(graph[1]!.passage!).text == "The graph of $y=f(x)$ is shown."
                  && !Figure.pictured(khanBar) && !Figure.pictured(page[6]?.passage), "a graph's picture labels: kept for the tutor, hidden, marked as a figure")
            check(Khan.one("Question 30 | Transitions\nShe left.\nWhich choice?\nChoose 1 answer:\nA a\nB b\nC c\nD d")?.choices?.count == 4
                  && Khan.one("She left early.\nWhich choice completes the text?\nChoose 1 answer:\nA a\nB b\nC c\nD d")?.question == "Which choice completes the text?"
                  && Khan.one("Search\nDonate") == nil, "one question pasted on its own, with or without its header")
            let odd = "Dot plot titled Siblings. The horizontal axis is labeled Number.\n\\[0\\]\n\\[1\\]\n\\[2\\]\nA survey asked students."
            check(Figure.split(odd).figure == nil && Figure.split(odd).text == "Dot plot titled Siblings. The horizontal axis is labeled Number.\nA survey asked students."
                  && Figure.clean("$f(x)=2$\n$3$") == "$f(x)=2$\n$3$", "unknown figures stay text without tick lines; a lone number is kept")
        }
        do {   // Khan copies each inline math token on its own line: flowed back into sentences, at reading and for text saved before
            let wire = "A wire with a length of\n$106$\ninches is cut into two parts. One part has a length of\n$x$\ninches, and the other part has a length of\n$y$\ninches. The value of\n$x$\nis\n$6$\nmore than\n$4$\ntimes the value of\n$y$\n. What is the value of\n\n$x$\n?"
            let flowed = "A wire with a length of $106$ inches is cut into two parts. One part has a length of $x$ inches, and the other part has a length of $y$ inches. The value of $x$ is $6$ more than $4$ times the value of $y$. What is the value of $x$?"
            let saved = Khan.tidy(.init(correct: "", question: wire)), parts = wire.components(separatedBy: "\n")
            let split = Khan.tidy(.init(correct: "", question: "?", passage: parts.dropLast().joined(separator: "\n")))   // as the reader stored it before
            let tex = Khan.tidy(.init(correct: "", question: wire.replacing(#/\$([^$\n]+)\$/#) { "\\(\($0.1)\\)" }))
            let pasted = Khan.parse("Question 4 | Linear equations in two variables\n" + wire.replacing(#/\$([^$\n]+)\$/#) { "\\(\($0.1)\\)" } + "\nCheck", max: 22)[4]
            check(saved.question == flowed && saved.passage == nil && split.question == flowed && split.passage == nil
                  && tex.question == flowed.replacing(#/\$([^$]+)\$/#) { "\\(\($0.1)\\)" } && pasted?.question == flowed && pasted?.passage == nil,
                  "Khan's math on its own lines flows into one sentence: \(saved.question ?? "")")
            let rw = Official.Answer(correct: "", question: "Which choice completes the text?", passage: "The poem begins\nand the night goes on\nAnother line.")
            let sys = Official.Answer(correct: "", question: "What is the solution?", passage: "A system of equations is shown.\n$y=2x$\n$y=x+1$")
            let disp = Official.Answer(correct: "", question: "The function \\(f\\) is defined by the given equation. What is \\(f(-4)\\)?", passage: "\\[f(x)=x^2+3\\]")
            let plain = Khan.parse(khanMath, max: 22)[1]!
            check(Khan.tidy(rw) == rw && Khan.tidy(sys) == sys && Khan.tidy(disp) == disp && Khan.tidy(plain) == plain && Khan.tidy(.init(correct: "", choices: ["$25$"])).choices == ["$25$"],
                  "text without inline math, display equations and a plain system stay as they are")
            let stem = "A scatterplot is graphed in the first quadrant of the xy plane. The points form a tight diagonal cluster that trends downward from approximately (0, 10) to (5, 0)."
            let labels = ((1...10).map { "\\(\($0)\\)" } + (1...8).map { "$\($0)$" }).joined(separator: "\n")
            let scatter = Khan.tidy(.init(correct: "", question: stem + "\n" + labels, skill: "Scatterplots")), f = Figure.split(stem)
            check(scatter.question == stem && Figure.split(scatter.passage ?? "").text.isEmpty && Khan.pictured(.init(correct: "", question: stem + "\n" + labels))
                  && f.figure == nil && f.text == stem && !Khan.pictured(.init(correct: "", question: flowed)),
                  "a scatterplot's tick labels hidden, no chart made up from its description, a picture asked for")
        }
        check(Rich.text("So \"$f(x)=0$\" means \"$y=0$,\" where it meets the axis.") != Rich.text("So \"$f(x)=0$\" means"), "quoted math is set as math")
        check(DesmosView.point("(14,0)")! == (14, 0) && DesmosView.point("( -2.5 , 3 )")! == (-2.5, 3) && DesmosView.point("") == nil, "Desmos answer point read")
        check(Vocab(en: "Barring", ja: "", note: "").term == "barring" && Vocab(en: "NASA", ja: "", note: "").term == "NASA" && Vocab(en: "opaque", ja: "", note: "").term == "opaque", "word list in one case")
        check(Tutor.clean("Test hard answers with numbers.e.g.,") == "Test hard answers with numbers." && Tutor.clean("Predict\u{1f} first.") == "Predict first.", "model text cleaned")
        check(Tutor.clean("Predict the word first.", title: true) == "Predict the word first" && Tutor.clean("Plug it back in", sentence: true) == "Plug it back in." && Tutor.clean("Why?", sentence: true) == "Why?", "titles lose periods, sentences get them")
        let vocabReply = #"{"vocab":[{"term":"","meaning":"x"},{"term":"x","meaning":"y"},{"term":"opaque","meaning":"hard to see through"}]}"#
        check(((try? JSONSerialization.jsonObject(with: Tutor.stored(vocabReply))) as? [String: Any])?["vocab"].map { ($0 as? [Any])?.count } == 1, "blank and one-letter words dropped")
        let runs = Rich.mathRuns("In a(b)^x, a is the starting value when x = 0. Use 24/n and/or 3x (A) in 1950s.")
        check(runs.filter(\.1).map(\.0) == ["a(b)^x", "x = 0", "24/n", "3x"], "equations found in plain text (\(runs.filter(\.1).map(\.0)))")
        // Khan Academy's MathJax: \( \) inline, \[ \] and $$ $$ on their own line, \left( \right) and \text{} inside.
        check(Rich.dollars(#"If \(3x+7=22\), find \(\$6x\)."#) == "If $3x+7=22$, find $\u{E000}6x$."
              && Rich.dollars(#"Solve \[\sqrt{(x-2)^2}=\sqrt{3x+34}\] for x"#) == "Solve\n$\\sqrt{(x-2)^2}=\\sqrt{3x+34}$\nfor x"
              && Rich.dollars("$$x^2$$") == "$x^2$" && Rich.dollars("costs $5 and $6") == "costs $5 and $6", "Khan math delimiters read")
        check(MathParse.row(#"\left(\frac{1}{2}\right)^{x}\le 4\cdot\pi"#) == [.text("(", italic: false), .frac([.text("1", italic: false)], [.text("2", italic: false)]),
              .script(.text(")", italic: false), sup: [.text("x", italic: true)], sub: nil), .op("≤"), .text("4", italic: false), .op("·"), .text("π", italic: false)]
              && MathParse.row(#"\sin A"#) == [.text("sin\u{2009}", italic: false), .text("A", italic: true)]
              && MathParse.row("x^2") == [.script(.text("x", italic: true), sup: [.text("2", italic: false)], sub: nil)]
              && MathParse.row(#"64\text{ cubic inches}"#).last == .text(" cubic inches", italic: false)
              && MathParse.row(#"\dfrac{a}{b}\ne\$3"#) == MathParse.row(#"\frac{a}{b}≠$3"#), "LaTeX commands set as math (\(MathParse.row(#"\left(x\right)"#)))")
        check(Rich.text("**a** $x^2$") == Rich.text("**a** $x^2$") && Rich.text("a", color: .primary) != Rich.text("a"), "kept rich text is per string and style")
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).tiff")
        try? NSImage(size: NSSize(width: 2, height: 2), flipped: false) { _ in true }.tiffRepresentation?.write(to: png)
        check(ZoomedShot.image(png) != nil && ZoomedShot.image(png) === ZoomedShot.image(png)
              && ZoomedShot.image(png.appendingPathExtension("missing")) == nil, "screenshots decoded once per file")
        try? FileManager.default.removeItem(at: png)
        check(Detected.parse("This Module Is Over\nAll your work has been saved.\nDo not refresh this page or quit the app.").reviewPage, "module-over screen is not a question")
        check(Detected.parse("Algebra worksheet page 3").number == nil, "unrelated page has no question")
        // Real misreads from a live Bluebook session, and Desmos covering the header.
        d = Detected.parse("Section I, Module I: Reading and Writing\nAlex Morgan Que5tion 3 of 27")
        check(d.number == 3 && d.module == 1 && d.section == "Reading and Writing", "OCR misreads (I for 1, 5 for s)")
        d = Detected.parse("Question 11 0127 N&xt")
        check(d.number == 11 && d.of == 27 && d.section == "Reading and Writing", "\"of\" read as 01")
        d = Detected.parse("Graphing Scientific\n33:05\nHide\nCalculator Reference More\nQuestion 5 of 22")
        check(d.number == 5 && d.section == "Math" && d.module == nil && d.timer == "33:05", "Desmos over the header: Math from the total")
        check(Tracker.seconds("33:05") == 1985 && Tracker.seconds("Hide") == nil, "countdown to seconds")
        let f0 = Date()   // last frame checked at f0; input 5 s before it unless noted
        check(Tracker.unchanged(last: f0, input: f0 - 5, frame: f0 + 19, refresh: 20)
              && !Tracker.unchanged(last: f0, input: f0 - 0.5, frame: f0 + 4, refresh: 20)   // screen hadn't settled
              && !Tracker.unchanged(last: f0, input: f0 + 2, frame: f0 + 4, refresh: 20)     // input since
              && !Tracker.unchanged(last: f0, input: f0 - 5, frame: f0 + 21, refresh: 20)    // refresh due
              && !Tracker.unchanged(last: nil, input: f0 - 5, frame: f0, refresh: 20), "unchanged frame skips re-reading")
        if let dir = ProcessInfo.processInfo.environment["SAT_SHOTS"] {   // real screenshots: print what the strips read
            for f in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".jpg") {
                guard let img = NSImage(contentsOfFile: dir + "/" + f)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let d = Detected.parse(Capture.bluebook(img))
                print(f, d.section ?? "-", d.module.map(String.init) ?? "-", d.number.map(String.init) ?? "MISS", d.timer ?? "-")
            }
        }
        check(Detected.parse("SAT Practice 6").practiceTest == 6 && Detected.parse("Practice Test 11").practiceTest == 11, "test name read from screen")

        // Glossary
        check(Glossary.all.count > 140, "glossary has \(Glossary.all.count) words")
        check(Glossary.search("slope").first?.ja == "傾き" && Glossary.search("傾き").first?.en == "slope", "lookup works both ways")
        check(Glossary.search("median").first?.en == "median", "prefix match first")

        // Real on-device OCR on a rendered page
        _ = Capture.text(sampleQuestion(number: 1))   // first call loads the model
        let t0 = Date()
        let ocr = Detected.parse(Capture.text(sampleQuestion(number: 13)))
        check(ocr.number == 13 && ocr.of == 22 && ocr.module == 1 && ocr.section == "Math", "OCR reads rendered page (\(Int(Date().timeIntervalSince(t0) * 1000)) ms warm)")
        let box = Capture.find("the value of 6x - 4", in: sampleQuestion())
        check(box.map { $0[0] > 0.5 && $0[1] > 0.15 && $0[1] < 0.3 && $0[2] < 0.5 } ?? false, "key phrase found on the page \(box ?? [])")

        // Time math, revisits, verdicts
        let b = Date(timeIntervalSince1970: 1_000_000)
        var s = Session(id: "selftest", start: b)
        s.visits = [Visit(module: 1, number: 1, start: b, end: b + 60),
                    Visit(module: 1, number: 2, start: b + 60, end: b + 300),
                    Visit(module: 1, number: 1, start: b + 300, end: b + 330),
                    Visit(module: 2, number: 1, start: b + 330, end: b + 340)]
        check(s.seconds("M1-1") == 90 && s.visitCount("M1-1") == 2, "revisit time adds up")
        check(s.keys == ["M1-1", "M1-2", "M2-1"], "questions sort by module then number")
        var both = s; both.visits.append(Visit(section: "Reading and Writing", module: 1, number: 3, start: b, end: b + 20))
        check(both.keys.first == "R1-3" && both.sections == ["Reading and Writing", "Math"] && both.only("Math").keys.count == 3, "a full test splits into sections")
        check(s.label("M2-1") == "M2 Q1", "labels show module when there are two")
        s.q["M1-1"] = QState(mark: false)
        var a = QState(); a.analysis = Analysis(questionEn: "", questionJa: "", topic: "Algebra", skill: "", difficulty: "Easy", correctAnswer: "A",
                                               studentAnswer: "A", verdict: "correct", solutionJa: "", wordingJa: "", trapJa: "", timeJa: "", vocab: [])
        s.q["M1-2"] = a
        check(s.correct("M1-1") == false && s.correct("M1-2") == true && s.correct("M2-1") == nil, "own mark wins, AI verdict next")

        // Official answers: equivalent forms match; your mark still wins; grade source is reported.
        check(Session.same("1/2", ".5") && Session.same("b", "B") && Session.same("3.5", "7/2") && Session.same("4", "2, 4")
              && !Session.same(nil, "A") && !Session.same("A", "B") && !Session.same("1/0", "0"), "answer matching")
        var o = Official(); o.answers["M2-1"] = .init(correct: "C", yours: "C"); o.answers["M1-1"] = .init(correct: "A", yours: "A")
        s.official = o
        check(s.correct("M2-1") == true && s.grade("M2-1") == .official && s.correct("M1-1") == false && s.grade("M1-1") == .mine, "official grades, your mark wins")
        s.official = nil

        // A logged test (no visits): Stats counts the official grades and has no time or pace to divide by.
        var lg = Session(id: "logged", start: Date()); lg.official = o
        let lst = Stats(lg.sections.map { lg.only($0) })
        check(lg.logged && lst.marked == 2 && lst.right == 2 && lst.time == 0 && lst.over.isEmpty && lst.topics.isEmpty, "logged test stats without visits")

        // Timeline filter: M1-1 marked wrong (90 s), M1-2 right, Easy Algebra, 240 s over pace, M2-1 not graded.
        func hits(_ f: QFilter) -> [String] { s.keys.filter { f.match(s, $0) } }
        var qf = QFilter(); qf.result = "Not graded"
        var flag = QFilter(); flag.flagged = true
        var mix = QFilter(); mix.overPace = true; mix.difficulty = "Easy"; mix.topics = ["Algebra"]; mix.module = 1; mix.section = "Math"
        var rw = QFilter(); rw.section = "Reading and Writing"
        check(hits(QFilter()) == s.keys && hits(QFilter(result: "Wrong")) == ["M1-1"] && hits(QFilter(result: "Right")) == ["M1-2"] && hits(qf) == ["M2-1"]
              && hits(QFilter(module: 2)) == ["M2-1"] && hits(mix) == ["M1-2"] && hits(flag).isEmpty && hits(rw).isEmpty && rw.scoped("Math") == QFilter()
              && !QFilter().isOn && qf.isOn, "timeline filter")
        check(["M1-1", "R2-3"].allSatisfy { k in s.pace(k) == s.only(Session.section(of: k)).pace }, "pace by key matches the section's pace")

        do {   // Reasons, handoffs and chat links over one finished test: Math misses M1-1..3, R&W miss R1-1, M1-4 right
            var w = Session(id: "why", start: b); w.end = b + 600
            w.visits = ["M1-1", "M1-2", "M1-3", "M1-4", "R1-1"].map { k in let (o, m, n) = Session.parts(k); return Visit(section: o == 0 ? "Reading and Writing" : "Math", module: m, number: n, start: b, end: b + 60) }
            func q(_ ok: Bool, _ r: [String]) -> QState { var x = QState(mark: ok); x.causes = r; return x }
            w.q = ["M1-1": q(false, ["misread", "time"]), "M1-2": q(false, ["misread"]), "M1-3": q(false, ["concept"]), "R1-1": q(false, ["concept"]), "M1-4": q(true, ["guess"])]
            var o = Official(); o.answers = ["M1-2": .init(correct: "A", yours: "B", domain: "Algebra"), "M1-4": .init(correct: "A", yours: "A", domain: "Advanced Math")]
            w.official = o
            let why = Student.reasons([w]).map { "\($0.id)\($0.section.map { "|" + $0 } ?? "") \($0.count)" }
            check(why == ["misread 2", "concept|Math 1", "concept|Reading and Writing 1", "time 1"], "reasons counted on misses, most common first (\(why))")
            check(Student.brief().contains("Why they miss") == !Student.reasons(Store.shared.sessions).isEmpty, "brief carries the reasons")
            check(Opening.review([w]) == Opening(sid: "why", scope: "Math", filter: QFilter(result: "Wrong")), "review opens the section with most misses, wrong only")
            check(Opening.topic("Algebra", [w]) == Opening(sid: "why", scope: "Math", filter: QFilter(result: "Wrong", topics: ["Algebra"]))
                  && Opening.topic("Advanced Math", [w])?.filter == QFilter(topics: ["Advanced Math"]) && Opening.topic("Geometry and Trigonometry", [w]) == nil, "topic drill opens that topic's misses")
            check(QFilter(result: "Wrong").order(w, "Math") == ["M1-1", "M1-2", "M1-3"] && QFilter(result: "Wrong").order(w, "Overview") == ["R1-1", "M1-1", "M1-2", "M1-3"]
                  && QFilter().order(w, "Math") == nil, "question view steps through the shared filter")
            var newer = w; newer.id = "why2"; newer.start = b + 999
            check(Opening.question("M1 Q2", [newer, w])?.sid == "why2" && Opening.question("M1 Q2", [newer, w], in: "why") == Opening(sid: "why", key: "M1-2")
                  && Opening.question("M2 Q9", [w]) == nil && QLink.label(URL(string: "satq:RW1-Q3")!) == "RW1 Q3" && QLink.label(URL(string: "https://x.org")!) == nil, "chat question links resolve")
            let lp = QLink.parts("See **RW1 Q3 and M2 Q7** now, Q5. FAQ1").map { "\($0.label ? "[" : "")\($0.text)\($0.bold ? "*" : "")" }
            check(lp == ["See ", "[RW1 Q3*", "** and **", "[M2 Q7*", " now, ", "[Q5", ". FAQ1"], "chat labels cut out as links, bold kept (\(lp))")
            var lg = Session(id: "logged-topics", start: b); var lo = Official()
            lo.answers = ["M1-1": .init(correct: "A", yours: "B", domain: "Algebra"), "M1-2": .init(correct: "A", yours: "A", domain: "Algebra")]
            lg.official = lo; lg.end = b
            check(Stats(lg.only("Math")).topics.map(\.name) == ["Algebra"] && Opening.topic("Algebra", [lg])?.sid == lg.id && QFilter(topics: ["Algebra"]).order(lg, "Math") == ["M1-1", "M1-2"],
                  "a logged test's topics come from College Board's record")
        }

        do {   // equal accuracy sorts by name, so topics and drills don't change between launches
            var page = "Questions Overview\nQuestion\nSection\tCorrect Answer\t\nYour Answer\nActions\t\nDomain\n"
            for q in 1...20 {   // the parser wants 20+ rows; both domains end up 8 of 10
                page += "\(q)\tReading and Writing\t\t\n\(q <= 4 ? "Incorrect" : "Correct")\n\n\(q % 2 == 0 ? "Craft and Structure" : "Information and Ideas")\n"
            }
            var s = Session(id: "tie", start: Date()); s.official = Importer.parse(page)
            let names = ["Craft and Structure", "Information and Ideas"]
            check(Score.domains([s]).map(\.name) == names && Planner.weakest([s]) == names, "ties sort by name")
        }

        engineChecks()

        // Chat markdown: paragraphs, bullets, numbered items, continuation lines, headings; bold stays inline.
        let md = ChatText.blocks("**Today** is rest.\nNo tests.\n\n- Sleep early\n* Eat\n  well\n1. Read\n2) Check\n\n# Plan\nAfter")
        check(md == [.text("**Today** is rest.\nNo tests."), .bullet("Sleep early"), .bullet("Eat well"), .number("1.", "Read"), .number("2.", "Check"), .text("**Plan**\nAfter")],
              "chat markdown blocks")
        check(String(ChatText.inline("a **b** c").characters) == "a b c", "chat markdown bold is inline")

        // Onboarding asks a score for each date already sat, none for booked ones (spec 6).
        var ob = Profile(), now = Calendar.current.startOfDay(for: Date())
        ob.sittings = [Sitting(date: Calendar.current.date(byAdding: .day, value: -30, to: now)!), Sitting(date: now), Sitting(date: Calendar.current.date(byAdding: .day, value: 30, to: now)!)]
        check(OnboardingView.flow(ob) == [.name, .dates, .score(ob.sittings[0].id), .score(ob.sittings[1].id), .earlier, .target, .week, .reminder, .ai, .screen, .plan]
              && OnboardingView.flow(Profile()).count == 9, "onboarding: a score step per date sat")

        // Each part's own checks.
        for (name, fails) in [("import", Importer.selfCheck()), ("flashcards", CardStore.selfCheck()), ("providers", Provider.selfCheck()), ("tutor chat", Coach.selfCheck())] {
            check(fails.isEmpty, "\(name): " + (fails.isEmpty ? "self-check" : fails.joined(separator: "; ")))
        }
        // Per-task model pins (test runs have no keys): "auto" and a keyless pin both run the main choice.
        check(Brain.resolve("auto") == Brain.provider && Brain.resolve(nil) == Brain.provider && Brain.resolve("openai") == Brain.provider
              && Brain.resolve("apple") == (Brain.appleReady ? .apple : Brain.provider), "task pins fall back to Auto")
        let sch = try! GenerationSchemaCheck.make(Tutor.schema)
        check(sch, "on-device schema converts")
        let st = Stats(s)
        check(st.right == 1 && st.marked == 2 && st.over == ["M1-2"] && st.avgWrong == 90, "stats: score, pace, averages")
        check(st.revisited == 1, "revisits counted")
        check(Stats([s, s]).marked == 4, "overall adds sections")

        // Save and load (dates keep milliseconds)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sat-selftest-\(UUID().uuidString)")
        let data = try! Fmt.encoder.encode(s)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let back = try! Fmt.decoder.decode(Session.self, from: data)
        check(back == s, "session round-trips through JSON")
        check(Fmt.iso.string(from: b + 0.123).contains(".123"), "timestamps keep milliseconds")
        let pretty = JSONEncoder(); pretty.outputFormatting = [.prettyPrinted, .sortedKeys]; pretty.dateEncodingStrategy = Fmt.encoder.dateEncodingStrategy
        check((try? Fmt.decoder.decode(Session.self, from: pretty.encode(s))) == s, "older pretty-printed session.json still loads")

        // Saves land on disk after a quiet spell or on flush, latest state winning.
        let store = Store.shared
        var sv = Session(id: "selftest-save-\(UUID().uuidString)", start: b)
        let svFile = store.dir(sv.id).appendingPathComponent("session.json")
        func onDisk() -> Session? { (try? Data(contentsOf: svFile)).flatMap { try? Fmt.decoder.decode(Session.self, from: $0) } }
        store.save(sv)
        check(FileManager.default.fileExists(atPath: store.dir(sv.id).appendingPathComponent("shots").path) && onDisk() == nil, "save: folder made now, file written later")
        for n in 1...5 { store.update(sv.id) { $0.q["M1-1", default: QState()].chat.append(ChatLine(fromStudent: true, text: "line \(n)")) } }
        store.flush()
        sv = store.session(sv.id)!
        check(onDisk() == sv && sv.q["M1-1"]?.chat.count == 5, "save: flush writes the latest state")
        store.update(sv.id) { $0.test = "after flush" }
        let until = Date() + 2
        while onDisk()?.test != "after flush", Date() < until { RunLoop.main.run(until: Date() + 0.05) }
        check(onDisk()?.test == "after flush", "save: written without flush after the quiet spell")
        store.sessions.removeAll { $0.id == sv.id }
        try? FileManager.default.removeItem(at: store.dir(sv.id))

        // Request shape (no network)
        let shot = tmp.appendingPathComponent("q.jpg")
        try! Capture.jpeg(sampleQuestion())!.write(to: shot)
        let body = try! Claude.body(system: "x", messages: [["role": "user", "content": [["type": "image", "local_path": "q.jpg"], ["type": "text", "text": "hi"]]]],
                                    schema: Tutor.schema, base: tmp)
        let img = ((body["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]])[0]
        check((img["source"] as? [String: Any])?["type"] as? String == "base64", "image path swapped for base64 on send")
        check(((body["output_config"] as! [String: Any])["format"] as? [String: Any])?["type"] as? String == "json_schema", "structured output requested")
        check(body["model"] as? String == "claude-opus-5-5", "model id")
        check(JSONSerialization.isValidJSONObject(body), "body is valid JSON")
        let req = (Tutor.schema["required"] as! [String]).sorted(), props = (Tutor.schema["properties"] as! [String: Any]).keys.sorted()
        check(req == props, "schema requires every field")
        let keys = Mirror(reflecting: a.analysis!).children.compactMap(\.label).map { $0.replacingOccurrences(of: "([A-Z])", with: "_$1", options: .regularExpression).lowercased() }.sorted()
        check(keys == (props.map { Tutor.storedNames[$0] ?? $0 } + ["question_ja"]).sorted(), "schema fields match Analysis")
        let reply = #"{"question_en":"q","topic":"Algebra","skill":"s","difficulty":"Easy","correct_answer":"A","student_answer":"B","verdict":"wrong","solution":"1. x","wording":"w","trap":"","time_note":"t","mistake_cause":"misread","coach_line":"c","key_phrase":"k","key_point":"kp","vocab":[{"term":"slope","meaning":"steepness"}]}"#
        let parsed = try? Tutor.snake.decode(Analysis.self, from: Tutor.stored(reply))
        check(parsed?.solutionJa == "1. x" && parsed?.vocab.first?.note == "steepness" && parsed?.questionJa == "" && parsed?.keyPoint == "kp.", "English reply maps onto stored fields")
        let fix = #"{"headline":"h","summary":"s","praise":"p","fixes":[{"cause":"time","title":"t","why":"w","drill":"d","questions":["Q1"]}]}"#
        check((try? Tutor.snake.decode(Debrief.self, from: Tutor.stored(fix)))?.fixes.first?.drillJa == "d.", "English debrief maps onto stored fields")
        do {   // Practice: a generated set parses, only questions the independent solve agrees with survive, scoring counts them
            let qs = (try? Practice.parse(practiceFixture)) ?? []
            check(qs.count == 4 && qs[1].choices.first == "microbes" && qs[0].keyPoint.hasSuffix(".") && qs[0].vocab.first?.note.isEmpty == false
                  && qs[2].solutionJa.hasPrefix("1.") && qs[2].desmos == ["y=3x-12"] && qs[3].choices.isEmpty, "practice set parses")
            let solved = (try? Practice.answers(#"{"answers":[{"number":"1","answer":"A"},{"number":"2","answer":"B"},{"number":"3","answer":"(D)"},{"number":"4","answer":"0.75"}]}"#)) ?? [:]
            let kept = Practice.verified(qs, solved)
            check(kept.map(\.skill) == [qs[0].skill, qs[2].skill, qs[3].skill], "answer check keeps only questions the solver agrees with")
            var bad = qs[0]; bad.choices.removeLast()
            check(Practice.verified([bad], ["1": "A"]).isEmpty, "answer check drops a question without four choices")
            var set = PracticeSet(section: Sec.math, domain: "Algebra", difficulty: "Medium", asked: 3, questions: Array(kept.dropFirst()))
            set.work[0].answer = "C"; set.work[1].answer = "3/4"
            check(set.score == 1 && !set.right(0) && set.right(1) && set.limit == 190, "practice scoring and time limit")
            let p = Practice(file: nil)
            p.sets = [set]
            check(p.stats("Algebra") == (0, 0), "unsubmitted sets don't count")
            p.update(set.id) { $0.done = true }
            check(p.stats("Algebra") == (0, 1) && p.stats("Problem-Solving and Data Analysis") == (1, 1), "practice stats by domain")
            let req = ((Practice.schema["properties"] as! [String: Any])["questions"] as! [String: Any])["items"] as! [String: Any]
            check((req["required"] as! [String]) == (req["properties"] as! [String: Any]).keys.sorted(), "practice schema requires every field")
            check((try? GenerationSchemaCheck.make(Practice.schema)) == true && (try? GenerationSchemaCheck.make(Practice.answerSchema)) == true, "practice schemas work on device")
            check(!Practice.exam(qs).contains(qs[0].keyPoint) && Practice.exam(qs).contains("D. $4$"), "the solver sees no key")
            practiceChecks(qs)
            practiceFlowChecks(qs)
        }
        // Sidebar: one toolbar toggle (off screen), shared with View > Hide Sidebar.
        let wasOnboarded = PlanStore.shared.profile.onboarded
        PlanStore.shared.profile.onboarded = true
        let win = NSWindow(contentViewController: NSHostingController(rootView: MainView()))
        win.setFrameOrigin(NSPoint(x: -10000, y: -10000)); win.orderBack(nil)
        RunLoop.main.run(until: Date() + 1)
        check(win.toolbar?.items.filter { $0.label.hasSuffix("Sidebar") }.count == 1, "toolbar has one sidebar toggle")
        Sidebar.shared.toggle(); let hid = Sidebar.shared.hidden
        RunLoop.main.run(until: Date() + 1)
        let whileHidden = win.toolbar?.items.filter { $0.label.hasSuffix("Sidebar") && $0.isVisible }.count ?? 0
        Sidebar.shared.toggle()
        check(hid && !Sidebar.shared.hidden, "sidebar hides and comes back")
        check(whileHidden <= 1, "one sidebar toggle while hidden (saw \(whileHidden))")
        win.orderOut(nil)
        PlanStore.shared.profile.onboarded = wasOnboarded
        try? FileManager.default.removeItem(at: tmp)
        print("all checks passed")
    }

    /// Real capture + OCR against Preview showing rendered Bluebook pages.
    static func trackTest() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sat-track-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let q4 = dir.appendingPathComponent("q4.png"), q5 = dir.appendingPathComponent("q5.png")
        for (url, n) in [(q4, 4), (q5, 5)] {
            try! NSBitmapImageRep(cgImage: sampleQuestion(number: n)).representation(using: .png, properties: [:])!.write(to: url)
        }
        let previewID = "com.apple.Preview"
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: previewID).isEmpty
        let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: previewID)!
        func show(_ url: URL) async {
            _ = try? await NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
            try? await Task.sleep(for: .seconds(2))
        }
        UserDefaults.standard.setVolatileDomain(["autoAnalyze": false], forName: UserDefaults.argumentDomain)
        await show(q4)
        let t = Tracker.shared
        t.start()
        try? await Task.sleep(for: .seconds(5))
        check(t.number == 4, "read Question 4 from the Preview window (got \(t.number.map(String.init) ?? "nothing"))")
        await show(q5)
        try? await Task.sleep(for: .seconds(5))
        check(t.number == 5, "moved to Question 5")
        let s = t.session!
        check(s.visits.count == 2 && s.visits[0].end != nil, "two visits, first one closed")
        let shots = s.visits.compactMap(\.shot).map { Store.shared.dir(s.id).appendingPathComponent($0) }
        check(shots.count == 2 && shots.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "a screenshot for each question")
        t.stop()
        let log = (try? String(contentsOf: Store.shared.dir(s.id).appendingPathComponent("events.jsonl"), encoding: .utf8)) ?? ""
        check(log.contains("\"event\":\"question\"") && log.contains("\"event\":\"stop\""), "raw event log written (\(log.split(separator: "\n").count) lines)")
        if !wasRunning { NSRunningApplication.runningApplications(withBundleIdentifier: previewID).forEach { $0.terminate() } }
        try? FileManager.default.removeItem(at: dir)
    }

    /// One real request: analyze a rendered question, then ask a follow-up.
    /// Loads DesmosView as the question view (expressions and answer point) and as the practice calculator (empty), and its
    /// page with an unreachable Desmos (offline), in windows that never show; reports what each page did and saves a PNG of each into `dir`.
    static func desmosCheck(_ dir: URL) -> Never {
        let offline = WKWebView()
        offline.loadHTMLString(DesmosView.html(["y=x"]).replacingOccurrences(of: "www.desmos.com", with: "desmos.invalid"), baseURL: URL(string: "https://www.desmos.com"))
        let cases: [(String, NSView)] = [("question", NSHostingView(rootView: DesmosView(expressions: ["y=x^{2}-4x+3", "y=2x-5"], focus: "(2,-1)"))),
                                         ("calculator", NSHostingView(rootView: DesmosView(expressions: []))), ("offline", offline)]
        let windows = cases.map { name, view in
            let win = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 450), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = view
            view.layoutSubtreeIfNeeded()
            // WebKit pauses drawing (the graph canvas stays 0x0) in a hidden window, so order it in: fully transparent,
            // click-through and placed off every display, so it never shows; occlusion detection off for the same reason.
            (view as? WKWebView ?? view.firstSubview(of: WKWebView.self))?.setValue(false, forKey: "windowOcclusionDetectionEnabled")
            win.alphaValue = 0; win.ignoresMouseEvents = true
            win.orderBack(nil)
            win.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            return win
        }
        Task {
            try? await Task.sleep(for: .seconds(12))
            var ok = true
            for (name, view) in cases {
                guard let web = view as? WKWebView ?? view.firstSubview(of: WKWebView.self) else { print("FAIL \(name): no WKWebView"); exit(1) }
                // Pixels drawn on the graph canvas (grid, curves); -1 when there is none.
                let js = "JSON.stringify({desmos: typeof Desmos, ready: !!window.ready, expressions: window.ready ? calc.getExpressions().length : 0, graphPixels: [...document.querySelectorAll('canvas')].reduce((n, c) => { if (!c.width || !c.height) return n; const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; for (let i = 3; i < d.length; i += 4) if (d[i]) n++; return n }, -1), text: document.body.innerText.slice(0, 60)})"
                let r = (try? await web.evaluateJavaScript(js)) as? String ?? "(no result)"
                let j = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
                let pass = name == "offline" ? (j["text"] as? String)?.contains("Desmos needs the internet") == true
                    : j["ready"] as? Bool == true && (j["graphPixels"] as? Int ?? 0) > 1000 && j["expressions"] as? Int == (name == "question" ? 3 : 1)
                ok = ok && pass
                print(pass ? "ok  " : "FAIL", name, r)
                let png = dir.appendingPathComponent("desmos-\(name).png")
                if let img = try? await web.takeSnapshot(configuration: nil), let t = img.tiffRepresentation,
                   let data = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                    try? data.write(to: png); print("     snapshot", png.path)
                }
            }
            _ = windows
            exit(ok ? 0 : 1)
        }
        RunLoop.main.run()
        exit(1)
    }

    static func live() async {
        let store = Store.shared
        var s = Session(id: "live-\(Int(Date().timeIntervalSince1970))", start: Date())
        s.visits = [Visit(module: 1, number: 4, start: Date() - 130, end: Date(), shot: "shots/M1-4_v1.jpg")]
        store.save(s)
        try! Capture.jpeg(sampleQuestion())!.write(to: store.dir(s.id).appendingPathComponent("shots/M1-4_v1.jpg"))
        let t0 = Date()
        await Tutor.analyze(s.id, "M1-4")
        let st = store.session(s.id)!.q["M1-4"]!
        if let e = st.error { print("FAIL analyze: \(e)"); exit(1) }
        let a = st.analysis!
        print("analyze \(Int(Date().timeIntervalSince(t0))) s: answer=\(a.correctAnswer) student=\(a.studentAnswer) verdict=\(a.verdict) topic=\(a.topic)")
        print("vocab: " + a.vocab.map { "\($0.en)=\($0.ja)" }.joined(separator: ", "))
        print("solution: \(a.solutionJa.prefix(300))")
        check(a.verdict == "wrong" && a.correctAnswer.contains("A"), "Claude solved it and saw the student picked B")
        await Tutor.ask(s.id, "M1-4", "What does \"value of\" mean here?")
        let reply = store.session(s.id)!.q["M1-4"]!.chat.last!
        print("follow-up: \(reply.text.prefix(300))")
        check(!reply.fromStudent && store.session(s.id)!.q["M1-4"]!.chat.count == 2, "follow-up answered")
        await Tutor.debrief(s.id, "Math")
        let d = store.session(s.id)!.debriefs["Math"]
        print("debrief: \(d?.headlineJa ?? "-") | fixes: \(d?.fixes.map { "\($0.titleJa) \($0.questions)" } ?? [])")
        check(d != nil && !(d!.fixes.isEmpty), "debrief made")
    }

    static func render(_ view: some View, _ size: NSSize, _ name: String, dark: Bool = false, to dir: URL) {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Palette.bg))
        w.contentView = host
        w.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date() + 1.2)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
        w.orderOut(nil)
        print("wrote \(name)")
    }

    /// A test screen with a highlight's note editor drawn where its popover opens: under `mark`, at `MarkView.anchor`.
    /// (An NSPopover is its own window, which an off-screen render can't capture.)
    static func notePopover<V: View>(_ view: V, _ size: NSSize, _ mark: PracticeSet.Mark, _ name: String, to dir: URL) {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        w.contentView = host
        w.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date() + 1.2)
        func find(_ v: NSView) -> [MarkView] { (v as? MarkView).map { [$0] } ?? v.subviews.flatMap(find) }
        let r = find(host).first.map { $0.convert($0.anchor(NSRange(location: mark.start, length: mark.length)), to: host) } ?? .zero
        w.orderOut(nil)
        print("note anchor \(r)")
        let editor = MarkEditor(mark: mark) { _ in }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.15)))
            .overlay(alignment: .top) { Rectangle().fill(.white).frame(width: 14, height: 14).rotationEffect(.degrees(45)).offset(y: -6) }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
            .fixedSize()
        render(view.overlay(alignment: .topLeading) { editor.offset(x: r.midX - 140, y: r.maxY + 10) }, size, name, to: dir)
    }

    /// Renders every screen to PNGs without showing anything on screen (1100×760, the window's minimum).
    static func snapshot(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store.shared
        let size = NSSize(width: 1100, height: 760)
        func shot(_ v: some View, _ name: String, _ sz: NSSize = size) {
            render(v, sz, name + ".png", to: dir)
            render(v, sz, name + "-dark.png", dark: true, to: dir)
        }
        var p = fixture(Profile())
        p.name = "Alex"
        PlanStore.shared.profile = p
        // SAT_SESSION=<id> (with SAT_DATA on a copy of real data): render that real test.
        if let id = ProcessInfo.processInfo.environment["SAT_SESSION"], let real = store.session(id) {
            CardStore.shared.sync()
            store.nav = .session(id)
            shot(MainView(), "real-overview")
            var wrong = QFilter(); wrong.result = "Wrong"
            shot(MainView().environment(\.reviewFilter, wrong), "real-overview-wrong")
            for sec in real.sections {
                shot(MainView().environment(\.reviewScope, sec), "real-\(sec.prefix(4))")
                shot(MainView().environment(\.reviewScope, sec), "real-\(sec.prefix(4))-large", NSSize(width: 1190, height: 773))   // the owner's window
                if let k = real.only(sec).keys.first(where: { real.correct($0) == false }) {
                    shot(QuestionView(sid: id, start: k, filter: .constant(wrong), scope: sec) {}.background(Palette.surface), "real-question-\(sec.prefix(4))", NSSize(width: 1068, height: 728))
                }
            }
            for k in (ProcessInfo.processInfo.environment["SAT_KEYS"] ?? "").split(separator: ",").map(String.init) where real.keys.contains(k) {
                shot(QuestionView(sid: id, start: k) {}.background(Palette.surface), "real-question-\(k)", NSSize(width: 1068, height: 728))
            }
            for (nav, name) in [(Store.Nav.today, "real-today"), (.plan, "real-plan"), (.cards, "real-cards"), (.tutor, "real-tutor")] {
                store.nav = nav
                shot(MainView(), name)
            }
            tutorShots(dir)
            onboardingShots(dir, prefix: "real-")
            return
        }
        let b = Date() - 3600
        var s = Session(id: "snapshot", start: b)
        var t = b
        for n in 1...22 {
            let secs = Double([40, 75, 120, 60, 95, 200, 50, 88, 140, 30, 110, 65][n % 12])
            s.visits.append(Visit(module: 1, number: n, start: t, end: t + secs, shot: "shots/M1-4_v1.jpg"))
            t += secs
        }
        s.visits.append(Visit(module: 1, number: 6, start: t, end: t + 45, shot: "shots/M1-4_v1.jpg"))
        let topics = ["Algebra", "Advanced Math", "Problem-Solving and Data Analysis", "Geometry and Trigonometry"]
        for n in 1...22 {
            var q = QState()
            if n < 20 {
                q.analysis = Analysis(questionEn: "If 3x + 7 = 22, what is the value of 6x − 4?", questionJa: "",
                                      topic: topics[n % 4], skill: "Linear equations in one variable", difficulty: "Easy",
                                      correctAnswer: "A", studentAnswer: n % 5 == 0 ? "B" : "A", verdict: n % 5 == 0 ? "wrong" : "correct",
                                      solutionJa: "1. 3x = 15, so x = 5.\n2. 6x − 4 = 30 − 4 = 26.", wordingJa: "**the value of 6x − 4** asks for the expression, not for x.",
                                      trapJa: "Stopping at x = 5: 5 is not a choice, but 30 (6x) is.", timeJa: "2:10 is over the 1:35 pace. Doubling the equation gives 6x = 30 at once.",
                                      vocab: [Vocab(en: "value of", ja: "", note: "the number an expression works out to"), Vocab(en: "expression", ja: "", note: "math without an equals sign")])
            }
            q.guessed = n == 9
            if n == 5 {   // the new format, with quotes and math, so renders show the typography
                q.analysis?.keyPoint = "The question asks for $6x - 4$, not $x$: double the equation to get **$6x = 30$** at once."
                q.analysis?.solutionJa = "1. Subtract 7: $3x = 15$.\n2. Multiply by 2: $6x = 30$, so $6x - 4 = 26$.\n3. Check: $\\frac{26 + 4}{6} = 5$ and $5^2 \\ge 25$."
                q.analysis?.trapJa = "B is $6x$, the step before the end. The question says \"the value of 6x − 4\", so subtract 4."
                q.analysis?.coachLine = "Underline what the question asks for before you solve."
            }
            s.q["M1-\(n)"] = q
        }
        let box = Capture.find("the value of 6x - 4", in: sampleQuestion())
        let causes = ["misread", "vocabulary", "misread", "time"]
        for (i, n) in [5, 10, 15, 20].enumerated() {
            s.q["M1-\(n)"]?.analysis?.mistakeCause = causes[i]
            s.q["M1-\(n)"]?.analysis?.keyPhrase = "the value of 6x - 4"
            s.q["M1-\(n)"]?.analysis?.coachLine = "You stopped at x = 5. The question asks for 6x − 4. Reread the last line before you choose."
            s.q["M1-\(n)"]?.highlight = box
        }
        s.q["M1-20"]?.mark = false
        s.debriefs["Math"] = Debrief(headlineJa: "You lose points reading the question, not doing the math",
                            summaryJa: "Two of your four misses solved for x and stopped. Your math is fast and right; a 5-second check of what is asked wins those back.",
                            praiseJa: "All 9 Algebra questions right, 1:10 on average.",
                            fixes: [.init(cause: "misread", titleJa: "Reread what is asked", whyJa: "Q5 and Q15: you answered x, not the expression.", drillJa: "Before choosing, reread the last sentence of the question.", questions: ["Q5", "Q15"]),
                                    .init(cause: "vocabulary", titleJa: "Learn 10 SAT words", whyJa: "Q10 stopped on 'expression'.", drillJa: "Five minutes a day with the word list.", questions: ["Q10"]),
                                    .init(cause: "time", titleJa: "Move on at 2:30", whyJa: "Q6 took 3:20 and rushed the end.", drillJa: "Past 2:30, flag it and go on.", questions: ["Q6", "Q20"])])
        s.q["M1-6"]?.chat = [ChatLine(fromStudent: true, text: "What does \"value of\" mean here?"), ChatLine(fromStudent: false, text: "It means the number the expression 6x − 4 works out to, not x itself.")]
        s.end = t + 45
        store.save(s)
        try! Capture.jpeg(sampleQuestion(chosen: 1))!.write(to: store.dir(s.id).appendingPathComponent("shots/M1-4_v1.jpg"))
        store.nav = .session(s.id)
        Tracker.shared.preview(s, number: 6)

        s.test = "SAT Practice 6"; store.save(s); Tracker.shared.preview(s, number: 6)
        func prefs(_ p: [String: Any]) { UserDefaults.standard.setVolatileDomain(p, forName: UserDefaults.argumentDomain) }
        render(MenuView(), NSSize(width: 300, height: 470), "menu-running.png", to: dir)
        render(BarView().padding(20), NSSize(width: 520, height: 92), "bar-running.png", to: dir)
        Tracker.shared.preview(nil, number: nil)
        CardStore.shared.sync()
        Coach.shared.lines = [Coach.Line(fromStudent: true, text: "I can't study this Thursday."),
                              Coach.Line(fromStudent: false, text: "No problem. Thursday is off, and the rest of the week stays as planned.", changes: Coach.shared.parse([["action": "day_off", "value": "", "list": [], "date": Planner.day.string(from: Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 5), matchingPolicy: .nextTime)!)]]).map(\.label))]
        for (nav, name) in [(Store.Nav.today, "today"), (.tutor, "tutor"), (.plan, "plan"), (.cards, "cards"), (.vocab, "vocab"), (.settings, "settings"), (.session(s.id), "session")] {
            store.nav = nav
            shot(MainView(), name)
        }
        var over = QFilter(); over.overPace = true
        store.nav = .session(s.id)
        shot(MainView().environment(\.reviewFilter, over), "session-over-pace")
        store.progress[s.id] = .init(done: 33, total: 98)
        shot(MainView(), "session-loading")
        store.progress[s.id] = .init(done: 98, total: 98)
        shot(MainView(), "session-writing")
        store.progress[s.id] = nil
        // Practice: a fixture set (no AI, no network: Desmos is drawn as a placeholder).
        let practice = Practice.shared
        practice.desmos = false
        let pq = (try? Practice.parse(practiceFixture)) ?? []
        let rwSec = Practice.rw
        var rw = PracticeSet(section: rwSec, domain: "Craft and Structure", difficulty: "Medium", asked: 5, questions: pq.filter { $0.section != Sec.math })
        rw.work[0].answer = "B"; rw.work[0].checked = true; rw.work[1].answer = "A"; rw.work[1].crossed = ["C"]
        var math = PracticeSet(section: Sec.math, domain: "Algebra", difficulty: "Medium", asked: 5, questions: pq.filter { $0.section == Sec.math })
        math.work = [.init(answer: "A", seconds: 74), .init(answer: "3/4", seconds: 121)]
        math.done = true
        // A full test: R&W Module 1 and Math Module 1 written, each Module 2 still to come.
        var ft = PracticeSet(section: "\(rwSec) + \(Sec.math)", domain: "Full test", difficulty: "Adaptive", asked: 98, questions: pq)
        ft.id = "practice-full"; ft.test = true; ft.stage = 0; ft.visits = []
        ft.modules = [.init(section: rwSec, number: 1, first: 0, count: 2, used: 1700), .init(section: rwSec, number: 2),
                      .init(section: Sec.math, number: 1, first: 2, count: 2), .init(section: Sec.math, number: 2)]
        ft.work[0].answer = "A"; ft.work[0].marked = true; ft.work[0].crossed = ["C"]
        var done = ft; done.id = "practice-full-done"; done.done = true; done.stage = 4
        done.work[1].answer = "C"; done.work[2].answer = "D"; done.work[3].answer = "3/4"
        done.work = done.work.enumerated().map { var w = $1; w.seconds = [64, 88, 101, 140][$0]; return w }
        practice.sets = [done, math, rw, ft]
        practice.blocks = [Block(section: rwSec, domain: "Craft and Structure", skill: "Words in Context", difficulty: "Hard", count: 6, focus: "science passages"),
                           Block(section: rwSec, domain: "Standard English Conventions"), Block(section: Sec.math, domain: "Advanced Math", difficulty: "Mixed", count: 8, format: Practice.grid)]
        practice.templates = [Template(name: "Weekday mix", blocks: practice.blocks)]
        store.nav = .practice
        practice.open = nil
        shot(MainView(), "practice")
        shot(PracticeView(full: true).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.bg), "practice-full-setup")
        // Writing in progress: one block done, one writing, one failed.
        var prog = rw; prog.id = "practice-progress"; prog.work = prog.questions.map { _ in .init() }
        practice.sets.append(prog)
        let pb = practice.blocks
        practice.parts[prog.id] = [Part(title: "\(pb[0].title) · Hard", section: rwSec, slots: Practice.slots(pb[0]), done: 6, kept: 5, step: ""),
                                   Part(title: "\(pb[1].title) · Mixed", section: rwSec, slots: Practice.slots(pb[1]), done: 0, kept: 0, step: "Writing"),
                                   Part(title: "\(pb[2].title) · Mixed", section: Sec.math, slots: Practice.slots(pb[2]), step: "", error: "The request timed out.")]
        practice.building = prog.id
        shot(MainView(), "practice-progress")
        practice.building = nil; practice.parts = [:]
        practice.open = ft.id
        shot(MainView(), "practice-test")                                   // full test, R&W, under 5 minutes
        let passage = pq[0].passage as NSString, near = passage.range(of: "coastal restoration projects"), noted = passage.range(of: "the knowledge of people who have fished")
        let marks = [PracticeSet.Mark(start: near.location, length: near.length),
                     PracticeSet.Mark(start: noted.location, length: noted.length, color: "pink", note: "Why outside plans fail: they ignore locals.")]
        practice.update(ft.id) { $0.work[0].highlights = marks }
        shot(PracticeTest(id: ft.id, at: 0, highlight: true), "practice-test-highlights")
        render(MarkEditor(mark: marks[1]) { _ in }, NSSize(width: 280, height: 110), "practice-test-highlight-editor.png", to: dir)
        notePopover(PracticeTest(id: ft.id, at: 0, highlight: true), size, marks[0], "practice-test-highlight-popover.png", to: dir)
        shot(PracticeTest(id: ft.id, at: 0, more: true), "practice-test-more")
        practice.leaving = {}
        shot(PracticeTest(id: ft.id, at: 0), "practice-test-leave")
        practice.leaving = nil
        practice.update(ft.id) { $0.work[0].highlights = nil }
        practice.open = nil
        shot(PracticeTest(id: rw.id, at: 0), "practice-test-checked")        // practice questions after Check
        practice.update(ft.id) { $0.stage = 2 }
        shot(PracticeTest(id: ft.id, at: 2), "practice-test-math")
        shot(PracticeTest(id: ft.id, at: 3, calc: true), "practice-test-math-calc")
        practice.update(ft.id) { $0.stage = 0 }
        shot(PracticeTest(id: ft.id, phase: .review, at: 0), "practice-review")
        shot(PracticeTest(id: rw.id, phase: .review, at: 0), "practice-questions-review")
        shot(PracticeTest(id: ft.id, phase: .over, at: 0), "practice-over")
        shot(PracticeTest(id: ft.id, phase: .rest, at: 0), "practice-break")
        practice.update(ft.id) { $0.stage = 1 }
        practice.parts[ft.id] = [Part(title: "Reading & Writing · Module 2", section: rwSec, slots: [], module: 1, hard: true, target: 27, step: "Writing", got: Array(repeating: pq[0], count: 12))]
        shot(PracticeTest(id: ft.id, phase: .wait, at: 0), "practice-wait")
        practice.parts = [:]
        practice.update(ft.id) { $0.stage = 0 }
        practice.open = math.id
        shot(MainView(), "practice-results")
        practice.open = done.id
        shot(MainView(), "practice-results-full")
        practice.open = nil
        shot(QuestionView(sid: s.id, start: "M1-5") {}.background(Palette.surface), "question", NSSize(width: 1068, height: 728))
        store.update(s.id) {
            $0.q["M1-6"]?.convo = Data("[]".utf8)
            $0.q["M1-6"]?.chat += [ChatLine(fromStudent: true, text: "Is there a faster way?"),
                                   ChatLine(fromStudent: false, text: "Yes. You don't need x at all.\n\n1. Double both sides: **6x + 14 = 44**.\n2. Subtract 18 from both sides: 6x − 4 = 26.\n\nThat's two steps instead of four, the same trick as **Q5**."),
                                   ChatLine(fromStudent: true, text: "Nice, thanks")]
        }
        shot(QuestionChat(sid: s.id, key: "M1-6", open: true).padding(20), "question-chat", NSSize(width: 440, height: 580))
        shot(QuestionChat(sid: s.id, key: "M1-5", open: true).padding(20), "question-chat-empty", NSSize(width: 440, height: 580))
        shot(ImportView(sid: s.id).background(Palette.surface), "import", NSSize(width: 760, height: 620))
        // Log a test, every step, from fixtures (no AI).
        let log = NSSize(width: 940, height: 680), pages = ["R1": khanReading, "M1": khanMath]
        shot(LogTestSheet().background(Palette.surface), "log-1-paste", log)
        shot(LogTestSheet(page: khanResults).background(Palette.surface), "log-1-results", log)
        shot(LogTestSheet(page: khanResults, step: 1).background(Palette.surface), "log-2-module", log)
        shot(LogTestSheet(page: khanResults, modules: pages, step: 1).background(Palette.surface), "log-2-module-pasted", log)
        shot(LogTestSheet(page: khanResults, modules: pages, step: 2).background(Palette.surface), "log-3-module", log)
        shot(LogTestSheet(page: khanResults, modules: pages, step: 3).background(Palette.surface), "log-4-module-pasted", log)
        let graphed = ["M1": khanGraph + "\n" + khanMath]   // question 1's graph is a picture: a slot to paste it
        shot(LogTestSheet(page: khanResults, modules: graphed, step: 3).background(Palette.surface), "log-4-module-graph", log)
        shot(LogTestSheet(page: khanResults, modules: graphed, step: 5, open: "M1-1").background(Palette.surface), "log-6-review-graph", log)
        shot(LogTestSheet(page: khanResults, modules: pages, step: 4).background(Palette.surface), "log-5-module-skipped", log)
        for k in ["R1-2", "M1-1", "M1-2"] {
            shot(LogTestSheet(page: khanResults, modules: pages, step: 5, open: k).background(Palette.surface), "log-6-review-\(k)", log)
        }
        // two-line choices: all four still show without scrolling
        let long = ["R1": khanReading.replacingOccurrences(of: "Riverside had more species in 2020 than in 2015.",
            with: "Riverside had more species in 2020 than in 2015, while the other two parks counted about the same number in both years.")
            .replacingOccurrences(of: "Lakeview had the fewest species in 2015.", with: "Lakeview had the fewest species in 2015, so its growth matters less to the claim than the others.")]
        shot(LogTestSheet(page: khanResults, modules: long, step: 5, open: "R1-2").background(Palette.surface), "log-6-review-long", log)
        var logged = Session(id: "logged-khan", start: Date() - 86400)
        logged.end = logged.start; logged.test = "SAT Practice 4"
        var texts: [String: Official.Answer] = [:]
        for (m, page) in pages { for (n, a) in Khan.parse(page, max: Khan.expected(m)) { texts["\(m)-\(n)"] = a } }
        logged.official = Khan.merge(texts, into: LogTestSheet.results(khanResults)!.o)
        store.save(logged)
        shot(QuestionView(sid: logged.id, start: "R1-2") {}.background(Palette.surface), "question-logged", NSSize(width: 1068, height: 728))
        shot(QuestionView(sid: logged.id, start: "M1-1") {}.background(Palette.surface), "question-logged-math", NSSize(width: 1068, height: 728))
        onboardingShots(dir)
        prefs(["test": "SAT Practice 6"])
        render(MenuView(), NSSize(width: 300, height: 470), "menu-idle.png", to: dir)
    }

    /// The one case every snapshot shows, the owner's: official SAT dates only. Sat the SAT on Sat Nov 7 2026 (score out
    /// later), booked Sat Dec 5 2026, target 1,450, Mon–Thu and Sat for 60 min, a PSAT from Oct 2025 as the earlier score.
    static func fixture(_ base: Profile) -> Profile {
        var p = base
        let cal = Calendar.current
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }
        p.onboarded = true; p.grade = 11; p.targetScore = 1450; p.days = [2, 3, 4, 5, 7]; p.minutes = 60
        p.reminders = true; p.remindAt = 17 * 60; p.skips = []; p.pins = [:]; p.focus = []
        p.sittings = [Sitting(date: d(2026, 11, 7)), Sitting(date: d(2026, 12, 5))]
        p.priorScores = [PriorScore(kind: .psat, date: d(2025, 10, 15), rw: 600, math: 610, total: 1210)]
        return p
    }

    /// Today, Plan, Settings, the menu, Tutor and onboarding from the fixture, at the owner's window (1190×745) and the
    /// minimum (900×640), light and dark. The states come from moving "today" through November; every day passed on the
    /// way has its tasks ticked (a student who keeps up), and the Nov 7 score comes in on Nov 20.
    /// Reads whatever SAT_DATA holds (a copy of real data) and rewrites its profile and plan.
    static func planStates(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store.shared, plan = PlanStore.shared, cal = Calendar.current
        CardStore.shared.sync()
        let saved = Clock.shift
        defer { Clock.shift = saved }
        func at(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d))! }
        var day = at(11, 7)
        func noon() { Clock.shift = day.addingTimeInterval(12 * 3600).timeIntervalSince(Date()) }
        func go(_ m: Int, _ d: Int) {
            while day < at(m, d) {
                noon()
                for t in plan.today?.tasks ?? [] where t.kind != .rest && !plan.isDone(day, t) { plan.toggle(day, t) }
                if cal.isDate(day, inSameDayAs: at(11, 20)), let s = plan.profile.sittings.first(where: { cal.isDate($0.date, inSameDayAs: at(11, 7)) }) {
                    plan.recordScore(sitting: s.id, rw: 640, math: 700)
                }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
            noon()
        }
        func shot(_ name: String, _ pages: [(Store.Nav, String)] = [(.today, "today"), (.plan, "plan")]) {
            for (nav, page) in pages {
                store.nav = nav
                for (size, tag) in [(NSSize(width: 1190, height: 745), ""), (NSSize(width: 900, height: 640), "-small")] {
                    render(MainView(), size, "\(name)-\(page)\(tag).png", to: dir)
                    render(MainView(), size, "\(name)-\(page)\(tag)-dark.png", dark: true, to: dir)
                }
            }
        }
        func menu(_ name: String) {
            let size = NSHostingView(rootView: MenuView()).fittingSize
            let v = MenuView().clipShape(RoundedRectangle(cornerRadius: M.radius + M.pad, style: .continuous))   // the popover's corners
            render(v, size, "\(name).png", to: dir)
            render(v, size, "\(name)-dark.png", dark: true, to: dir)
        }
        plan.profile = fixture(plan.profile)
        noon()
        shot("test-day")
        go(11, 8)
        shot("needs-score")
        plan.profile.onboarded = false
        onboardingShots(dir)
        plan.profile.onboarded = true
        if let s = plan.needsScore.first { plan.snooze(sitting: s.id) }
        go(11, 9)
        shot("suggestions")
        tutorShots(dir)
        for s in plan.suggestions { plan.dismiss(s.id) }
        go(11, 10)
        shot("normal")
        menu("menu")
        go(11, 12)
        for t in plan.today?.tasks ?? [] where t.kind != .rest && !plan.isDone(day, t) { plan.toggle(day, t) }
        shot("all-done")
        go(11, 13)
        shot("off-day")
        go(11, 30)
        shot("final-week")
        store.nav = .settings
        for (size, tag) in [(NSSize(width: 1190, height: 745), ""), (NSSize(width: 900, height: 640), "-small")] {
            render(MainView(), size, "settings\(tag).png", to: dir)
            render(MainView(), size, "settings\(tag)-dark.png", dark: true, to: dir)
            for tab in ["Tutor", "App"] {
                let detail = NSSize(width: size.width - 220, height: size.height)
                render(SettingsView(tab: tab), detail, "settings-\(tab.lowercased())\(tag).png", to: dir)
                render(SettingsView(tab: tab), detail, "settings-\(tab.lowercased())\(tag)-dark.png", dark: true, to: dir)
            }
        }
        go(12, 4)
        shot("eve")
        menu("menu-eve")
        go(12, 7)
        shot("not-booked")
    }

    /// The Tutor page in the detail area of the owner's window (1190x745 less the 220 sidebar) and of the smallest
    /// (900x640): the saved chat, an empty chat, a proposal waiting, the same proposal accepted.
    static func tutorShots(_ dir: URL) {
        func shot(_ name: String) {
            for (sz, tag) in [(NSSize(width: 970, height: 745), ""), (NSSize(width: 680, height: 640), "-narrow")] {
                render(CoachView(), sz, "\(name)\(tag).png", to: dir)
                render(CoachView(), sz, "\(name)\(tag)-dark.png", dark: true, to: dir)
            }
        }
        let coach = Coach.shared, plan = PlanStore.shared, saved = (coach.lines, plan.profile)
        defer { coach.lines = saved.0; plan.profile = saved.1 }
        shot("tutor-saved")
        coach.lines = []
        shot("tutor-empty")
        let thu = Calendar.current.nextDate(after: Clock.now, matching: DateComponents(weekday: 5), matchingPolicy: .nextTime)!
        let changes = coach.parse([["action": "day_off", "value": "", "list": [], "date": Planner.day.string(from: thu)],
                                   ["action": "set_minutes", "value": "75", "date": "", "list": []]])
        let s = plan.suggest(chat: changes, title: changes.map(\.label).joined(separator: ", "), why: "")
        coach.lines = [Coach.Line(fromStudent: true, text: "I have a school trip on Thursday. Can I skip it and make up the time?"),
                       Coach.Line(fromStudent: false, text: "Yes. Take Thursday off and study 75 minutes on your other days.",
                                  changes: changes.map(\.label), suggestion: s.id)]
        shot("tutor-pending")
        plan.accept(s.id)
        shot("tutor-accepted")
    }

    /// Every onboarding step at the window's minimum and at the owner's size, then the steps that change with input:
    /// a date already sat with its score typed, and earlier scores added.
    static func onboardingShots(_ dir: URL, prefix: String = "") {
        func shot(_ step: Int, _ name: String, adding: PriorScore.Kind? = nil) {
            for (sz, tag) in [(NSSize(width: 900, height: 640), ""), (NSSize(width: 1190, height: 745), "-full")] {
                render(OnboardingView(step: step, adding: adding), sz, "\(prefix)onboarding-\(name)\(tag).png", to: dir)
                render(OnboardingView(step: step, adding: adding), sz, "\(prefix)onboarding-\(name)\(tag)-dark.png", dark: true, to: dir)
            }
        }
        let plan = PlanStore.shared, saved = plan.profile
        defer { plan.profile = saved }
        let flow = OnboardingView.flow(OnboardingView.start())
        for (i, s) in flow.enumerated() { shot(i, "\(i)-" + "\(s)".prefix { $0.isLetter }) }
        guard let i = flow.firstIndex(where: { if case .score = $0 { true } else { false } }), let e = flow.firstIndex(of: .earlier),
              case .score(let id) = flow[i], let k = plan.profile.sittings.firstIndex(where: { $0.id == id }) else { return }
        plan.profile.sittings[k].rw = 640; plan.profile.sittings[k].math = 700   // the Nov 7 score, as it comes in on Nov 20
        shot(i, "\(i)-score-typed")
        shot(e, "\(e)-earlier-added")
        shot(e, "\(e)-earlier-bluebook", adding: .bluebook)
    }

    /// A Score Details page for SAT Practice 4 with the answer letters shown; the first three questions of R&W and Math
    /// match the Khan Academy fixtures below.
    static var khanResults: String {
        var page = "Score Details\nSAT Practice 4 - November 2, 2026\nQuestions Overview\n"
        let set = ["R1-1": ("A", "A"), "R1-2": ("A", "B"), "R1-3": ("B", "B"), "M1-1": ("B", "A"), "M1-2": ("26", "20"), "M1-3": ("D", "D")]
        for (sec, mod, n) in [("Reading and Writing", 1, 27), ("Reading and Writing", 2, 27), (Sec.math, 1, 22), (Sec.math, 2, 22)] {
            for q in 1...n {
                let (c, y) = set[Session.key(sec, mod, q)] ?? ("C", q % 6 == 0 ? "A" : "C")
                page += "\(q)\t\(sec)\t\(c)\t\(y)\t\n\(c == y ? "Correct" : "Incorrect")\n\n\(sec == Sec.math ? "Algebra" : "Craft and Structure")\n"
            }
        }
        return page
    }

    /// Khan Academy's page for SAT Practice 4, Reading and Writing Module 1, copied with ⌘A ⌘C (first three questions):
    /// choices as "(Choice A)" / "A" / text with the text twice, as letters on their own lines, and as "A license,".
    static let khanReading = """
    Skip to main content
    If you're seeing this message, it means we're having trouble loading external resources on our website.
    Search
    Donate
    Log in
    Sign up
    SAT Practice Test 4
    Reading and Writing: Module 1
    Question 1 | Words in context
    Marine biologist Lena Ortiz argues that coastal restoration projects succeed only when local communities help plan them. Projects designed far away, she notes, often ______ the knowledge of people who have fished the same waters for generations, and so they miss problems that residents could have pointed out at the start.
    Which choice completes the text with the most logical and precise word or phrase?
    Choose 1 answer:
    Choose 1 answer:
    (Choice A)
    overlook
    A
    overlook
    (Choice B)
    celebrate
    B
    celebrate
    (Choice C)
    duplicate
    C
    duplicate
    (Choice D)
    predict
    D
    predict
    Check
    Explain
    Report a problem
    Question 2 | Command of evidence: quantitative
    A researcher claims that the number of bird species in city parks grew between 2015 and 2020. The table shows species counted in three parks.
    Park	2015	2020
    Riverside	42	51
    Hilltop	37	35
    Lakeview	29	40
    Which choice best describes data from the table that support the researcher's claim?
    Choose 1 answer:
    A
    Riverside had more species in 2020 than in 2015.
    B
    Hilltop had fewer species in 2020 than in 2015.
    C
    Lakeview had the fewest species in 2015.
    D
    All three parks had more species in 2020.
    Hint
    Check
    Question 3 | Boundaries
    In 1921, Bessie Coleman became the first African American woman to earn a pilot's ______ she trained in France because no flight school in the United States would accept her.
    Which choice completes the text so that it conforms to the conventions of Standard English?
    Choose 1 answer:
    A license,
    B license;
    C license
    D license, and
    Check
    Report a problem
    Do 4 problems
    About
    Donate
    """

    /// Khan Academy's text for a bar graph (R&W Module 2, question 12 of a real test), axis ticks echoed after it.
    static let khanBar = """
    Bar graph titled Metal Content of Plants with and without Kanamycin Exposure. The horizontal axis is labeled Experimental condition. 2 data categories are shown. The vertical axis is labeled Metal content, in parts per million. It ranges from 0 to 700 in increments of 100.
    For each data category, the following bars are shown:
    * Zinc
    * Iron
    The data for the 2 categories are as follows:
    Without kanamycin:
    * Zinc: 390
    * Iron: 625
    With kanamycin:
    * Zinc: 300
    * Iron: 225
    \\[0\\]
    \\[100\\]
    \\[200\\]
    \\[300\\]
    \\[400\\]
    \\[500\\]
    \\[600\\]
    \\[700\\]
    Many plants lose their leaf color when exposed to kanamycin, an antibiotic. Researchers measured the zinc and iron in plants grown with and without it and found that kanamycin lowered the amount of both metals.
    """

    /// A table in Khan's words: a "table titled" line, then the rows as copied (tab-separated).
    static let khanTable = """
    A table titled Bird Species Counted in Three City Parks.
    Park\t2015\t2020
    Riverside\t42\t51
    Hilltop\t37\t35
    Lakeview\t29\t40
    A researcher claims that the number of bird species in city parks grew between 2015 and 2020.
    """

    /// A line graph in the same style as the bar graph: each line named, then its points as "* x: y".
    static let khanLine = """
    Line graph titled Average Monthly Rainfall in Two Cities. The horizontal axis is labeled Month. It ranges from 1 to 4 in increments of 1. The vertical axis is labeled Rainfall, in centimeters. It ranges from 0 to 30 in increments of 5.
    2 lines are shown:
    * City A
    * City B
    The data for the 2 lines are as follows:
    City A:
    * 1: 8
    * 2: 14
    * 3: 21
    * 4: 26
    City B:
    * 1: 18
    * 2: 12
    * 3: 9
    * 4: 6
    \\[0\\]
    \\[5\\]
    \\[10\\]
    A student compared rainfall in two cities over four months.
    """

    /// A page with what has tripped the reader: ", like" early in a passage, lines that are only a number, a header with a
    /// tab, "Choose 1 answer" without its colon or as "Choose an answer:", "Question 8 of 27".
    static let khanOdd = """
    Question 5 | Inferences
    A growing number, like the count of new bird species each year, can mislead researchers who expect steady change.
    Which choice most logically completes the text?
    Choose 1 answer:
    A one
    B two
    C three
    D four
    Check
    Question 6\tTransitions
    The railroad reached the town in
    1850
    and the population doubled within a decade. ______ the town's main industry shifted from farming to trade.
    Which choice completes the text with the most logical transition?
    Choose 1 answer
    A Meanwhile,
    B Still,
    C For instance,
    D Likewise,
    Check
    Question 7 — Central ideas and details
    Ants in a colony divide their work by age: younger ants tend the nest while older ones forage.
    Which choice best states the main idea of the text?
    Choose an answer:
    A one
    B two
    C three
    D four
    Hint
    Question 8 of 27 | Boundaries
    The museum's newest exhibit opened in ______ visitors lined up for hours.
    Which choice completes the text so that it conforms to the conventions of Standard English?
    Choose 1 answer:
    A May,
    B May;
    C May
    D May, and
    Check
    Question 9 | Words in context
    An okapi, like a giraffe, has a long tongue.
    Which choice completes the text?
    Choose 1 answer:
    A one
    B two
    C three
    D four
    Check
    """

    /// A Math question whose graph is a picture: only its tick labels come through, one per line, between the stem's lines.
    static let khanGraph = """
    Question 1 | Exponential graphs
    The graph of \\(y=f(x)\\) is shown.
    2
    4
    6
    8
    10
    −4
    −6
    −8
    −10
    O
    y
    x
    Which of the following could be the equation of the graph?
    Choose 1 answer:
    A \\(y=2^x\\)
    B \\(y=-2^x\\)
    C \\(y=2^{-x}\\)
    D \\(y=x^2\\)
    Check
    """

    /// Math Module 1 of the same test: inline choices, a grid-in with Khan's answer-format help, LaTeX choices.
    static let khanMath = """
    SAT Practice Test 4
    Math: Module 1
    Question 1 | Systems of two linear equations in two variables
    y = 2x + 6
    y = −x
    At which point (x, y) do the graphs of the given equations intersect?
    Choose 1 answer:
    A (−14,0)
    B (−2,2)
    C (0,6)
    D (2,10)
    Show calculator
    Check
    Question 2 | Linear equations in one variable
    If 3x + 7 = 22, what is the value of 6x − 4 ?
    Your answer should be
    an integer, like 6
    a simplified proper fraction, like 3/5
    a simplified improper fraction, like 7/4
    a mixed number, like 1 3/4
    an exact decimal, like 0.75
    a multiple of pi, like 12 pi or 2/3 pi
    Check
    Explain
    Question 3 | Graphs of linear systems and inequalities
    Which point lies in the solution region of $y > 2x + 1$?
    Choose 1 answer:
    (A)
    $(0, 0)$
    (B)
    $(1, 3)$
    (C)
    $(2, 2)$
    (D)
    $(-1, 2)$
    Hint
    Report a problem
    Up next
    About
    """

    /// Practice: the skill table, block plans and presets, Math checks, mixed-section scoring, old files, and a full test as a Session.
    static func practiceChecks(_ qs: [PracticeQuestion]) {
        let rw = Practice.rw, math = Sec.math
        do {   // the word before a punctuation blank is not also printed in the passage
            func q(_ p: String, _ c: [String]) -> PracticeQuestion { var x = qs[0]; x.passage = p; x.choices = c; return x }
            let a = q("devices that recur throughout the corpus ______ the prophetic dream.", ["corpus;", "corpus,", "corpus:", "corpus"]).unrepeated()
            let b = q("would benefit amphibians most quickly ______ his first surveys", ["quickly; however,", "quickly, however,", "quickly however,", "quickly, however"]).unrepeated()
            let c = q("the microbes ______ survival.", ["microbes", "microbe's", "microbes'", "microbe"]).unrepeated()   // different words: untouched
            check(a.passage == "devices that recur throughout the ______ the prophetic dream." && b.passage == "would benefit amphibians most ______ his first surveys"
                  && c.passage == "the microbes ______ survival.", "repeated blank word \(a.passage) | \(b.passage) | \(c.passage)")
        }
        let official: [String: [String]] = [
            "Craft and Structure": ["Words in Context", "Text Structure and Purpose", "Cross-Text Connections"],
            "Information and Ideas": ["Central Ideas and Details", "Command of Evidence: Textual", "Command of Evidence: Quantitative", "Inferences"],
            "Standard English Conventions": ["Boundaries", "Form, Structure, and Sense"],
            "Expression of Ideas": ["Transitions", "Rhetorical Synthesis"],
            "Algebra": ["Linear equations in one variable", "Linear functions", "Linear equations in two variables",
                        "Systems of two linear equations in two variables", "Linear inequalities in one or two variables"],
            "Advanced Math": ["Nonlinear functions", "Nonlinear equations in one variable and systems of equations in two variables", "Equivalent expressions"],
            "Problem-Solving and Data Analysis": ["Ratios, rates, proportional relationships, and units", "Percentages",
                                                  "One-variable data: Distributions and measures of center and spread", "Two-variable data: Models and scatterplots",
                                                  "Probability and conditional probability", "Inference from sample statistics and margin of error",
                                                  "Evaluating statistical claims: Observational studies and experiments"],
            "Geometry and Trigonometry": ["Area and volume", "Lines, angles, and triangles", "Right triangles and trigonometry", "Circles"],
        ]
        check((Planner.rwDomains + Planner.mathDomains).allSatisfy { d in Practice.skills(Practice.section(of: d), d).map(\.name) == official[d] }
              && Practice.skills.count == 30 && Practice.skills.allSatisfy { !$0.stems.isEmpty && !$0.form.isEmpty && !$0.choices.isEmpty && !$0.levels.isEmpty },
              "skill table covers every official skill, each with a full spec")
        check(Practice.skills(math).allSatisfy { (0...0.5).contains($0.spr) } && Practice.skills(rw).allSatisfy { $0.spr == 0 }
              && Practice.skills.first { $0.name == "Percentages" }?.spr == 0.5, "grid-in shares per Math skill")

        // Only the batch's own skills and sections go to the writer.
        let wic = Practice.slots(Block(section: rw, domain: "Craft and Structure", skill: "Words in Context", count: 2))
        let sys = Practice.system(wic)
        check(wic.allSatisfy { $0.skill.name == "Words in Context" } && sys.contains("most logical and precise word or phrase")
              && !sys.contains("Rhetorical Synthesis") && !sys.contains("MATH.") && sys.contains("READING AND WRITING."), "writer gets only the batch's skill specs")
        let req = Practice.request(wic, avoid: ["Marine biologist"])
        check(req.contains("1. Reading and Writing · Craft and Structure · Words in Context") && req.contains("correct answer \(wic[0].key)") && req.contains("Marine biologist"), "request lists the plan per question")

        // Presets: a module in official proportions and order.
        let rwMod = Practice.preset("R&W module", [])
        let per = Dictionary(uniqueKeysWithValues: rwMod.map { ($0.domain, $0.count) })
        check(rwMod.map(\.count).reduce(0, +) == 27 && (7...8).contains(per["Craft and Structure"] ?? 0) && (6...8).contains(per["Information and Ideas"] ?? 0)
              && (6...8).contains(per["Standard English Conventions"] ?? 0) && (4...6).contains(per["Expression of Ideas"] ?? 0)
              && rwMod.map(\.domain) == Planner.rwDomains, "R&W module: 27 in official domain shares, in module order")
        let rwSlots = rwMod.flatMap { Practice.slots($0) }
        let runs = rwSlots.map(\.skill.name).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
        let rank = { (d: String) in Practice.tiers.firstIndex(of: d) ?? 0 }
        let grouped = Set(runs).count == runs.count && runs.allSatisfy { n in let t = rwSlots.filter { $0.skill.name == n }.map { rank($0.difficulty) }; return t == t.sorted() }
        check(rwSlots.count == 27 && grouped && runs.first == "Words in Context", "R&W module grouped by skill, each easiest to hardest")
        let mathMod = Practice.preset("Math module", [])
        let mathSlots = mathMod.flatMap { Practice.slots($0) }
        let mathDom = Dictionary(grouping: mathSlots, by: \.skill.domain).mapValues(\.count)
        check(mathSlots.count == 22 && mathSlots.map { rank($0.difficulty) } == mathSlots.map { rank($0.difficulty) }.sorted()
              && mathDom["Algebra"] == 8 && mathDom["Advanced Math"] == 8 && mathDom["Problem-Solving and Data Analysis"] == 3, "Math module: 22, easiest to hardest, official shares")
        let full = Practice.slots(Block(section: math, count: 22), mix: [1, 1, 1])
        let grids = full.filter { $0.key.isEmpty }.count
        let keys = Dictionary(grouping: full.filter { !$0.key.isEmpty }, by: \.key).mapValues(\.count)
        check(full.map { rank($0.difficulty) } == full.map { rank($0.difficulty) }.sorted() && (3...8).contains(grids)
              && keys.values.max()! - keys.values.min()! <= 1 && keys.count == 4, "full-test Math module: easiest first, grid-ins near 26%, keys spread A–D")
        let hard = Practice.slots(Block(section: rw, count: 27), mix: [1, 4, 5]).filter { $0.difficulty == "Hard" }.count
        let easy = Practice.slots(Block(section: rw, count: 27), mix: [5, 4, 1]).filter { $0.difficulty == "Easy" }.count
        check(hard >= 10 && easy >= 10, "Module 2 routes: harder or easier mix")
        let mixed = Practice.preset("Mixed", [])
        check(mixed.map(\.section) == [rw, math] && Practice.label(mixed) == "Reading & Writing, Math" && Practice.label(rwMod) == "Reading & Writing", "mixed preset and set names")

        // Reordering blocks reorders the plan.
        var blocks = [Block(section: rw, domain: "Expression of Ideas", skill: "Transitions", count: 1), Block(section: math, domain: "Algebra", count: 2),
                      Block(section: rw, domain: "Craft and Structure", skill: "Words in Context", count: 1)]
        blocks.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let plan = blocks.flatMap { Practice.slots($0) }.map(\.skill.name)
        check(blocks.map(\.title) == ["Words in Context", "Transitions", "Algebra"] && plan.first == "Words in Context" && plan[1] == "Transitions", "dragging a block moves its questions")

        // From my results: the most-missed skill gets the most questions, difficulty from accuracy.
        var lg = Session(id: "from-results", start: Date()); var o = Official()
        for n in 1...4 { o.answers["R1-\(n)"] = .init(correct: "A", yours: n == 1 ? "A" : "B", domain: "Craft and Structure", skill: "Words in context") }
        for n in 5...6 { o.answers["R1-\(n)"] = .init(correct: "A", yours: n == 5 ? "A" : "C", domain: "Standard English Conventions", skill: "Boundaries") }
        lg.official = o
        let fr = Practice.fromResults([lg])
        check(fr.map(\.skill) == ["Words in Context", "Boundaries"] && fr[0].count > fr[1].count && fr[0].difficulty == "Easy" && fr[1].difficulty == "Medium", "blocks from my results")

        // Math checks in code: numeric choices ascending (the key and notes follow), grid-in length.
        var mq = qs[2]; mq.choices = ["$4$", "$-12$", "$3$", "$-4$"]; mq.correct = "A"; mq.choiceNotes = ["", "y", "s", "n"]
        let up = mq.ascending()
        check(up.choices == ["$-12$", "$-4$", "$3$", "$4$"] && up.correct == "D" && up.choiceNotes == ["y", "n", "s", ""], "numeric choices re-sorted, key remapped")
        var g = qs[3]
        g.correct = "123456"; let long = g.valid
        g.correct = "-12345"; let neg = g.valid
        g.correct = "49/2, 24.5"; let forms = g.valid
        check(!long && neg && forms, "grid-in keys fit 5 characters (6 with a minus sign)")
        var late = qs[1], early = qs[0]
        late.skill = "Form, Structure, and Sense"; early.skill = "Words in Context"; early.difficulty = "Hard"
        var easyMath = qs[2]; easyMath.difficulty = "Easy"
        check(Practice.ordered([late, qs[2], early, easyMath]).map(\.skill) == [qs[2].skill, qs[2].skill, "Words in Context", "Form, Structure, and Sense"]
              && Practice.ordered([qs[2], easyMath]).first?.difficulty == "Easy", "module order: Math easiest first, R&W by skill")

        // Mixed sections: per-section scores and per-question pace.
        var ms = PracticeSet(section: "\(rw) + \(math)", domain: "Mixed", difficulty: "Mixed", asked: 4, questions: qs)
        ms.work[0].answer = "A"; ms.work[1].answer = "C"; ms.work[2].answer = "D"; ms.work[3].answer = "0.75"
        check(ms.sections == [rw, math] && ms.score(rw) == (1, 2) && ms.score(math) == (2, 2) && ms.score == 3 && ms.limit == 71 * 2 + 95 * 2, "mixed-section scoring and pace")

        // Sets saved before blocks, modes and full tests still load.
        let old = #"[{"id":"old","date":"2026-11-05T10:00:00.000Z","section":"Math","domain":"Algebra","difficulty":"Medium","asked":5,"done":true,"questions":[{"section":"Math","domain":"Algebra","skill":"Linear functions","difficulty":"Medium","passage":"","question":"q","choices":["$1$","$2$","$3$","$4$"],"correct":"B","keyPoint":"k","solutionJa":"1. s","trapJa":"t","choiceNotes":["a","","c","d"],"vocab":[],"desmos":[],"desmosFocus":""}],"work":[{"answer":"B","crossed":[],"marked":false,"seconds":42}]}]"#
        let loaded = try? Fmt.decoder.decode([PracticeSet].self, from: Data(old.utf8))
        check(loaded?.first.map { !$0.full && $0.timer == nil && $0.order == [0] && $0.score == 1 && $0.work[0].checked == nil && $0.work[0].highlights == nil } == true, "old practice.json decodes")
        typealias Mark = PracticeSet.Mark
        let hl = [Mark(start: 10, length: 5), Mark(start: 30, length: 10, color: "blue", note: "claim")]
        check(Mark.add(Mark(start: 0, length: 4), to: hl).map(\.start) == [0, 10, 30], "separate highlight is added in order")
        check(Mark.add(Mark(start: 32, length: 3, color: "pink"), to: hl) == hl, "highlight inside a highlight changes nothing")
        check(Mark.add(Mark(start: 12, length: 23, color: "pink"), to: hl) == [Mark(start: 10, length: 30, color: "pink", note: "claim")],
              "overlapping highlights merge into one, keeping the note")
        check(Mark.add(Mark(start: 15, length: 15), to: hl).count == 3, "touching highlights stay separate")
        var hw = PracticeSet.Work(); hw.highlights = hl
        check((try? Fmt.decoder.decode(PracticeSet.Work.self, from: Fmt.encoder.encode(hw))) == hw, "highlights round-trip")
        let gs = MarkedText.groups("Year | Rate\n2020 | 4\nA <u>claim</u> here.\nText 2\n______ ends")
        check(gs.map(\.table) == [true, false] && gs[1].base == 21 && MarkedText.length(gs[1].text) == 32, "passage groups count shown characters")
        let tpl = [Template(name: "Mine", blocks: blocks)]
        check((try? Fmt.decoder.decode([Template].self, from: Fmt.encoder.encode(tpl))) == tpl, "templates round-trip")

        // A full test run becomes a tracked Session.
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var ft = PracticeSet(section: "\(rw) + \(math)", domain: "Full test", difficulty: "Adaptive", asked: 98, questions: qs)
        ft.test = true
        ft.modules = [.init(section: rw, number: 1, first: 0, count: 2), .init(section: rw, number: 2), .init(section: math, number: 1, first: 2, count: 2), .init(section: math, number: 2)]
        ft.work[0].answer = "A"; ft.work[1].answer = "B"; ft.work[1].marked = true; ft.work[2].answer = "D"
        ft.visits = [Visit(section: rw, module: 1, number: 1, start: t0, end: t0 + 60), Visit(section: rw, module: 1, number: 2, start: t0 + 60, end: t0 + 100),
                     Visit(section: rw, module: 1, number: 1, start: t0 + 100, end: t0 + 110), Visit(section: math, module: 1, number: 1, start: t0 + 700, end: t0 + 790)]
        check(Practice.harder(ft, 0) == false && Practice.harder(ft, 2) == false, "Module 1 under 70% takes the easier route")
        ft.work[1].answer = "A"
        check(Practice.harder(ft, 0), "Module 1 at 70% or more takes the harder route")
        ft.work[1].answer = "B"
        let ss = Practice.session(ft)
        check(ss.keys == ["R1-1", "R1-2", "M1-1", "M1-2"] && ss.sections == [rw, math] && ss.modules == [1] && !ss.logged && ss.end == t0 + 790
              && ss.seconds("R1-1") == 70 && ss.seconds("R1-2") == 40 && ss.seconds("M1-1") == 90 && ss.seconds("M1-2") == 0 && ss.visitCount("R1-1") == 2
              && ss.correct("R1-1") == true && ss.correct("R1-2") == false && ss.correct("M1-1") == true && ss.correct("M1-2") == false
              && ss.q["R1-2"]?.flagged == true && ss.q["M1-2"]?.analysis?.verdict == "unanswered" && ss.official?.answers["M1-1"]?.choices?.count == 4
              && ss.topic("M1-1") == "Algebra" && ss.q["R1-1"]?.analysis?.keyPoint == qs[0].keyPoint && ss.test?.hasPrefix("Practice test · ") == true,
              "full test run becomes a Session with visits, answers and explanations")
    }

    /// Practice: block options, the student context, Cancel and a stubbed writer, leaving and restarting a test, the note anchor.
    static func practiceFlowChecks(_ qs: [PracticeQuestion]) {
        let rw = Practice.rw, math = Sec.math
        // Options: the Math format fixes every key; R&W ignores it; the focus note reaches the request once.
        let grid = Practice.slots(Block(section: math, domain: "Algebra", count: 6, format: Practice.grid, focus: "word problems about sports"))
        let mc = Practice.slots(Block(section: math, count: 10, format: Practice.choice))
        let rwGrid = Practice.slots(Block(section: rw, count: 4, format: Practice.grid))
        check(grid.count == 6 && grid.allSatisfy { $0.key.isEmpty && $0.skill.spr > 0 } && mc.allSatisfy { !$0.key.isEmpty } && rwGrid.allSatisfy { !$0.key.isEmpty },
              "question format: all grid-in, all multiple choice, R&W unchanged")
        let gReq = Practice.request(grid, avoid: [])
        check(gReq.components(separatedBy: "word problems about sports").count == 2 && !Practice.request(mc, avoid: []).contains("asked for"), "focus note goes in the request once")
        // The student's data: only sets made from it get it, in a few short lines.
        var lg = Session(id: "context", start: Date()); var o = Official()
        for n in 1...4 { o.answers["R1-\(n)"] = .init(correct: "A", yours: n == 1 ? "A" : "B", domain: "Craft and Structure", skill: "Words in context") }
        lg.official = o
        lg.q["R1-2"] = { var x = QState(); x.causes = ["vocabulary"]; return x }()
        var card = Card(id: "word:tenuous", kind: .word, front: "tenuous", back: "weak"); card.lastReviewed = Date()
        let ctx = Practice.context([lg], cards: [card])
        check(ctx.contains("Craft and Structure 25%") && ctx.contains("Words in Context") && ctx.contains("Didn't know a word 1") && ctx.contains("1 of 4 right")
              && ctx.contains("tenuous") && ctx.count < 700, "student context: weak areas, reasons, vocabulary, short")
        check(Practice.context([], cards: []).isEmpty, "no data, no context")
        check(Practice.fromResults([lg]).allSatisfy { $0.mine == true } && Practice.preset("Mixed", []).allSatisfy { $0.mine == nil }, "blocks from results carry the student's data")

        // Writing with a stubbed model: a written set waits for Start; Cancel stops it and keeps nothing, even after a first batch.
        func spin(_ limit: Double, until done: () -> Bool) {
            let end = Date() + limit
            while !done(), Date() < end { RunLoop.main.run(until: Date() + 0.02) }
        }
        let p = Practice(file: nil)
        p.stub = { batch in Dictionary(uniqueKeysWithValues: batch.indices.map { ($0, qs[0]) }) }
        p.make([Block(section: rw, domain: "Craft and Structure", count: 2)], timer: false)
        let made = p.building
        spin(3) { made.map { p.set($0)?.questions.count == 2 } ?? true }
        let waits = p.open == nil && p.building == made   // written, but it waits for Start instead of opening by itself
        if let made { p.start(made) }
        check(made != nil && waits && p.set(made!)?.questions.count == 2 && p.open == made && p.building == nil, "stubbed writer: set written, opens on Start")
        p.open = nil
        var calls = 0
        p.stub = { batch in
            calls += 1
            if calls > 1 { try await Task.sleep(for: .seconds(30)) }
            return Dictionary(uniqueKeysWithValues: batch.indices.map { ($0, qs[0]) })
        }
        p.make([Block(section: rw, domain: "Craft and Structure", count: 2), Block(section: rw, domain: "Information and Ideas", count: 2)], timer: false)
        let cancelled = p.building!
        spin(3) { calls > 1 }
        let half = p.set(cancelled) != nil
        p.cancel(cancelled)
        spin(0.3) { false }
        check(half && p.building == nil && p.set(cancelled) == nil && p.parts[cancelled] == nil && p.error == nil && p.sets.count == 1 && p.open == nil,
              "Cancel stops writing and keeps no half-written set")

        // Leaving a full test asks first; the page guard keeps the page until it is answered.
        var ft = PracticeSet(section: "\(rw) + \(math)", domain: "Full test", difficulty: "Adaptive", asked: 98, questions: qs)
        ft.test = true; ft.stage = 2; ft.visits = [Visit(section: rw, module: 1, number: 1, start: Date(), end: Date())]; ft.session = "s"; ft.done = true
        ft.modules = [.init(section: rw, number: 1, first: 0, count: 2, used: 900), .init(section: rw, number: 2, hard: true, used: 300),
                      .init(section: math, number: 1, first: 2, count: 2, used: 50), .init(section: math, number: 2)]
        ft.done = false
        p.sets.append(ft); p.open = ft.id
        var ran = false
        check(!p.mayLeave { ran = true } && p.leaving != nil && !ran, "a full test on screen asks before leaving")
        p.leaving?(); p.leaving = nil; p.open = nil
        check(ran && p.mayLeave {}, "leaving goes ahead once answered; nothing to ask with no test open")
        let store = Store.shared, wasNav = store.nav, wasLeave = store.leave
        store.nav = .practice; store.leave = { from, to in to != .plan }
        store.nav = .plan; let held = store.nav
        store.leave = nil; store.nav = .plan; let went = store.nav
        store.leave = wasLeave; store.nav = wasNav
        check(held == .practice && went == .plan, "the page guard keeps the page when asked to")

        // Restart: everything back to zero, Module 1 on screen, questions kept.
        ft.work = ft.work.map { _ in .init(answer: "A", crossed: ["B"], marked: true, seconds: 40, checked: true, highlights: [.init(start: 0, length: 4, note: "n")]) }
        var re = ft; re.restart()
        check(re.work.allSatisfy { $0 == .init() } && re.stage == 0 && re.visits == [] && re.session == nil && !re.done
              && re.modules?.allSatisfy { $0.used == 0 } == true && re.questions == ft.questions && re.modules?[1].hard == true, "restart resets a full test")
        var ps = PracticeSet(section: rw, domain: "x", difficulty: "Medium", asked: 2, questions: Array(qs.prefix(2)))
        ps.work = ps.work.map { _ in .init(answer: "B", crossed: ["A"], marked: true, seconds: 70, checked: true) }; ps.done = true
        ps.restart()
        check(ps.work.allSatisfy { $0 == .init() } && !ps.done && ps.stage == nil && ps.modules == nil, "restart resets practice questions")

        // The note popover points at the highlighted words, even after SwiftUI measured the text at another width.
        let text = "Coastal restoration projects often fail when planners ignore the knowledge of people who have fished there for decades."
        let v = MarkView(usingTextLayoutManager: false)
        v.textContainerInset = .zero; v.textContainer?.lineFragmentPadding = 0; v.gap = 6
        v.textStorage?.setAttributedString(MarkedText(text: text, marks: .constant([]), on: false, color: .constant("yellow")).attributed())
        v.frame = NSRect(x: 0, y: 0, width: 300, height: v.fit(300))
        let line1 = v.anchor(NSRange(location: 0, length: 7))
        _ = v.fit(40)   // a narrow probe, as SwiftUI sends while sizing
        let after = v.anchor(NSRange(location: 0, length: 7))
        let last = v.anchor(NSRange(location: (text as NSString).length - 8, length: 8))
        check(v.isFlipped && line1.minY < 1 && line1.height > 10 && line1.height < 30 && line1.width < 150 && after == line1
              && last.minY > line1.maxY && last.maxY <= v.frame.height + 1, "note popover anchor sits on the highlighted line (\(line1), last \(last))")
    }

    /// A generated practice set as the writer returns it: two Reading and Writing questions, a Math choice question, a grid-in.
    static let practiceFixture = #"""
    {"questions":[
    {"section":"Reading and Writing","domain":"Craft and Structure","skill":"Words in context","difficulty":"Medium",
     "passage":"Marine biologist Lena Ortiz argues that coastal restoration projects succeed only when local communities help plan them. Projects designed far away, she notes, often ______ the knowledge of people who have fished the same waters for generations, and so they miss problems that residents could have pointed out at the start.",
     "question":"Which choice completes the text with the most logical and precise word or phrase?",
     "choices":["overlook","celebrate","duplicate","predict"],"correct":"A",
     "key_point":"The blank must fit the result that comes after \"and so\" in the text",
     "solution":"1. The text says the projects \"miss problems that residents could have pointed out\".\n2. That happens when planners ignore local knowledge.\n3. **Overlook** means fail to notice or use, so it fits.",
     "trap":"\"Predict\" sounds scientific, but nobody predicts knowledge that people already have.",
     "choice_notes":["","Celebrating local knowledge would help the projects, not make them miss problems.","To copy the knowledge would not explain the missed problems.","Knowledge that already exists can't be predicted."],
     "vocab":[{"term":"overlook","meaning":"fail to notice or use"},{"term":"celebrate","meaning":"praise in public"},{"term":"duplicate","meaning":"make an exact copy of"},{"term":"predict","meaning":"say what will happen"}],
     "desmos":[],"desmos_focus":""},
    {"section":"Reading and Writing","domain":"Standard English Conventions","skill":"Form, structure, and sense","difficulty":"Easy",
     "passage":"The Atacama Desert in Chile is one of the driest places on Earth, and some of its weather stations have never recorded rain. Even so, scientists have found tiny ______ living inside its salt rocks, where a thin film of water forms on humid nights.",
     "question":"Which choice completes the text so that it conforms to the conventions of Standard English?",
     "choices":["A) microbes","B) microbe's","C) microbes'","D) microbe"],"correct":"a",
     "key_point":"A plural noun takes no apostrophe unless it owns the word after it.",
     "solution":"1. The word after the blank is \"living\", not something owned.\n2. So no possessive is needed, and \"tiny\" with no \"a\" needs a plural.",
     "trap":"An apostrophe looks careful, but nothing here belongs to the microbes.",
     "choice_notes":["","This shows ownership, but nothing that follows is owned.","This is a plural possessive, and nothing is owned here.","One microbe would need \"a\" before \"tiny\"."],
     "vocab":[{"term":"film","meaning":"a very thin layer"}],"desmos":[],"desmos_focus":""},
    {"section":"Math","domain":"Algebra","skill":"Linear functions","difficulty":"Medium","passage":"",
     "question":"The line $y = 3x - 12$ crosses the $x$-axis at the point $(a, 0)$. What is the value of $a$?",
     "choices":["$-12$","$-4$","$3$","$4$"],"correct":"D",
     "key_point":"A graph crosses the $x$-axis where $y = 0$.",
     "solution":"1. Set $y = 0$: $0 = 3x - 12$.\n2. Add 12 and divide by 3: $x = 4$.",
     "trap":"$-12$ is the $y$-intercept, where the line crosses the $y$-axis instead.",
     "choice_notes":["This is the $y$-intercept, not the $x$-intercept.","This comes from a sign slip when solving $3x = 12$.","This is the slope of the line.",""],
     "vocab":[{"term":"x-axis","meaning":"the flat number line across a graph"},{"term":"the value of","meaning":"the number something works out to"}],
     "desmos":["y=3x-12"],"desmos_focus":"(4,0)"},
    {"section":"Math","domain":"Problem-Solving and Data Analysis","skill":"Ratios, rates, and proportions","difficulty":"Medium",
     "passage":"A recipe uses 3 cups of flour for every 4 cups of milk.",
     "question":"How many cups of flour does the recipe use for each cup of milk?",
     "choices":[],"correct":"3/4",
     "key_point":"A rate \"for each\" unit is the first amount divided by the second.",
     "solution":"1. Divide flour by milk: $\\frac{3}{4}$.\n2. So each cup of milk takes $\\frac{3}{4}$ cup of flour.",
     "trap":"Dividing the other way gives $\\frac{4}{3}$, the milk for each cup of flour.",
     "choice_notes":[],"vocab":[{"term":"for each","meaning":"for every one"}],"desmos":[],"desmos_focus":""}
    ]}
    """#
}

extension NSView {
    func firstSubview<T: NSView>(of: T.Type) -> T? {
        for v in subviews { if let t = v as? T ?? v.firstSubview(of: T.self) { return t } }
        return nil
    }
}

// MARK: - Study plan engine

extension SelfTest {
    /// The plan engine on a fixed calendar: the real case (sat Nov 7 2026, booked Dec 5, Mon–Thu + Sat, 60 min,
    /// target 1400, latest practice 1330), the research rules (R1–R14), missed days, suggestions, notifications, migration.
    static func engineChecks() {
        let cal = Calendar.current
        func at(_ m: Int, _ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))! }
        func gap(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day! }
        func on(_ plan: [StudyDay], _ m: Int, _ d: Int) -> StudyDay? { plan.first { cal.isDate($0.date, inSameDayAs: at(m, d)) } }
        func tests(_ plan: [StudyDay]) -> [Date] { plan.filter { $0.tasks.contains { $0.kind == .test } }.map(\.date) }
        let nov7 = at(11, 7)
        guard let dec5 = SATDates.all.map(\.date).first(where: { cal.isDate($0, equalTo: at(12, 1), toGranularity: .month) }) else { return check(false, "plan: a December 2026 SAT date") }
        check(cal.component(.day, from: dec5) == 5, "plan: the December 2026 SAT is Dec 5")

        // The fixture: SAT Practice 9 logged Oct 31 (1330: R&W 620, Math 710), most misses in Craft and Structure and Advanced Math.
        var p9 = Session(id: "fixture-p9", start: at(10, 31, 9), end: at(10, 31, 12), test: "SAT Practice 9")
        var o = Official(); o.total = 1330; o.readingWriting = 620; o.math = 710
        for (sec, mods, n, doms) in [("R", 2, 27, Planner.rwDomains), ("M", 2, 22, Planner.mathDomains)] {
            for m in 1...mods { for q in 1...n {
                let i = (m - 1) * n + q, dom = doms[i % doms.count]
                let miss = (dom == "Craft and Structure" && i % 2 == 0) || (dom == "Advanced Math" && i % 3 == 0) || i % 13 == 0
                o.answers["\(sec)\(m)-\(q)"] = .init(correct: "", yours: nil, domain: dom, skill: Practice.skills(sec == "R" ? Practice.rw : Sec.math, dom).first?.name,
                                                     difficulty: ["Easy", "Medium", "Hard"][i % 3], right: !miss)
            } }
        }
        p9.official = o
        var p = Profile(); p.days = [2, 3, 4, 5, 7]; p.minutes = 60; p.targetScore = 1400
        let nov = Sitting(date: cal.startOfDay(for: nov7)), dec = Sitting(date: dec5)
        p.sittings = [nov, dec]
        let mastery = Mastery(sessions: [p9], today: nov7)
        let base = Planner.baseline(p, sessions: [p9], today: nov7)
        check(base?.total == 1330 && base?.rw == 620 && base?.math == 710 && base?.source == "SAT Practice 9", "plan: baseline is the latest practice score")
        func input(_ p: Profile, _ now: Date, tests t: [Planner.TestDone]? = nil, due: [Date] = [], new: Int = 12, studied: Int = 0) -> Planner.Input {
            Planner.Input(profile: p, today: now, tests: t ?? Planner.tests([p9]), mastery: mastery, baseline: base?.total, cardsDue: due, cardsNew: new, cardsStudiedToday: studied)
        }

        // Sittings: Nov 7 is today (countdown "Today"), the plan already targets Dec 5; the day after, Nov 7 asks for its score.
        check(p.nextSitting(nov7)?.id == nov.id && p.goal(nov7).sitting?.id == dec.id && p.goal(nov7).booked && p.needsScore(nov7).isEmpty, "sittings: a sitting today is today, the plan targets the next")
        check(p.needsScore(at(11, 8)).map(\.id) == [nov.id] && p.nextSitting(at(11, 8))?.id == dec.id, "sittings: Nov 7 passed needs its score, Dec 5 is next")
        var snoozed = p; snoozed.sittings[0].snoozedUntil = at(11, 15, 0)
        check(snoozed.needsScore(at(11, 14)).isEmpty && snoozed.needsScore(at(11, 15)).count == 1, "sittings: Not out yet asks again 7 days later")
        var scored = p; scored.sittings[0].rw = 640; scored.sittings[0].math = 720
        check(scored.needsScore(at(11, 8)).isEmpty && Planner.baseline(scored, sessions: [p9], today: at(11, 8))?.total == 1360, "sittings: an official score becomes the baseline")
        var none = Profile(); none.sittings = []
        let open = none.goal(nov7)
        check(!open.booked && gap(nov7, open.date) >= 56 && SATDates.all.contains { cal.isDate($0.date, inSameDayAs: open.date) }, "sittings: nothing booked plans toward an official date 8+ weeks out")

        let plan = Planner.make(input(p, nov7))
        let ahead = plan.filter { $0.date >= cal.startOfDay(for: nov7) }
        check(on(plan, 11, 7) == nil, "plan: nothing on the sitting day")
        check(ahead.last.map { cal.isDate($0.date, inSameDayAs: at(12, 4)) && $0.tasks.map(\.kind) == [.rest] } == true, "plan: the day before the sitting is rest")
        check(!ahead.contains { $0.date >= dec5 }, "plan: ends before Dec 5")
        let full = tests(plan)
        check(full.count == 1 && cal.isDate(full[0], inSameDayAs: at(11, 21)) && on(plan, 11, 21)?.tasks.first?.test == "SAT Practice 4",
              "plan: one full test, SAT Practice 4 on Sat Nov 21 (14 days after the SAT, 14 before Dec 5)")
        check(on(plan, 11, 21)?.tasks.count == 1 && on(plan, 11, 21)?.tasks.first?.minutes == 135 && on(plan, 11, 21)?.tasks.first?.detail.contains("Longer than your usual 60 min") == true,
              "plan: a full test takes the day, 2 h 15, noted when longer than the usual session")
        check(on(plan, 11, 9)?.tasks.first.map { $0.kind == .review && $0.target == .review("fixture-p9") } == true, "plan: SAT Practice 9 reviewed on the first study day")
        check(plan.flatMap(\.tasks).count { $0.target == .review("fixture-p9") } == 1, "plan: one review per test")
        check(on(plan, 11, 23)?.tasks.first.map { $0.kind == .review && $0.title == "Review SAT Practice 4" } == true, "plan: review within 2 days of the full test")
        check(on(plan, 11, 9)?.tasks.contains { $0.kind == .cards && $0.count == 12 && $0.title == "Redo misses" } == true, "plan: redo task carries the cards due")
        check(ahead.allSatisfy { $0.tasks.reduce(0) { $0 + $1.minutes } <= 60 || $0.tasks.contains { $0.kind == .test } }, "plan: study days fit 60 min")
        check(ahead.allSatisfy { d in p.days.contains(cal.component(.weekday, from: d.date)) || d.tasks.allSatisfy { $0.kind == .rest } }, "plan: only study days, plus the eve")
        let taper = ahead.filter { $0.date >= at(11, 28, 0) && $0.tasks.contains { $0.kind != .rest } }
        check(!taper.isEmpty && taper.allSatisfy { $0.phase == .taper && !$0.tasks.contains { [.drill, .test, .words].contains($0.kind) } }
              && taper.flatMap(\.tasks).count { $0.kind == .module } == 1, "plan: final week: no new topics, no full test, one timed module")
        let modules = ahead.flatMap(\.tasks).filter { $0.kind == .module }.map(\.target)
        check(modules.count >= 4 && zip(modules, modules.dropFirst()).allSatisfy { $0 != $1 } && modules.first == .module(Practice.rw), "plan: timed modules alternate R&W and Math")
        let drills = ahead.flatMap(\.tasks).filter { $0.kind == .drill }
        check(!drills.isEmpty && drills.allSatisfy { (20...30).contains($0.minutes) && ($0.blocks?.count ?? 0) >= 1 && !$0.why.isEmpty }, "plan: drills are 20–30 min Practice sets with a reason")
        check(Set(drills.prefix(2).map(\.title)).count == 2 && drills.first?.blocks.map { Set($0.map(\.skill)).count == 2 } == true, "plan: two skills per drill, rotating")
        let rank = mastery.ranking(target: 1400)
        check(["Craft and Structure", "Advanced Math"].contains(rank.first?.domain ?? ""), "mastery: the most missed weighted domains rank first")
        check(ahead.flatMap(\.tasks).allSatisfy { !$0.short.isEmpty } && on(plan, 11, 9)?.tasks.first?.short == "Review SAT Practice 9" && on(plan, 11, 21)?.tasks.first?.short == "SAT Practice 4", "plan: short titles for pills")
        check(Planner.phases(ahead).map(\.phase) == [.practice, .taper], "plan: phases 4 weeks out are practice tests, then the final week")

        // Stable ids: the same inputs keep every id; a new minutes setting keeps the ids of tasks still planned.
        let again = Planner.make(input(p, nov7), old: plan)
        check(again.flatMap(\.tasks).map(\.id) == plan.flatMap(\.tasks).map(\.id), "plan: re-planning keeps task ids")
        var p90 = p; p90.minutes = 90
        let more = Planner.make(input(p90, nov7), old: plan)
        check(on(more, 11, 21)?.tasks.first?.id == on(plan, 11, 21)?.tasks.first?.id && on(more, 11, 9)?.tasks.first?.id == on(plan, 11, 9)?.tasks.first?.id, "plan: a re-plan keeps ids of tasks still planned")

        // Days go by. Nov 9 done, Nov 10 missed: Nov 11 brings the review and the cards forward, drops the missed drills, keeps rotating.
        var lived = plan
        for i in lived.indices where cal.isDate(lived[i].date, inSameDayAs: at(11, 9)) { for j in lived[i].tasks.indices where lived[i].tasks[j].kind != .review { lived[i].tasks[j].done = true } }
        let nov10 = Planner.make(input(p, at(11, 10)), old: lived)
        check(on(nov10, 11, 10)?.tasks.first?.target == .review("fixture-p9") && on(nov10, 11, 9)?.tasks.contains { $0.missed && $0.kind == .review } == true,
              "plan: an unfinished review moves to the next study day")
        // Rotation: with Nov 9–10 done, the drills from Nov 11 go on where the plan was, not back to the top pair.
        var twoDays = plan
        for i in twoDays.indices where twoDays[i].date < at(11, 11, 0) { for j in twoDays[i].tasks.indices { twoDays[i].tasks[j].done = true } }
        let drillsFrom = { (pl: [StudyDay]) in pl.filter { $0.date >= at(11, 11, 0) }.flatMap(\.tasks).filter { $0.kind == .drill }.map(\.title) }
        let rotated = drillsFrom(Planner.make(input(p, at(11, 11), new: 0), old: twoDays))
        check(on(plan, 11, 10)?.tasks.contains { $0.kind == .drill } == true && rotated == drillsFrom(plan) && rotated != drillsFrom(Planner.make(input(p, at(11, 11), new: 0))),
              "plan: drill rotation carries on across days")
        let nov11 = Planner.make(input(p, at(11, 11), due: [at(11, 10, 0)], new: 0), old: nov10)
        let t11 = on(nov11, 11, 11)?.tasks ?? []
        check(t11.first.map { $0.target == .review("fixture-p9") && $0.carried } == true && on(nov11, 11, 10)?.tasks.allSatisfy { $0.missed } == true, "plan: a missed review is carried until done")
        check(t11.contains { $0.kind == .cards && $0.carried } && !t11.contains { $0.kind == .drill && $0.carried } && t11.reduce(0) { $0 + $1.minutes } <= 60, "plan: missed cards carry, missed drills are dropped, no pile-up")
        // A review is done once every miss has a reason (or ticked).
        let reviewed = Planner.tests([p9]).map { var t = $0; t.unreviewed = 0; return t }
        check(Planner.make(input(p, at(11, 11), tests: reviewed), old: nov10).filter { $0.date >= at(11, 11, 0) }.flatMap(\.tasks).allSatisfy { $0.target != .review("fixture-p9") || $0.done },
              "plan: review done when every miss has a reason")
        // A missed full test moves to the next allowed weekend, keeping the spacing and the final 6 days clear.
        let nov23 = Planner.make(input(p, at(11, 23)), old: plan)
        check(on(nov23, 11, 21)?.tasks.first?.missed == true && tests(nov23.filter { $0.date >= at(11, 23, 0) }).map { cal.startOfDay(for: $0) } == [cal.startOfDay(for: at(11, 28))],
              "plan: a missed full test moves to Sat Nov 28 (7 days out)")
        // The test is taken: its task ticks itself; today's finished tasks never change.
        var took = Planner.tests([p9]); took.append(.init(id: "p4", name: "SAT Practice 4", date: at(11, 21, 15), misses: 20, unreviewed: 20))
        let after = Planner.make(input(p, at(11, 21, 18), tests: took), old: plan)
        check(on(after, 11, 21)?.tasks.map(\.kind) == [.test] && on(after, 11, 21)?.tasks.first?.done == true, "plan: a taken test is done and the day stays as planned")
        check(on(after, 11, 23)?.tasks.first?.target == .review("p4"), "plan: the review targets the test taken")
        // Ticked as taken with no results in the app: nothing to review, so no review for it, that day or later.
        var ticked4 = plan
        for i in ticked4.indices where cal.isDate(ticked4[i].date, inSameDayAs: at(11, 21)) { ticked4[i].tasks[0].done = true }
        let tickedDay = Planner.make(input(p, at(11, 21, 18)), old: ticked4), tickedLater = Planner.make(input(p, at(11, 23)), old: tickedDay)
        check(on(plan, 11, 23)?.tasks.contains { $0.title == "Review SAT Practice 4" } == true
              && !(tickedDay + tickedLater).contains { $0.date > at(11, 21, 23) && $0.tasks.contains { $0.title == "Review SAT Practice 4" } }, "plan: no review for a test ticked with no results in the app")
        // Not booked (aiming 8+ weeks out): the drills mix R&W and Math by priority, and timed modules come in skill building too.
        var loose = p; loose.sittings = [nov]
        let far = Planner.make(input(loose, at(11, 9))).filter { $0.date >= at(11, 9, 0) }
        let farBlocks = far.prefix(6).flatMap(\.tasks).flatMap { $0.blocks ?? [] }
        check(!loose.goal(at(11, 9)).booked && Set(farBlocks.map(\.section)) == [Practice.rw, Sec.math]
              && far.filter { $0.phase == .build }.flatMap(\.tasks).contains { $0.kind == .module }, "plan: not booked, drills interleave both sections and modules come before the last 4 weeks")
        // Cards studied today tick the redo task.
        let cardsDone = Planner.make(input(p, at(11, 9, 18), new: 0, studied: 12), old: plan)
        check(on(cardsDone, 11, 9)?.tasks.first { $0.kind == .cards }?.done == true, "plan: redo done when today's cards are studied")

        // R1: no score yet → the first study day is a full test (diagnostic).
        var fresh = Profile(); fresh.sittings = [Sitting(date: SATDates.all.map(\.date).first { gap(nov7, $0) > 100 }!)]
        let diag = Planner.make(Planner.Input(profile: fresh, today: at(11, 9)))
        check(diag.first?.phase == .diagnose && diag.first?.tasks.first?.kind == .test && diag.first?.tasks.first?.why.contains("No score yet") == true, "plan: diagnostic when there is no baseline")
        check(Planner.phases(diag).map(\.phase) == [.diagnose, .build, .practice, .taper], "plan: diagnose, build, practice tests, final week")
        // Spacing for every distance to the sitting: ≥14 days (≥7 under 4 weeks), never in the final 6 days, last ≥14 days out when possible.
        var every = Profile(); every.days = Set(1...7)
        for lead in 2...120 {
            every.sittings = [Sitting(date: cal.date(byAdding: .day, value: lead, to: cal.startOfDay(for: at(11, 9)))!)]
            let pl = Planner.make(Planner.Input(profile: every, today: at(11, 9), baseline: 1200))
            let ts = tests(pl), end = every.sittings[0].date
            if !(ts.allSatisfy { gap($0, end) >= 7 } && zip(ts, ts.dropFirst()).allSatisfy { gap($0, $1) >= (gap($0, end) < 28 ? 7 : 14) } && (ts.last.map { gap($0, end) >= 14 || ts.count == 1 } ?? true)
                 && ts.allSatisfy { [1, 7].contains(cal.component(.weekday, from: $0)) }) {
                return check(false, "plan: test spacing at \(lead) days out: \(ts.map { gap($0, end) })")
            }
        }
        check(true, "plan: test spacing and final-week rule for 2–120 days out")
        var short = Profile(); short.sittings = [Sitting(date: at(11, 15, 0))]
        check(tests(Planner.make(Planner.Input(profile: short, today: at(11, 9)))).isEmpty, "plan: no diagnostic in the final 6 days")

        // Feasibility from PrepScholar's table (R2).
        check([0, 30, 31, 70, 71, 130, 131, 200, 201].map { Planner.hours(gap: $0) } == [0, 10, 20, 20, 40, 40, 80, 80, 150], "plan: hours by gain")
        let f = Planner.feasibility(p, baseline: 1330, days: ahead, today: nov7)
        check(f.gap == 70 && f.neededHours == 20 && f.weeks == 4 && f.budgetPerWeek == 5 && f.neededPerWeek == 5 && f.status != .unknown, "plan: 70 points need 20 h, 5 h a week")
        var high = p; high.targetScore = 1600
        let hf = Planner.feasibility(high, baseline: 1330, days: ahead, today: nov7)
        check(hf.status == .notEnough && hf.neededHours == 150, "plan: 1600 from 1330 is not enough in 4 weeks")
        check(Planner.feasibility(p, baseline: nil, days: ahead, today: nov7).status == .unknown, "plan: no score, no verdict")

        // Suggestions, one per trigger.
        func advise(_ p: Profile, _ now: Date, baseline: Planner.Baseline? = base, history: [StudyDay] = [], days: [StudyDay]? = nil, mastery m: Mastery = mastery) -> [Suggestion] {
            let d = days ?? ahead
            return Adviser.make(.init(profile: p, today: now, baseline: baseline, feasibility: Planner.feasibility(p, baseline: baseline?.total, days: d, today: now),
                                      history: history, days: d, mastery: m))
        }
        let s8 = advise(p, at(11, 8))
        check(s8.contains { $0.kind == .askScore && $0.sitting == nov.id && $0.title == "How did Nov 7 go?" }, "suggest: a passed sitting asks for its score")
        check(s8.contains { $0.kind == .info && $0.trigger == "rank:fixture-p9" && $0.title.hasPrefix("Priorities: ") }, "suggest: a new score re-ranks the priorities")
        // One priority list: the suggestion names the same 4 the drills work on (and Today, Plan, Tutor show), two per section (R10).
        let pri = mastery.priorities(target: p.targetScore)
        let drilled = Set(ahead.flatMap(\.tasks).flatMap { $0.blocks ?? [] }.map { $0.skill.isEmpty ? $0.domain : $0.skill })
        let ranked = mastery.ranking(target: p.targetScore).filter { $0.seen == 0 || $0.right < $0.seen }
        check(pri.count == 4 && [Practice.rw, Sec.math].allSatisfy { s in pri.count { $0.section == s } >= min(2, ranked.count { $0.section == s }) }
              && !(pri.contains { $0.seen > 0 && $0.right == $0.seen } && ranked.contains { a in !pri.contains { $0.id == a.id } })
              && s8.contains { $0.trigger == "rank:fixture-p9" && $0.title == "Priorities: " + pri.map(\.short).joined(separator: ", ") }
              && drilled == Set(pri.map { $0.skill ?? $0.domain }), "priorities: one list of 4, missed skills before all-right ones, two per section where it has two, in the suggestion and the drills")
        let sh = advise(high, at(11, 8), days: Planner.make(input(high, at(11, 8))).filter { $0.date >= at(11, 8, 0) })
        check(sh.contains { $0.kind == .change && $0.trigger.hasPrefix("hours:") && !$0.changes.isEmpty }, "suggest: hours short by 25%+ → more time or a later date")
        let missedWeek = Planner.make(input(p, at(11, 14)), old: plan).filter { $0.date < at(11, 14, 0) }
        check(advise(p, at(11, 14), history: missedWeek).contains { $0.trigger.hasPrefix("missed:") && $0.changes == [.minutes(45)] }, "suggest: 2+ missed study days → a lighter day")
        var strong = Session(id: "strong", start: at(11, 5, 9), end: at(11, 5, 10), test: "Algebra set")
        var so = Official(); for q in 1...12 { so.answers["M1-\(q)"] = .init(correct: "", yours: nil, domain: "Algebra", right: true) }
        strong.official = so
        let mm = Mastery(sessions: [strong], today: nov7)
        check(mm.mastered.map(\.id) == ["Algebra"] && !mm.ranking().contains { $0.domain == "Algebra" }, "mastery: 12 of 12 lately is mastered and out of the drills")
        check(advise(p, at(11, 8), mastery: mm).contains { $0.trigger == "mastered:Algebra" && $0.kind == .info }, "suggest: a mastered skill is announced")
        var used = Profile(); used.days = Set(1...7); used.sittings = [Sitting(date: SATDates.all.map(\.date).first { gap(nov7, $0) > 100 }!)]
        used.priorScores = TestChoice.bluebook.map { PriorScore(kind: .bluebook, date: at(10, 1), testName: $0, total: 1300) }
        let outPlan = Planner.make(Planner.Input(profile: used, today: nov7, baseline: 1300))
        check(outPlan.contains { $0.tasks.contains { $0.target == .appTest } } && advise(used, nov7, days: outPlan).contains { $0.trigger.hasPrefix("bluebook-out:") },
              "suggest: Bluebook tests used up → in-app full tests")
        var few = p; few.days = [2, 4]; few.targetScore = 1500
        check(advise(few, at(11, 8)).contains { $0.trigger.hasPrefix("days:") && $0.changes == [.days([2, 4, 7])] }, "suggest: fewer than 4 days with a big gap → add Saturday")
        check(advise(high, nov7, days: Planner.make(input(high, nov7)).filter { $0.date >= nov7 }).allSatisfy { $0.kind == .askScore }
              && advise(high, at(11, 30)).allSatisfy { $0.kind == .askScore }, "suggest: nothing to change on a sitting day or in the final week")
        var moved = p
        PlanChange.moveSitting(id: dec.id, to: SATDates.all[2].date).apply(&moved)
        check(moved.sittings.count == 2 && moved.sittings.last?.id == dec.id && cal.isDate(moved.sittings.last!.date, inSameDayAs: SATDates.all[2].date), "suggest: moving a sitting keeps the others")

        // A waiting suggestion reads the numbers of today, not of the day it was raised.
        let days15 = Planner.make(input(high, at(11, 15))).filter { $0.date >= at(11, 15, 0) }
        let f15 = Planner.feasibility(high, baseline: base?.total, days: days15, today: at(11, 15))
        var log = advise(high, at(11, 8), days: Planner.make(input(high, at(11, 8))).filter { $0.date >= at(11, 8, 0) }).filter { $0.trigger.hasPrefix("hours:") }
        check(Adviser.update(&log, from: advise(high, at(11, 15), days: days15)) && log.first?.why.hasPrefix("\(Int(f15.neededPerWeek.rounded())) h a week") == true,
              "suggest: a waiting suggestion's hours match today's Needs figure (\(log.first?.why ?? ""))")

        // Redo: each redo counts the cards due since the one before; a ticked redo's cards are not due again the next day.
        let due15 = Array(repeating: at(11, 1, 0), count: 12) + [at(11, 12, 0), at(11, 12, 0), at(11, 18, 0)]
        let rp = Planner.make(input(p, nov7, due: due15, new: 0))
        let counts = rp.flatMap { $0.tasks.filter { $0.kind == .cards }.map { $0.count ?? 0 } }
        check(counts.first == 12 && counts.dropFirst().allSatisfy { $0 < 12 } && counts.reduce(0, +) == 15, "plan: redo counts go down as earlier redos clear cards (\(counts))")
        var redone = rp
        for i in redone.indices where cal.isDate(redone[i].date, inSameDayAs: at(11, 9)) { for j in redone[i].tasks.indices { redone[i].tasks[j].done = true } }
        let after9 = Planner.make(input(p, at(11, 10), due: due15, new: 0), old: redone)
        check(on(after9, 11, 9)?.tasks.first { $0.kind == .cards }?.count == 12 && on(after9, 11, 10)?.tasks.contains { $0.kind == .cards } != true, "plan: a ticked redo keeps its count and is not due again the next day")

        // Stability (R14): a student who does each day's tasks sees every day ahead stay as planned, day after day.
        // A full test is taken in the app (its results in, as many misses as the one before), so its planned review stays.
        var kept = Planner.make(input(p, at(11, 8), due: due15, new: 0)), shifted: [String] = [], taken = Planner.tests([p9])
        for n in 8..<34 {
            let now = cal.date(byAdding: .day, value: n - 8, to: at(11, 8))!, next = cal.date(byAdding: .day, value: 1, to: now)!
            for i in kept.indices where cal.isDate(kept[i].date, inSameDayAs: now) { for j in kept[i].tasks.indices where kept[i].tasks[j].kind != .rest {
                kept[i].tasks[j].done = true
                if let t = kept[i].tasks[j].test { taken.append(.init(id: "taken-" + t, name: t, date: now, misses: taken[0].misses, unreviewed: taken[0].misses)) }
            } }
            let made = Planner.make(input(p, next, tests: taken, due: due15, new: 0), old: kept)
            let ahead = { (pl: [StudyDay]) in pl.filter { $0.date >= cal.startOfDay(for: next) }.map { Planner.day.string(from: $0.date) + " " + $0.tasks.map { "\($0.title) \($0.minutes)" }.joined(separator: ", ") } }
            if ahead(made) != ahead(kept) { shifted.append(Planner.day.string(from: next)) }
            kept = made
        }
        check(shifted.isEmpty, "plan: a new day with nothing new keeps every day ahead and the week's minutes as planned \(shifted)")

        // Drills follow the priority order: #1 in the most blocks, and the day's first block has it when there are two.
        let drillTasks = ahead.flatMap(\.tasks).filter { $0.kind == .drill }
        let uses = mastery.priorities(target: 1400).map { a in drillTasks.count { $0.blocks?.contains { ($0.skill.isEmpty ? $0.domain : $0.skill) == (a.skill ?? a.domain) } == true } }
        check(uses.count == 4 && uses[0] >= uses.max()! && uses[0] > uses[3]
              && ahead.allSatisfy { d in let dr = d.tasks.filter { $0.kind == .drill }; return dr.count < 2 || dr[0].title.contains(rank[0].short) }, "plan: drill blocks follow the priority order \(uses)")

        // Full tests card: a sitting waiting for its score and the nearest ahead and behind stay; the far ends go first.
        func ft(_ m: Int, _ d: Int, _ y: Int = 2026, pending: Bool = false) -> FullTest { FullTest(date: cal.date(from: DateComponents(year: y, month: m, day: d))!, name: "\(m)/\(d)", note: "", kind: .planned, pending: pending) }
        let list = [ft(11, 4), ft(11, 5), ft(11, 21), ft(12, 5, pending: true), ft(12, 19), ft(1, 2, 2027), ft(2, 20, 2027), ft(3, 6, 2027)]
        check(TestsCard.keep(list, 3, today: cal.startOfDay(for: at(12, 7))).map(\.name) == ["11/21", "12/5", "12/19"]
              && TestsCard.keep(list, 5, today: cal.startOfDay(for: at(12, 7))).map(\.name) == ["11/5", "11/21", "12/5", "12/19", "1/2"], "full tests: the rows nearest today are kept")

        // Notifications for a sample week (nothing reaches the system under SAT_DATA).
        check(Notifier.offline, "notify: test runs never touch real notifications")
        var np = p; np.reminders = true
        check(Notifier.requests(p, days: plan, suggestions: [], now: at(11, 8, 8)).isEmpty, "notify: off until the student turns reminders on")
        let week = Notifier.requests(np, days: plan, suggestions: s8, now: at(11, 8, 8))
        let study = week.filter { $0.id.hasPrefix("sat.study.") }
        check(study.map { cal.component(.day, from: $0.date) } == [9, 10, 11, 12, 14] && study.allSatisfy { cal.component(.hour, from: $0.date) == 17 && $0.title == "Today's session" },
              "notify: one 17:00 reminder per study day, none on Friday or Sunday")
        check(study.first?.body.hasPrefix("Review SAT Practice 9 · Redo 12 misses · ") == true && study.first?.body.hasSuffix(" · \(on(plan, 11, 9)!.minutes) min") == true, "notify: the body lists the day's tasks and minutes: \(study.first?.body ?? "")")
        check(week.contains { $0.id == "sat.after.\(nov.id)" && $0.title == "How did your SAT go?" && cal.component(.hour, from: $0.date) == 9 && $0.body.contains("Dec 5") }, "notify: the morning after a sitting asks for the score")
        var done9 = plan
        for i in done9.indices where cal.isDate(done9[i].date, inSameDayAs: at(11, 9)) { for j in done9[i].tasks.indices { done9[i].tasks[j].done = true } }
        check(!Notifier.requests(np, days: done9, suggestions: [], now: at(11, 8, 8)).contains { $0.id == "sat.study.2026-11-09" }, "notify: quiet once the day's session is done")
        var fri = np; fri.days.insert(6)
        let friPlan = Planner.make(input(fri, nov7))
        check(Notifier.requests(fri, days: friPlan, suggestions: [], now: at(11, 15, 8)).contains { $0.id == "sat.study.2026-11-20" && $0.title == "Tomorrow: SAT Practice 4" && $0.body.contains("2 h 15") },
              "notify: the eve of a full test replaces the daily reminder")
        let eve = Notifier.requests(np, days: plan, suggestions: [], now: at(11, 30, 8))
        check(eve.contains { $0.title == "SAT tomorrow" && cal.isDate($0.date, inSameDayAs: at(12, 4)) && cal.component(.hour, from: $0.date) == 19 }, "notify: the evening before the sitting")
        check(!eve.contains { cal.isDate($0.date, inSameDayAs: at(12, 4)) && $0.id.hasPrefix("sat.study.") }, "notify: no study reminder on the rest day")
        var sn = np; sn.sittings[0].snoozedUntil = at(11, 14, 0)
        check(Notifier.requests(sn, days: plan, suggestions: [], now: at(11, 9, 8)).contains { $0.title == "Is your Nov 7 score out?" && cal.isDate($0.date, inSameDayAs: at(11, 14)) }, "notify: asks again when a snooze ends")
        let change = Suggestion(kind: .change, trigger: "x", title: "Study 90 min a day?", why: "Needs 11 h a week.")
        check(Notifier.requests(np, days: plan, suggestions: [change], now: at(11, 8, 8)).contains { $0.title == "Plan change" && cal.isDate($0.date, inSameDayAs: at(11, 9)) }, "notify: a new suggestion at the next study-day reminder")

        // Start opens each task's feature in the app; a practice task reads Continue while its set from today is open.
        do {
            let st = Store.shared, pr = Practice(file: nil)
            Actions.start(StudyTask(kind: .cards, title: "Redo misses", detail: "", minutes: 10, target: .cards))
            check(st.nav == .cards && UserDefaults.standard.string(forKey: "cardsDeck") == Card.Kind.mistake.rawValue, "start: redo opens the mistakes deck")
            Actions.start(StudyTask(kind: .words, title: "Words", detail: "", minutes: 10, target: .words))
            check(st.nav == .vocab, "start: words opens Words")
            let drill = Planner.drill([Mastery.Area(domain: "Algebra")], minutes: 20, high: true)
            let blocks = drill.blocks ?? []
            check(!blocks.isEmpty && pr.current(blocks) == nil, "start: no set open for a new drill")
            var set = PracticeSet(section: Sec.math, domain: Practice.label(blocks), difficulty: "Mixed", asked: 2, questions: [])
            pr.drafts[set.id] = set
            check(pr.current(blocks) == set.id && pr.current(Practice.preset("Math module", [])) == nil, "start: the drill's set from today is found again (Continue)")
            set.done = true; pr.drafts[set.id] = set
            check(pr.current(blocks) == nil, "start: a finished set starts a new one")
            st.nav = .today
            let fl = PlanTimeline.flags([0, 30, 200, 395], ["P4 · Nov 21", "P5 · Nov 28", "P6 · Dec 19", "P7 · Jan 2"], width: 400)
            check(fl == [0: true, 2: true, 3: true], "timeline: a flag that would sit on a label is left out, the last label stays inside")
            for (xs, w) in [([0, 250, 330], 376), ([0, 400, 600], 682), ([0, 20], 376)] as [([CGFloat], CGFloat)] {
                let names = ["Build", "Practice tests", "Final week"].prefix(xs.count)
                let lx = PlanTimeline.labels(Array(zip(xs, names)).map { ($0, $1) }, width: w)
                let shown = zip(lx, names).compactMap { x, n in x.map { ($0, $0 + CGFloat(n.count) * 6.5) } }
                check(lx.first! != nil && lx.last! != nil && zip(shown, shown.dropFirst()).allSatisfy { $0.1 + 12 <= $1.0 } && shown.allSatisfy { $0.0 >= 0 && $0.1 <= w },
                      "timeline: phase names never overlap and stay in the track (\(lx))")
            }
        }

        // Migration: old profile.json (one testDate or a targetMonth) and done.json load without loss.
        func decode(_ json: String) -> Profile? { try? Fmt.decoder.decode(Profile.self, from: Data(json.utf8)) }
        let old = decode(#"{"days":[2,3,4,5,7],"focus":[],"grade":11,"minutes":60,"name":"Ana","onboarded":true,"pins":{"2026-11-14":"SAT Practice 5"},"skips":[],"targetScore":1400,"testDate":"2026-11-07T00:00:00.000-05:00"}"#)
        check(old.map { $0.name == "Ana" && $0.onboarded && $0.pins.count == 1 && $0.sittings.count == 1 && $0.sittings[0].booked && cal.isDate($0.sittings[0].date, inSameDayAs: nov7) } == true,
              "migrate: testDate becomes a booked sitting, everything else kept")
        let month = decode(#"{"days":[1,7],"focus":["Algebra"],"grade":12,"minutes":45,"name":"","onboarded":true,"pins":{},"skips":["2026-12-01"],"targetScore":1500,"targetMonth":"2027-03-01T00:00:00.000-05:00","startScore":1210}"#)
        check(month.map { $0.sittings.count == 1 && !$0.sittings[0].booked && cal.isDate($0.sittings[0].date, inSameDayAs: SATDates.all[2].date) && $0.minutes == 45
                          && $0.priorScores.first?.total == 1210 && $0.focus == ["Algebra"] } == true, "migrate: targetMonth becomes that month's official date, not booked")
        check(decode(#"{"name":"Kai"}"#)?.name == "Kai" && decode("{}") == Profile(), "migrate: missing fields take defaults")
        check(old.flatMap { try? Fmt.decoder.decode(Profile.self, from: Fmt.encoder.encode($0)) } == old, "migrate: the new profile round-trips")
        let ticks: Set<String> = ["2026-11-05|drill|Algebra", "2026-11-05|cards|Flashcards", "2026-11-09|cards|Flashcards", "2026-11-09|drill|Not a task anymore", "garbage", "2026-11-06|nokind|x"]
        let migrated = Planner.migrate(ticks)
        check(migrated.count == 2 && migrated[0].tasks.count == 2 && migrated.allSatisfy { $0.tasks.allSatisfy(\.done) }, "migrate: ticks become done tasks, unreadable ones dropped")
        let mPlan = Planner.make(input(p, at(11, 9)), old: migrated)
        check(on(mPlan, 11, 5)?.tasks.count == 2 && on(mPlan, 11, 9)?.tasks.first { $0.kind == .cards }?.done == true && on(mPlan, 11, 9)?.tasks.contains { $0.title == "Not a task anymore" } == false,
              "migrate: old history kept, today's tick maps by kind")
        check((try? Fmt.decoder.decode([StudyDay].self, from: Fmt.encoder.encode(plan))) == plan, "plan.json round-trips")

        // The store: one plan, ticks kept by id, a finished test ticks itself, accept / dismiss.
        let ps = PlanStore.shared, savedProfile = ps.profile, savedCards = CardStore.shared.cards
        var cp = savedProfile; cp.days = Set(1...7); cp.minutes = 60; cp.sittings = [Sitting(date: cal.date(byAdding: .day, value: 56, to: cal.startOfDay(for: Date()))!)]; cp.pins = [:]; cp.skips = []
        ps.profile = cp
        let d0 = ps.days
        check(!d0.isEmpty && d0.flatMap(\.tasks).map(\.id) == ps.days.flatMap(\.tasks).map(\.id), "plan store: reading twice gives the same plan")
        if let t = ps.today?.tasks.first(where: { $0.kind != .test }) ?? ps.days.first?.tasks.first {
            let day = ps.days.first { $0.tasks.contains { $0.id == t.id } }!.date
            ps.toggle(day, t)
            cp.minutes = 90; ps.profile = cp
            check(ps.isDone(day, t) && ps.days.flatMap(\.tasks).contains { $0.id == t.id && $0.done }, "plan store: a tick survives a re-plan")
            ps.toggle(day, t)
        }
        if let fd = ps.days.first(where: { $0.tasks.contains { $0.kind == .test && $0.test != nil } }), let ft = fd.tasks.first(where: { $0.kind == .test }) {
            // On the test's own day (the plan's clock moved there), so the check holds whatever day it runs.
            Clock.shift = fd.date.addingTimeInterval(12 * 3600).timeIntervalSince(Date())
            defer { Clock.shift = 0 }
            var fin = Session(id: "selftest-plan-\(UUID().uuidString)", start: Clock.now - 60)
            fin.end = Clock.now; fin.test = ft.test
            Store.shared.save(fin)
            check(ps.isDone(Clock.now, ft) && ps.active(Clock.now), "plan store: a finished test ticks its task")
            Store.shared.sessions.removeAll { $0.id == fin.id }
            Store.shared.flush(); try? FileManager.default.removeItem(at: Store.shared.dir(fin.id))
        }
        // The day after a planned test that was not taken: missed on the list and the week; ticked, the menu moves on.
        if let fd = ps.days.first(where: { $0.tasks.contains { $0.kind == .test && $0.test != nil } }), let ft = fd.tasks.first(where: { $0.kind == .test }), let name = ft.test {
            if ps.isDone(fd.date, ft) { ps.toggle(fd.date, ft) }   // the check above left it ticked
            Clock.shift = fd.date.addingTimeInterval(36 * 3600).timeIntervalSince(Date())
            defer { Clock.shift = 0 }
            check(ps.fullTests.contains { $0.kind == .missed && $0.note == "Missed" && cal.isDate($0.date, inSameDayAs: fd.date) }
                  && DayMark.of(fd.date, ps.byDay[cal.startOfDay(for: fd.date)], plan: ps) == .missed, "full tests: a planned test not taken shows as missed")
            check(ps.trackChoice(name) == name, "track: a test not taken stays the menu's pick")
            ps.toggle(fd.date, ft)
            let next = ps.days.flatMap(\.tasks).compactMap(\.test).first
            check(ps.trackChoice(name) != name && (next == nil || ps.trackChoice(name) == next) && ps.fullTests.contains { $0.name == name && $0.note == "No results" },
                  "track: a test ticked as taken moves the menu to the plan's next test")
        }
        CardStore.shared.cards = savedCards
        ps.profile = savedProfile
    }
}
