import Combine
import SwiftUI

// MARK: - Model

/// One generated SAT question with its explanation. Field names follow `Analysis` (solutionJa, trapJa, vocab),
/// so `Tutor.stored` renames and cleans the model's reply the same way it does for explanations.
struct PracticeQuestion: Codable, Hashable {
    var section: String
    var domain: String
    var skill: String
    var difficulty: String
    var passage: String
    var question: String
    var choices: [String]        // A to D; empty for a Math student-produced response
    var correct: String          // a letter, or the number(s) for a student-produced response: "49/2, 24.5"
    var keyPoint: String
    var solutionJa: String
    var trapJa: String
    var choiceNotes: [String]    // why each choice fails, A to D; "" for the right one
    var vocab: [Vocab]
    var desmos: [String]
    var desmosFocus: String

    /// Four choices with a letter key, or no choices with number keys that fit the SAT's entry box (5 characters, 6 with a minus sign).
    var valid: Bool {
        guard choices.isEmpty else { return choices.count == 4 && Practice.letters.contains(correct) }
        let forms = correct.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return section == Sec.math && !forms.isEmpty
            && forms.allSatisfy { f in !f.isEmpty && f.count <= (f.hasPrefix("-") ? 6 : 5) && f.allSatisfy { "0123456789./-".contains($0) } }
    }

    /// A blank whose choices all start with the word just before it ("the corpus ______" + "corpus;" / "corpus,") reads
    /// the word twice. As on the SAT, the choices carry the word and the passage leaves it out.
    func unrepeated() -> PracticeQuestion {
        guard choices.count == 4, let blank = passage.range(of: "______"),
              let w = choices[0].firstMatch(of: #/^[\p{L}'’-]+/#).map({ String($0.output) }),
              choices.allSatisfy({ $0.hasPrefix(w) && $0.dropFirst(w.count).first.map { !$0.isLetter } ?? true }) else { return self }
        let before = passage[..<blank.lowerBound]
        guard let m = before.firstMatch(of: try! Regex("(?:^|\\s)" + NSRegularExpression.escapedPattern(for: w) + "\\s*$")) else { return self }
        var q = self
        let keep = before[..<m.range.lowerBound]
        q.passage = String(keep) + (keep.isEmpty ? "" : " ") + passage[blank.lowerBound...]
        return q
    }

    /// Numeric choices in ascending order, as the SAT lists them; the key and the notes move with them.
    func ascending() -> PracticeQuestion {
        let v = choices.map { Double($0.filter { !"$, ".contains($0) }.replacingOccurrences(of: "−", with: "-")) }
        guard choices.count == 4, let k = Practice.letters.firstIndex(of: correct), v.allSatisfy({ $0 != nil }) else { return self }
        let order = v.indices.sorted { v[$0]! < v[$1]! }
        var q = self
        q.choices = order.map { choices[$0] }
        if choiceNotes.count == 4 { q.choiceNotes = order.map { choiceNotes[$0] } }
        q.correct = Practice.letters[order.firstIndex(of: k)!]
        return q
    }
}

/// A practice set as taken: the questions, the student's work on each, and whether it was submitted. Saved in practice.json.
/// Fields added later are optional, so sets saved before them still load.
struct PracticeSet: Codable, Identifiable, Hashable {
    struct Work: Codable, Hashable {
        var answer: String? = nil
        var crossed: [String] = []
        var marked = false
        var seconds = 0.0
        var checked: Bool? = nil     // practice questions: Check was pressed, so the answer is shown and locked
        var highlights: [Mark]? = nil
        var chat: [ChatLine]? = nil  // practice questions: the student's questions to the tutor after Check
    }
    /// A highlight on the passage or question text (Bluebook's Highlights & Notes): a character range of the shown text.
    struct Mark: Codable, Hashable {
        var start: Int
        var length: Int
        var color = "yellow"         // yellow, blue or pink
        var note = ""
    }
    /// One module of a full test: where its questions sit in `questions` once written, and its clock.
    struct Module: Codable, Hashable {
        var section: String
        var number: Int
        var first = 0, count = 0     // count 0: not written yet
        var hard: Bool?              // Module 2: the harder route, set when Module 1 ends
        var used = 0.0               // seconds off the module's clock
        var limit: Double { Sec.limit(section) }
        var size: Int { section == Sec.math ? 22 : 27 }
        var range: Range<Int> { first..<first + count }
    }
    var id = UUID().uuidString
    var date = Date()
    var section: String          // "Reading and Writing", "Math", or both joined with " + "
    var domain: String           // the set's name
    var difficulty: String
    var asked: Int               // questions requested; the answer check can keep fewer
    var questions: [PracticeQuestion]
    var work: [Work]
    var done = false
    var test: Bool?              // a full test: four modules, Module 2 adaptive, results at the end
    var timer: Bool?             // practice questions: count down at SAT pace
    var modules: [Module]?
    var stage: Int?              // full test: the module on screen; modules.count when finished
    var visits: [Visit]?         // full test: every stay on a question, for the Session it becomes
    var session: String?         // full test: that Session's id

    init(section: String, domain: String, difficulty: String, asked: Int, questions: [PracticeQuestion]) {
        self.section = section; self.domain = domain; self.difficulty = difficulty; self.asked = asked
        self.questions = questions; work = questions.map { _ in Work() }
    }

    var full: Bool { test == true }
    /// SAT pace per question: 71 s in Reading and Writing, 95 s in Math.
    static func pace(_ section: String) -> Double { section == Sec.math ? 95 : 71 }
    func pace(_ i: Int) -> Double { Self.pace(questions[i].section) }
    var limit: Double { questions.indices.map(pace).reduce(0, +) }
    func right(_ i: Int) -> Bool { Session.same(work[i].answer, questions[i].correct) }
    /// Questions in the order they are taken: module by module in a full test.
    var order: [Int] { modules.map { $0.flatMap(\.range) } ?? Array(questions.indices) }
    var score: Int { order.filter(right).count }
    var sections: [String] {
        let s = order.map { questions[$0].section }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return s.isEmpty ? section.components(separatedBy: " + ") : s
    }
    func score(_ sec: String) -> (right: Int, total: Int) {
        let ks = order.filter { questions[$0].section == sec }
        return (ks.filter(right).count, ks.count)
    }

    /// Back to the start: every answer, mark, cross-out, highlight, check and second cleared; a full test back to Module 1
    /// with full clocks. The questions stay, a written Module 2 too, on the route it was written for.
    mutating func restart() {
        work = questions.map { _ in Work() }
        done = false
        guard full else { return }
        stage = 0; visits = []; session = nil
        modules = modules?.map { var m = $0; m.used = 0; return m }
    }
}

/// One part of a set to build: a section, a domain or one skill, a difficulty and a count.
struct Block: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var section: String
    var domain = ""              // "" = every domain of the section, in official shares
    var skill = ""               // "" = every skill of the domain
    var difficulty = "Mixed"
    var count = 5
    var format: String?          // Math: `Practice.choice` or `Practice.grid`; nil = the official mix
    var focus: String?           // the student's note to the writer, e.g. "science passages"
    var mine: Bool?              // made from the student's results: the writer gets their weak spots (`Practice.context`)
    var title: String { !skill.isEmpty ? skill : !domain.isEmpty ? domain : "All of \(Sec.name(section))" }
}

struct Template: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var blocks: [Block]
}

/// The plan for one question: its skill, difficulty, and where the key goes ("" = a student-produced response).
struct Slot: Hashable { var skill: Skill; var difficulty: String; var key: String; var focus = "" }

/// Questions being written for one block, or one share of a full-test module, with its progress.
struct Part: Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var section: String
    var slots: [Slot]
    var module: Int? = nil       // full test: the module these questions make
    var hard: Bool? = nil        // Module 2: the route it was written for
    var mine = false             // the writer gets the student's weak spots
    var target = 0               // full test: questions needed; dropped ones are written again, up to twice as many tries
    var done = 0, kept = 0
    var step = "Waiting"         // Waiting, Writing, Checking; "" once finished or failed
    var error: String?
    var got: [PracticeQuestion] = []   // full test: held until the whole module is written
    var finished: Bool { done >= slots.count && error == nil }
}

// MARK: - Store and generation

/// Practice sets written by the AI, checked by a second, independent solve, and kept on disk.
@MainActor final class Practice: ObservableObject {
    static let shared = Practice()
    nonisolated static let letters = ["A", "B", "C", "D"]
    @Published var sets: [PracticeSet] { didSet { if let file { Files.save(sets, file) } } }
    @Published var templates: [Template] { didSet { if file != nil { Files.save(templates, "templates.json") } } }
    @Published var open: String?            // the set on screen: its test while unfinished, else its results
    @Published var building: String?        // the set whose questions are being written, on the Practice page
    @Published var parts: [String: [Part]] = [:]   // by set id
    @Published var chatting: Set<String> = []      // "set id/question index" while the tutor answers
    @Published var blocks: [Block] = []     // the set being built; kept while the page is away
    @Published var timer = false
    @Published var error: String?
    @Published var leaving: (() -> Void)?   // a full test asks before it goes away; this runs once the student saves or discards
    var desmos = true                       // snapshots draw a placeholder instead (Desmos needs the network)
    var drafts: [String: PracticeSet] = [:] // sets with no question yet
    var stub: (([Slot]) async throws -> [Int: PracticeQuestion])?   // self-test: questions without a model
    private var started: Set<String> = []
    private var tasks: [String: [Task<Void, Never>]] = [:]   // by set id, so Cancel can stop them
    private let file: String?

    init(file: String? = "practice.json") {
        self.file = file
        sets = (file.flatMap { Files.load($0, as: [PracticeSet].self) } ?? []).filter { !$0.questions.isEmpty }
            .map { var s = $0; s.questions = s.questions.map { $0.unrepeated() }; return s }   // sets written before the fix read right too
        templates = file == nil ? [] : Files.load("templates.json", as: [Template].self) ?? []
        if file != nil { Store.shared.leave = { [unowned self] from, to in from != .practice || mayLeave { Store.shared.nav = to } } }
    }

    /// True unless a full test is on screen: then it asks first, and `then` runs once the student saves or discards.
    func mayLeave(_ then: @escaping () -> Void) -> Bool {
        guard let id = open, let s = set(id), s.full, !s.done else { return true }
        leaving = then
        return false
    }

    func set(_ id: String) -> PracticeSet? { sets.first { $0.id == id } }
    /// A question to the tutor about a checked practice question. The question, its key and the explanation go along,
    /// so the tutor never has to re-solve it.
    func ask(_ id: String, _ i: Int, _ text: String) async {
        let tag = "\(id)/\(i)"
        guard let s = set(id), s.questions.indices.contains(i), !chatting.contains(tag) else { return }
        let q = s.questions[i], w = s.work[i]
        chatting.insert(tag); defer { chatting.remove(tag) }
        update(id) { $0.work[i].chat = ($0.work[i].chat ?? []) + [ChatLine(fromStudent: true, text: text)] }
        let choices = zip(Practice.letters, q.choices).map { "\($0). \($1)" }.joined(separator: "\n")
        let facts = [q.passage, q.question, choices, "Correct answer: \(q.correct). The student answered: \(w.answer ?? "nothing").",
                     "Key point: \(q.keyPoint)", "Solution:\n\(q.solutionJa)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let history: [[String: Any]] = (set(id)?.work[i].chat ?? []).map { ["role": $0.fromStudent ? "user" : "assistant", "content": [["type": "text", "text": $0.text]]] }
        let system = "You are the student's SAT tutor. They just answered this practice question and read its explanation.\n\n"
            + facts + "\n\n" + Tutor.chatRules + "\n\nWhat you know about the student:\n" + Student.brief()
        let reply: String
        do { reply = try await Brain.send(task: .chat, system: system, messages: history, base: Store.shared.root) }
        catch { reply = error.localizedDescription }
        update(id) { $0.work[i].chat = ($0.work[i].chat ?? []) + [ChatLine(fromStudent: false, text: reply)] }
    }

    func update(_ id: String, _ change: (inout PracticeSet) -> Void) {
        if let i = sets.firstIndex(where: { $0.id == id }) { change(&sets[i]) }
    }

    /// Right and total across submitted sets, for one official domain.
    func stats(_ domain: String) -> (right: Int, total: Int) {
        var r = 0, t = 0
        for s in sets where s.done { for i in s.order where s.questions[i].domain == domain { t += 1; if s.right(i) { r += 1 } } }
        return (r, t)
    }

    /// The student's weakest domain (their own focus first), as one block at a difficulty from their accuracy there.
    static func defaultBlock() -> Block {
        let sessions = Store.shared.sessions
        let dom = PlanStore.shared.profile.focus.first ?? Planner.weakest(sessions).first ?? Planner.mathDomains[0]
        return Block(section: section(of: dom), domain: dom, difficulty: level(Score.domains(sessions).first { $0.name == dom }?.rate))
    }
    static func level(_ rate: Double?) -> String { rate.map { $0 < 0.5 ? "Easy" : $0 < 0.8 ? "Medium" : "Hard" } ?? "Medium" }
    static func section(of domain: String) -> String { Planner.mathDomains.contains(domain) ? Sec.math : rw }
    static func domains(_ section: String) -> [String] { section == Sec.math ? Planner.mathDomains : Planner.rwDomains }
    /// Questions per section in one module: a set holds up to that many.
    static func cap(_ section: String) -> Int { section == Sec.math ? 22 : 27 }

    // MARK: Planning

    /// `n` shared out by weight, largest remainder first; ties go to the larger weight, then at random, so small blocks vary their skills.
    static func split(_ n: Int, _ w: [Double]) -> [Int] {
        let total = w.reduce(0, +)
        guard n > 0, total > 0 else { return w.map { _ in 0 } }
        let exact = w.map { Double(n) * $0 / total }
        var out = exact.map { Int($0) }
        let jitter = w.map { _ in Double.random(in: 0..<1) }
        let order = w.indices.sorted { (exact[$0] - Double(out[$0]), w[$0], jitter[$0]) > (exact[$1] - Double(out[$1]), w[$1], jitter[$1]) }
        for i in order.prefix(n - out.reduce(0, +)) { out[i] += 1 }
        return out
    }

    /// The plan for a block: domains share it by official weight, skills by their weight in a module, and difficulty spreads by
    /// `mix` (Easy, Medium, Hard). Math runs easiest to hardest with topics mixed; Reading and Writing is grouped by skill, each
    /// group easiest to hardest, as in a real module. Keys go round A–D in shuffled fours; Math grid-ins come at the skill's
    /// official rate, scaled by difficulty (Easy 9%, Medium 32%, Hard 36% against 26% overall).
    static func slots(_ b: Block, mix: [Double]? = nil) -> [Slot] {
        let one = skills.first { $0.name == b.skill }
        let doms = one.map { [$0.domain] } ?? (b.domain.isEmpty ? domains(b.section) : [b.domain])
        var chosen: [Skill] = []
        let format = b.section == Sec.math ? b.format : nil
        for (d, n) in zip(doms, split(b.count, doms.map { Planner.share[$0] ?? 1 })) {
            let all = skills(b.section, d), gridded = all.filter { $0.spr > 0 }
            let pool = one.map { [$0] } ?? (format == grid && !gridded.isEmpty ? gridded : all)
            for (s, k) in zip(pool, split(n, pool.map(\.weight))) { chosen += Array(repeating: s, count: k) }
        }
        let mix = mix ?? tiers.map { b.difficulty == "Mixed" || b.difficulty == $0 ? 1.0 : 0 }
        func tier(_ j: Int, of n: Int) -> String {   // the j-th of n, at the middle of its share
            let x = (Double(j) + 0.5) / Double(n) * mix.reduce(0, +)
            var c = 0.0
            for (t, w) in zip(tiers, mix) { c += w; if x < c { return t } }
            return tiers[2]
        }
        var plan: [(Skill, String)] = []
        if b.section == Sec.math {
            plan = chosen.shuffled().enumerated().map { ($1, tier($0, of: chosen.count)) }
        } else {
            for s in skills where chosen.contains(s) {
                let n = chosen.count { $0 == s }
                plan += (0..<n).map { (s, tier($0, of: n)) }
            }
        }
        let scale = ["Easy": 0.09 / 0.26, "Medium": 0.32 / 0.26, "Hard": 0.36 / 0.26]
        var deck: [String] = [], gridShare = 0.5
        let focus = String((b.focus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.focusLimit))
        return plan.map { s, d in
            let before = gridShare
            gridShare += s.spr * (scale[d] ?? 1)
            if format.map({ $0 == grid && s.spr > 0 }) ?? (Int(gridShare) > Int(before)) { return Slot(skill: s, difficulty: d, key: "", focus: focus) }
            if deck.isEmpty { deck = letters.shuffled() }
            return Slot(skill: s, difficulty: d, key: deck.removeFirst(), focus: focus)
        }
    }

    /// A Math block's question format: all multiple choice, or all student-produced responses (skills that have them).
    static let choice = "Multiple choice", grid = "Student-produced response"
    static let focusLimit = 120

    /// Module order: Math easiest to hardest; Reading and Writing grouped by skill in module order, each easiest to hardest.
    static func ordered(_ qs: [PracticeQuestion]) -> [PracticeQuestion] {
        let rank = Dictionary(skills.enumerated().map { ($1.name, $0) }) { a, _ in a }
        func key(_ i: Int) -> (Int, Int, Int) {
            let q = qs[i]
            return (q.section == Sec.math ? 0 : rank[q.skill] ?? 0, tiers.firstIndex(of: q.difficulty) ?? 1, i)
        }
        return qs.indices.sorted { key($0) < key($1) }.map { qs[$0] }
    }

    static let presets = ["Weakest topics", "R&W module", "Math module", "Mixed"]

    /// Ready-made block lists. A module follows the official shares (R&W by domain; Math easiest to hardest).
    static func preset(_ name: String, _ sessions: [Session]) -> [Block] {
        switch name {
        case "R&W module":
            return zip(Planner.rwDomains, split(27, Planner.rwDomains.map { Planner.share[$0] ?? 0 })).map { Block(section: rw, domain: $0, count: $1) }
        case "Math module":
            return [("Easy", 6), ("Medium", 10), ("Hard", 6)].map { Block(section: Sec.math, difficulty: $0, count: $1) }
        case "Mixed":
            return [Block(section: rw), Block(section: Sec.math)]
        default:
            let rates = Score.domains(sessions)
            var names: [String] = []
            for d in rates.map(\.name) + Planner.weakest(sessions) where !names.contains(d) { names.append(d) }
            return names.prefix(3).map { d in Block(section: section(of: d), domain: d, difficulty: level(rates.first { $0.name == d }?.rate), mine: true) }
        }
    }

    /// The official skill a recorded skill name means, within its domain ("Words in context" → Words in Context).
    static func skill(named raw: String, in domain: String) -> Skill? {
        let r = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return nil }
        let pool = skills.filter { $0.domain == domain }
        func words(_ s: String) -> [Substring] { Array(s.lowercased().split(separator: " ").prefix(2)) }
        return pool.first { $0.name.lowercased() == r } ?? pool.first { $0.name.lowercased().hasPrefix(r) || r.hasPrefix($0.name.lowercased()) }
            ?? pool.first { words($0.name) == words(r) }
    }

    /// Blocks from past tests: the skills (or domains) with the most misses get the most questions, each at a difficulty
    /// from the accuracy there. With no misses yet, the weakest topics.
    static func fromResults(_ sessions: [Session]) -> [Block] {
        var tally: [String: (right: Int, total: Int, block: Block)] = [:]
        for s in sessions {
            for k in s.keys {
                guard let c = s.correct(k), let d = s.topic(k), Planner.share[d] != nil else { continue }
                let sk = skill(named: s.official?.answers[k]?.skill ?? s.q[k]?.analysis?.skill ?? "", in: d)
                let name = sk?.name ?? d
                tally[name, default: (0, 0, Block(section: section(of: d), domain: d, skill: sk?.name ?? ""))].total += 1
                if c { tally[name]!.right += 1 }
            }
        }
        let missed = tally.filter { $0.value.total > $0.value.right }
            .sorted { ($0.value.total - $0.value.right, $1.key) > ($1.value.total - $1.value.right, $0.key) }.prefix(5)
        guard !missed.isEmpty else { return preset("Weakest topics", sessions) }
        let counts = split(20, missed.map { Double($0.value.total - $0.value.right) })
        return zip(missed, counts).map { m, n in
            var b = m.value.block
            b.count = max(1, min(10, n)); b.difficulty = level(Double(m.value.right) / Double(m.value.total)); b.mine = true
            return b
        }
    }

    /// A set's name from its blocks: a whole section by its name, else its topics.
    static func label(_ blocks: [Block]) -> String {
        var out: [String] = []
        for sec in [rw, Sec.math] {
            let bs = blocks.filter { $0.section == sec }
            guard !bs.isEmpty else { continue }
            let doms = Set(bs.map(\.domain))
            if doms.contains("") || (doms.isSuperset(of: domains(sec)) && bs.allSatisfy { $0.skill.isEmpty }) { out.append(Sec.name(sec)) }
            else { for b in bs where !out.contains(b.title) { out.append(b.title) } }
        }
        return out.joined(separator: ", ")
    }

    // MARK: Prompts

    static let writer = """
    You write practice questions for the digital SAT, as students see them in College Board's Bluebook app. Each question \
    must match the real test: follow the section rules and the specification of its skill exactly, in question wording, \
    passage form and length, answer-choice style and difficulty. Write new questions; never copy real College Board ones. \
    Each question has exactly one correct answer: solve it yourself and check it before you write it down. Every wrong \
    choice fails for a reason a careful student can find.

    Write the questions in the order asked, each to its plan: its skill, its difficulty, and the letter the correct answer \
    goes at. For numeric choices, which are in ascending order, pick the wrong values so the correct one lands at that letter. \
    A question planned as a student-produced response has no choices.

    The explanations are for a student who knows the math well but learned it in another language. Write in plain, \
    simple English: short sentences (under 20 words), common words. No praise, no filler. Advice must hold on any test: \
    never say "tomorrow", "today" or "on test day", and don't refer to dates. Titles never end with a period; every sentence does. \
    Never name a choice by its letter in the explanations.

    Formatting: write every bit of math between $ signs in simple LaTeX ($x^2$, $\\frac{24}{n}$, $\\sqrt{x}$, $\\le$, $\\cdot$, \
    $\\pi$), in the question and choices too. In explanations, put words quoted from the passage, question or choices in \
    double quotes and mark at most one key term per field with **double asterisks**. No other markup.
    """

    static let solver = """
    You are a careful student taking the digital SAT. Solve each question on your own and check your work. \
    Answer every question: the letter of the best choice (A to D), or for a question with no choices the number only \
    (a fraction like 3/4 is fine). If unsure, give the most likely answer.
    """

    /// The writer's instructions for one batch: the general rules, the rules of the sections in it, and only its skills' specs.
    static func system(_ batch: [Slot]) -> String {
        var secs: [String] = [], sks: [Skill] = []
        for s in batch {
            if !secs.contains(s.skill.section) { secs.append(s.skill.section) }
            if !sks.contains(s.skill) { sks.append(s.skill) }
        }
        return ([writer] + secs.compactMap { rules[$0] } + ["SKILL SPECIFICATIONS"] + sks.map { "\($0.name) (\($0.section), \($0.domain))\n\($0.spec)" })
            .joined(separator: "\n\n")
    }

    /// The batch's plan, one line per question, and recent passages not to repeat.
    static func request(_ batch: [Slot], avoid: [String]) -> String {
        var lines = ["Write \(batch.count) \(batch.count == 1 ? "question" : "questions"), in this order:"]
        for (i, s) in batch.enumerated() {
            lines.append("\(i + 1). \(s.skill.section) · \(s.skill.domain) · \(s.skill.name) · \(s.difficulty) · "
                         + (s.key.isEmpty ? "student-produced response (no choices)" : "four choices, correct answer \(s.key)"))
        }
        let asked = batch.map(\.focus).filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if !asked.isEmpty { lines.append("The student asked for: " + asked.joined(separator: "; ") + ". Follow it where it fits the plan.") }
        if !avoid.isEmpty { lines.append("Use new topics and contexts, not these: " + avoid.joined(separator: " | ")) }
        return lines.joined(separator: "\n")
    }

    /// For sets made from the student's data (From my results, Weakest topics, full tests): their weakest domains and skills,
    /// recent reasons for misses, and their vocabulary, in a few lines. Custom sets get none, so the student's picks stand.
    static func context(_ sessions: [Session], cards: [Card]) -> String {
        var lines: [String] = []
        let weak = Score.domains(sessions).prefix(3).map { "\($0.name) \(Int($0.rate * 100))%" }
        if !weak.isEmpty { lines.append("Weakest domains (share right): " + weak.joined(separator: ", ") + ".") }
        let missed = fromResults(sessions).filter { !$0.skill.isEmpty }.prefix(3).map(\.skill)
        if !weak.isEmpty, !missed.isEmpty { lines.append("Most-missed skills: " + missed.joined(separator: ", ") + ".") }
        let why = Student.reasons(Array(sessions.prefix(3))).prefix(3).compactMap { r in Cause.of(r.id, section: r.section).map { "\($0.name) \(r.count)" } }
        if !why.isEmpty { lines.append("Why they missed on recent tests: " + why.joined(separator: ", ") + ".") }
        var wic = (right: 0, total: 0)
        for s in sessions { for k in s.keys where (s.official?.answers[k]?.skill ?? s.q[k]?.analysis?.skill)?.lowercased() == "words in context" {
            if let c = s.correct(k) { wic.total += 1; if c { wic.right += 1 } }
        } }
        let learning = cards.filter { $0.kind == .word && ($0.lapses > 0 || $0.learning) }.prefix(6).map(\.front)
        var vocab: [String] = []
        if wic.total > 0 { vocab.append("Words in Context \(wic.right) of \(wic.total) right") }
        if !learning.isEmpty { vocab.append("words still being learned: " + learning.joined(separator: ", ")) }
        if !vocab.isEmpty { lines.append("Vocabulary: " + vocab.joined(separator: "; ") + ". English is not their first language.") }
        guard !lines.isEmpty else { return "" }
        return (lines + ["Use this only to aim traps and contexts at these weak spots. Every question keeps its planned skill, difficulty and key."])
            .joined(separator: "\n")
    }

    static let schema: [String: Any] = {
        func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        func e(_ v: [String]) -> [String: Any] { ["type": "string", "enum": v] }
        let tutor = Tutor.schema["properties"] as? [String: Any] ?? [:]   // the same explanation contract as the tutor's
        let q: [String: Any] = [
            "section": e([rw, Sec.math]),
            "domain": e(Planner.rwDomains + Planner.mathDomains),
            "skill": s("The skill name exactly as planned."),
            "difficulty": e(tiers),
            "passage": s("Reading and Writing: the passage as its skill specifies, with any attribution line, Text 1/Text 2 labels, notes or table. Math: a short context the question needs, or an empty string."),
            "question": s("The question line in the SAT's wording. Math: the whole problem if there is no context."),
            "choices": ["type": "array", "items": ["type": "string"], "description": "Exactly four answer choices in order A to D, without their letters. An empty array only for a Math student-produced response."],
            "correct": s("The correct letter, A to D. For a student-produced response, the number only, every accepted form separated by commas, e.g. '24', '3/4' or '49/2, 24.5'."),
            "key_point": tutor["key_point"] ?? s("One reusable rule, one sentence."),
            "solution": tutor["solution"] ?? s("2 to 4 numbered steps."),
            "trap": s("The trap that catches most students on this question and why it fails, one or two sentences. Never write the answer letter."),
            "choice_notes": ["type": "array", "items": ["type": "string"], "description": "For each choice in order A to D, why it is wrong, in one short sentence that doesn't name its letter; an empty string for the correct choice. An empty array for a student-produced response."],
            "vocab": tutor["vocab"] ?? ["type": "array", "items": ["type": "object"]],
            "desmos": tutor["desmos"] ?? ["type": "array", "items": ["type": "string"]],
            "desmos_focus": tutor["desmos_focus"] ?? s("A point such as '(14,0)', or an empty string."),
        ]
        let item: [String: Any] = ["type": "object", "additionalProperties": false, "required": Array(q.keys).sorted(), "properties": q]
        return ["type": "object", "additionalProperties": false, "required": ["questions"], "properties": ["questions": ["type": "array", "items": item]]]
    }()

    static let answerSchema: [String: Any] = {
        let a: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["answer", "number"],
                                "properties": ["number": ["type": "string", "description": "The question number, e.g. '3'."],
                                               "answer": ["type": "string", "description": "The letter, or the number for a question with no choices."]]]
        return ["type": "object", "additionalProperties": false, "required": ["answers"], "properties": ["answers": ["type": "array", "items": a]]]
    }()

    /// The writer's reply as questions: cleaned like explanations, letters taken off the choices ("A) 24" → "24"),
    /// numeric Math choices put in ascending order.
    static func parse(_ text: String) throws -> [PracticeQuestion] {
        struct Reply: Decodable { var questions: [PracticeQuestion] }
        return try Tutor.snake.decode(Reply.self, from: Tutor.stored(text)).questions.map { q in
            var q = q
            q.choices = q.choices.map { $0.replacingOccurrences(of: #"^\(?[A-D][.):]\s+"#, with: "", options: .regularExpression) }
            q.correct = q.correct.trimmingCharacters(in: .whitespaces)
            if !q.choices.isEmpty { q.correct = q.correct.uppercased() }
            return q.section == Sec.math ? q.ascending() : q.unrepeated()
        }
    }

    /// The plan wins over the writer's labels: each question takes its slot's section, domain, skill and difficulty.
    static func label(_ qs: [PracticeQuestion], _ batch: [Slot]) -> [PracticeQuestion] {
        zip(qs, batch).map { q, s in
            var q = q
            q.section = s.skill.section; q.domain = s.skill.domain; q.skill = s.skill.name; q.difficulty = s.difficulty
            return q
        }
    }

    /// The solver's reply as question number → answer.
    static func answers(_ text: String) throws -> [String: String] {
        struct Reply: Decodable { struct A: Decodable { var number: String; var answer: String }; var answers: [A] }
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()"))
        return Dictionary(try JSONDecoder().decode(Reply.self, from: Data(text.utf8)).answers.map { ($0.number.trimmingCharacters(in: trim), $0.answer.trimmingCharacters(in: trim)) }) { a, _ in a }
    }

    /// Places of the well-formed questions whose key the independent solve agrees with.
    static func agreed(_ qs: [PracticeQuestion], _ answers: [String: String]) -> [Int] {
        qs.indices.filter { qs[$0].valid && Session.same(answers["\($0 + 1)"], qs[$0].correct) }
    }
    static func verified(_ qs: [PracticeQuestion], _ answers: [String: String]) -> [PracticeQuestion] { agreed(qs, answers).map { qs[$0] } }

    /// The questions as the solver sees them: no key, no explanation.
    static func exam(_ qs: [PracticeQuestion]) -> String {
        qs.enumerated().map { i, q in
            var lines = ["Question \(i + 1) (\(q.section))"]
            if !q.passage.isEmpty { lines.append(q.passage) }
            lines.append(q.question)
            lines += q.choices.isEmpty ? ["(No choices: answer with a number.)"] : zip(letters, q.choices).map { "\($0). \($1)" }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    // MARK: Writing

    /// One batch: written to plan, then solved by a second call without the key. Only questions the solve agrees with come back,
    /// by their place in the batch.
    func write(_ batch: [Slot], avoid: [String], mine: Bool, checking: () -> Void) async throws -> [Int: PracticeQuestion] {
        if let stub { return try await stub(batch) }
        func ask(_ text: String) -> [[String: Any]] { [["role": "user", "content": [["type": "text", "text": text]]]] }
        let about = mine ? Self.context(Store.shared.sessions, cards: CardStore.shared.cards) : ""
        let text = try await Brain.send(task: .practice, system: Self.system(batch) + (about.isEmpty ? "" : "\n\nWhat you know about the student:\n" + about),
                                        messages: ask(Self.request(batch, avoid: avoid)), schema: Self.schema, base: Files.base)
        let qs = Self.label(try Self.parse(text), batch)
        checking()
        let check = try await Brain.send(task: .practice, system: Self.solver, messages: ask(Self.exam(qs)), schema: Self.answerSchema, base: Files.base)
        let ok = Self.agreed(qs, try Self.answers(check))
        return Dictionary(uniqueKeysWithValues: ok.map { ($0, qs[$0]) })
    }

    /// Writes a practice set block by block; it can start as soon as its first questions pass the check.
    func make(_ blocks: [Block], timer: Bool) {
        guard building == nil, !blocks.isEmpty else { return }
        error = nil
        var secs: [String] = []
        for b in blocks where !secs.contains(b.section) { secs.append(b.section) }
        let diffs = Set(blocks.map(\.difficulty))
        var s = PracticeSet(section: secs.joined(separator: " + "), domain: Self.label(blocks), difficulty: diffs.count == 1 ? diffs.first! : "Mixed",
                            asked: blocks.map(\.count).reduce(0, +), questions: [])
        s.timer = timer
        let ps = blocks.map { Part(title: "\($0.title) · \($0.difficulty)", section: $0.section, slots: Self.slots($0), mine: $0.mine == true) }
        drafts[s.id] = s; parts[s.id] = ps; building = s.id
        let id = s.id
        // Blocks write side by side; the on-device model can only take one at a time. place() keeps block order either way.
        if Brain.provider(for: .practice) == .apple { spawn(id) { for p in ps where !Task.isCancelled { await self.run(id, p.id) } } }
        else { for p in ps { spawn(id) { await self.run(id, p.id) } } }
    }

    private func spawn(_ id: String, _ work: @escaping () async -> Void) { tasks[id, default: []].append(Task { await work() }) }

    /// A full test: Module 1 of each section is written now; each Module 2 once its Module 1 shows the route.
    func makeTest(_ sections: [String]) {
        guard building == nil, !sections.isEmpty else { return }
        error = nil
        var s = PracticeSet(section: sections.joined(separator: " + "), domain: "Full test", difficulty: "Adaptive",
                            asked: sections.map { Self.cap($0) * 2 }.reduce(0, +), questions: [])
        s.test = true; s.stage = 0; s.visits = []
        s.modules = sections.flatMap { sec in [1, 2].map { PracticeSet.Module(section: sec, number: $0) } }
        drafts[s.id] = s; building = s.id
        for (m, mod) in s.modules!.enumerated() where mod.number == 1 { prepare(s.id, m) }
    }

    /// Starts writing a module unless it is written or being written. Module 2 is written for a route: harder or easier.
    /// The module is split into batches written side by side (one after another on device).
    func prepare(_ id: String, _ m: Int, hard: Bool? = nil) {
        guard let s = set(id) ?? drafts[id], let mods = s.modules, mods.indices.contains(m), mods[m].count == 0,
              !(parts[id] ?? []).contains(where: { $0.module == m }) else { return }
        let mod = mods[m]
        let mix: [Double] = mod.number == 1 ? [1, 1, 1] : hard == true ? [1, 4, 5] : [5, 4, 1]
        let slots = Self.slots(Block(section: mod.section, count: mod.size), mix: mix)
        let per = Brain.provider(for: .practice) == .apple ? slots.count : 5
        let new = stride(from: 0, to: slots.count, by: per).map {
            Part(title: "\(Sec.name(mod.section)) · Module \(mod.number)", section: mod.section, slots: Array(slots[$0..<min($0 + per, slots.count)]),
                 module: m, hard: hard, mine: true, target: min(per, slots.count - $0))
        }
        parts[id, default: []] += new
        for p in new { spawn(id) { await self.run(id, p.id) } }
    }

    /// Runs one part's batches (5 questions, 2 on device). A failed call stops the part with its error; Retry runs it again.
    func run(_ id: String, _ pid: String) async {
        let per = Brain.provider(for: .practice) == .apple ? 2 : 5
        @discardableResult func edit(_ change: (inout Part) -> Void) -> Part? {
            guard let i = parts[id]?.firstIndex(where: { $0.id == pid }) else { return nil }
            change(&parts[id]![i])
            return parts[id]![i]
        }
        guard var p = edit({ $0.error = nil }), p.step != "Writing", p.step != "Checking" else { return }
        while p.done < p.slots.count, set(id)?.done != true, !Task.isCancelled {
            let batch = Array(p.slots[p.done..<min(p.done + per, p.slots.count)])
            let names = Set(batch.map(\.skill.name))
            let avoid = ((set(id)?.questions ?? []) + p.got).filter { names.contains($0.skill) }.suffix(12).map { String(($0.passage.isEmpty ? $0.question : $0.passage).prefix(70)) }
            do {
                edit { $0.step = "Writing" }
                let got = try await write(batch, avoid: avoid, mine: p.mine) { edit { $0.step = "Checking" } }
                let kept = batch.indices.compactMap { got[$0] }
                let dropped = batch.indices.filter { got[$0] == nil }.map { batch[$0] }
                guard let now = edit({ q in
                    q.done += batch.count; q.kept += kept.count
                    if q.module != nil { q.got += kept; if q.slots.count + dropped.count <= 2 * q.target { q.slots += dropped } }
                }) else { return }   // the part was dropped: Module 2 took the other route
                if now.module == nil { place(kept, id, now) }
                p = now
            } catch {
                if !Task.isCancelled { edit { $0.error = error.localizedDescription; $0.step = "" } }
                return
            }
        }
        guard !Task.isCancelled else { return }
        edit { $0.step = "" }
        if let m = p.module { commit(id, m) } else { finish(id) }
    }

    /// Practice: verified questions go in block order, so a retried block lands where it belongs.
    private func place(_ qs: [PracticeQuestion], _ id: String, _ p: Part) {
        guard !qs.isEmpty, let ps = parts[id], let k = ps.firstIndex(where: { $0.id == p.id }) else { return }
        let at = ps[..<k].map(\.kept).reduce(0, +) + p.kept - qs.count
        if set(id) == nil, let d = drafts.removeValue(forKey: id) { sets.insert(d, at: 0) }
        update(id) { s in
            let i = min(at, s.questions.count)
            s.questions.insert(contentsOf: qs, at: i); s.work.insert(contentsOf: qs.map { _ in .init() }, at: i)
        }
    }

    /// Practice: when every block is written. A set the student hasn't started stays on the progress view, all ready,
    /// until they press Start: it never opens by itself (they may be on another page, or back hours later).
    private func finish(_ id: String) {
        guard let ps = parts[id], ps.allSatisfy(\.finished) else { return }
        if set(id) == nil {
            close(id)
            error = "None of the questions passed the answer check. Try again."
        } else if started.contains(id) { close(id) }
    }

    /// Full test: a module joins the set once all its parts are written, and Module 2 only on the route its Module 1 earned.
    func commit(_ id: String, _ m: Int) {
        guard let s = set(id) ?? drafts[id], let mod = s.modules?[m], mod.count == 0 else { return }
        let ps = (parts[id] ?? []).filter { $0.module == m }
        guard !ps.isEmpty, ps.allSatisfy(\.finished), mod.number == 1 || (mod.hard != nil && ps.allSatisfy { $0.hard == mod.hard }) else { return }
        let qs = Self.ordered(ps.flatMap(\.got))
        parts[id]?.removeAll { $0.module == m }
        guard !qs.isEmpty else { return }   // nothing passed: the test writes it again when it gets there
        if set(id) == nil, let d = drafts.removeValue(forKey: id) { sets.insert(d, at: 0) }
        update(id) { s in
            s.modules![m].first = s.questions.count; s.modules![m].count = qs.count
            s.questions += qs; s.work += qs.map { _ in .init() }
        }
        // Module 1 is ready: start Module 2 right away, on the route the student's past results in this section point to.
        // Finishing Module 1 the other way rewrites it then (see `lock`).
        if mod.number == 1, let mods = set(id)?.modules, mods.indices.contains(m + 1), mods[m + 1].number == 2 {
            prepare(id, m + 1, hard: Self.likelyHarder(mod.section))
        }
    }

    /// Whether past tests suggest the harder Module 2 (70% or more right in this section); the harder route if unknown.
    static func likelyHarder(_ section: String) -> Bool {
        var right = 0, graded = 0
        for s in Store.shared.sessions { for k in s.keys where Session.section(of: k) == section { if let c = s.correct(k) { graded += 1; if c { right += 1 } } } }
        return graded == 0 || Double(right) >= 0.7 * Double(graded)
    }

    /// A plan task's set (its blocks, a module preset, or a full test): the one still open from today, else a new one.
    func begin(_ blocks: [Block], timer: Bool, test: Bool = false) {
        if let id = current(blocks, test: test) { if building != id { start(id) } }
        else if test { makeTest([Self.rw, Sec.math]) }
        else { self.timer = timer; make(blocks, timer: timer) }
        Store.shared.nav = .practice
    }

    /// The unfinished set made today from these blocks, or the unfinished full test.
    func current(_ blocks: [Block], test: Bool = false) -> String? {
        let name = test ? "Full test" : Self.label(blocks)
        return (sets + drafts.values).first { !$0.done && $0.full == test && $0.domain == name && (test || Calendar.current.isDateInToday($0.date)) }?.id
    }

    /// Retry: the failed parts run again.
    func retry(_ id: String, _ pids: [String]) {
        for pid in pids where parts[id]?.first(where: { $0.id == pid })?.error != nil { spawn(id) { await self.run(id, pid) } }
    }

    func start(_ id: String) {
        started.insert(id)
        if set(id)?.full == true || parts[id]?.allSatisfy(\.finished) == true { close(id) }   // nothing left to write: the progress view goes
        open = id
    }

    /// Gives up on what is still unwritten; questions already kept stay in their set.
    func close(_ id: String) {
        parts[id] = nil; drafts[id] = nil; tasks[id] = nil
        if building == id { building = nil }
    }

    /// Cancel: stops the writing and keeps nothing of it, unless the student already started the set.
    func cancel(_ id: String) {
        tasks[id]?.forEach { $0.cancel() }
        if !started.contains(id) { sets.removeAll { $0.id == id } }
        close(id)
    }

    /// Throws a set away, with anything still being written for it.
    func discard(_ id: String) {
        started.remove(id); cancel(id)
        if open == id { open = nil }
    }

    func restart(_ id: String) { update(id) { $0.restart() } }

    /// Progress for one set: a row per block, or per module of a full test.
    struct Row: Identifiable {
        var id: String, title: String, section: String
        var ready: Int, of: Int, dropped = 0
        var step = "", error: String? = nil
        var parts: [String] = []
    }

    func rows(_ id: String) -> [Row] {
        let ps = parts[id] ?? []
        guard let s = set(id) ?? drafts[id] else { return [] }
        guard let mods = s.modules else {
            return ps.map { Row(id: $0.id, title: $0.title, section: $0.section, ready: $0.kept, of: $0.slots.count, dropped: $0.done - $0.kept, step: $0.step, error: $0.error, parts: [$0.id]) }
        }
        return mods.enumerated().map { m, mod in
            let mine = ps.filter { $0.module == m }
            var r = Row(id: "\(m)", title: "\(Sec.name(mod.section)) · Module \(mod.number)", section: mod.section, ready: mod.count, of: mod.size, parts: mine.map(\.id))
            if mod.count == 0 {
                r.ready = min(mod.size, mine.map(\.got.count).reduce(0, +))
                r.error = mine.compactMap(\.error).first
                r.step = mine.isEmpty ? (mod.number == 2 ? "After Module 1" : "Waiting")
                    : mine.contains { $0.step == "Writing" } ? "Writing" : mine.contains { $0.step == "Checking" } ? "Checking" : mine.allSatisfy(\.finished) ? "" : "Waiting"
            }
            return r
        }
    }

    // MARK: Text

    /// Bluebook's serif for passages, questions and choices; math between $ signs goes through `Rich`, like every equation in
    /// the app, and <u>…</u> is underlined as the SAT underlines a sentence or claim.
    static func serif(_ s: String, size: CGFloat = 18, ink: Color = Rich.ink) -> Text {
        let parts = Rich.dollars(s).components(separatedBy: "$")   // Khan's \(…\) and \[…\] too
        var out = Text(verbatim: "")
        for (i, p) in parts.enumerated() where !p.isEmpty {
            if i % 2 == 1 && i < parts.count - 1 { out = Text("\(out)\(Rich.text("$\(p)$", size: size - 1, color: .primary, ink: ink))"); continue }
            for (j, t) in p.replacingOccurrences(of: "</u>", with: "<u>").components(separatedBy: "<u>").enumerated() where !t.isEmpty {
                out = Text("\(out)\(Text(verbatim: t).font(.custom("STIX Two Text", size: size)).underline(j % 2 == 1))")
            }
        }
        return out
    }

    @ViewBuilder static func calculator(_ ex: [String], focus: String? = nil) -> some View {
        Group {
            if shared.desmos { DesmosView(expressions: ex, focus: focus) }
            else { ZStack { Palette.well; Image(systemName: "function").font(.system(size: 40)).foregroundStyle(.tertiary) } }
        }
        .clipShape(RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }
}

/// A passage as set on the test: paragraphs in the serif, and lines with " | " cells drawn as a table.
struct PassageText: View {
    let text: String
    var size: CGFloat = 17
    var ink: Color = Rich.ink

    var body: some View {
        let groups = text.components(separatedBy: "\n").reduce(into: [(table: Bool, lines: [String])]()) { g, l in
            let t = l.contains(" | ")
            if let last = g.last, last.table == t { g[g.count - 1].lines.append(l) } else { g.append((t, [l])) }
        }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups.indices, id: \.self) { k in
                if groups[k].table {
                    let rows = groups[k].lines.map { $0.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) } }
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(rows.indices, id: \.self) { r in
                            GridRow {
                                ForEach(rows[r].indices, id: \.self) { c in
                                    Practice.serif(rows[r][c], size: size - 2, ink: ink).fontWeight(r == 0 ? .semibold : .regular)
                                        .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                                        .border(Color.primary.opacity(0.45), width: 0.5)
                                }
                            }
                        }
                    }
                } else {
                    Practice.serif(groups[k].lines.joined(separator: "\n"), size: size, ink: ink).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Practice page

struct PracticeView: View {
    @ObservedObject var practice = Practice.shared
    @ObservedObject var store = Store.shared
    @State private var full: Bool
    @State private var testSections = "Both"
    @State private var picking = false
    @State private var chosen: Set<String> = []
    @State private var naming = false
    @State private var renaming: String?
    @State private var name = ""

    init(full: Bool = false) { _full = State(initialValue: full) }

    var body: some View {
        if let id = practice.open, let s = practice.set(id) {
            if s.done { PracticeResults(id: id).id(id) } else { PracticeTest(id: id).id(id) }
        } else {
            VStack(alignment: .leading, spacing: L.gap) {
                PageTitle(title: "Practice")
                HStack(alignment: .top, spacing: L.gap) {
                    Group {
                        if let b = practice.building { Panel("Writing questions", icon: "hourglass") { progress(b) } }
                        else { Panel("New set", icon: "pencil.and.list.clipboard") { builder } }
                    }
                    .frame(width: 480)
                    Panel("Past sets", icon: "clock.arrow.circlepath") { past }
                }
            }
            .padding(L.gap)
            .onAppear { if practice.blocks.isEmpty { practice.blocks = [Practice.defaultBlock()] } }
        }
    }

    // MARK: Builder

    private var builder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Segments(items: [("Practice questions", false), ("Full test", true)], value: $full)
            if full { testSetup } else { blockSetup }
            if let e = practice.error { Text(e).font(T.caption).foregroundStyle(Palette.wrong) }
        }
    }

    private var blockSetup: some View {
        let rwN = practice.blocks.filter { $0.section == Practice.rw }.map(\.count).reduce(0, +)
        let mathN = practice.blocks.filter { $0.section == Sec.math }.map(\.count).reduce(0, +)
        let over = rwN > Practice.cap(Practice.rw) || mathN > Practice.cap(Sec.math)
        let secs = Set(practice.blocks.map(\.section))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Menu("Presets") {
                    ForEach(Practice.presets, id: \.self) { p in Button(p) { practice.blocks = Practice.preset(p, store.sessions) } }
                    Divider()
                    Button("From my results…") { chosen = Set(store.sessions.map(\.id)); picking = true }
                }
                .fixedSize()
                .popover(isPresented: $picking, arrowEdge: .bottom) { resultsPicker }
                Menu("Templates") {
                    ForEach(practice.templates) { t in
                        Menu(t.name) {
                            Button("Use") { practice.blocks = t.blocks.map { var b = $0; b.id = UUID().uuidString; return b } }
                            Button("Rename…") { name = t.name; renaming = t.id }
                            Button("Delete", role: .destructive) { practice.templates.removeAll { $0.id == t.id } }
                        }
                    }
                    if !practice.templates.isEmpty { Divider() }
                    Button("Save as Template…") { name = ""; naming = true }.disabled(practice.blocks.isEmpty)
                }
                .fixedSize()
                Spacer()
                Button { practice.blocks.append(Block(section: practice.blocks.last?.section ?? Practice.rw)) } label: { Label("Add", systemImage: "plus") }
                    .disabled(practice.blocks.count >= 12)
            }
            .controlSize(.small)
            List {
                ForEach($practice.blocks) { $b in
                    row($b)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                .onMove { practice.blocks.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 160)
            HStack(spacing: 14) {
                if rwN > 0 { total(Practice.rw, rwN) }
                if mathN > 0 { total(Sec.math, mathN) }
                Spacer()
                let secsTime = Double(rwN) * PracticeSet.pace(Practice.rw) + Double(mathN) * PracticeSet.pace(Sec.math)
                Label("\(Int((secsTime / 60).rounded())) min", systemImage: "clock").font(T.caption).foregroundStyle(.secondary).monospacedDigit()
                Toggle("Timer", isOn: $practice.timer).toggleStyle(.switch).controlSize(.mini).font(T.caption)
            }
            startButton(secs.count == 1 ? Sec.color(secs.first!) : .accentColor, disabled: practice.blocks.isEmpty || over) {
                practice.make(practice.blocks, timer: practice.timer)
            }
        }
        .alert("Save as Template", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Save") { practice.templates.append(Template(name: name.isEmpty ? Practice.label(practice.blocks) : name, blocks: practice.blocks)) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Template", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") { if let r = renaming, !name.isEmpty, let i = practice.templates.firstIndex(where: { $0.id == r }) { practice.templates[i].name = name } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func total(_ sec: String, _ n: Int) -> some View {
        let over = n > Practice.cap(sec)
        return Label { Text("\(n) of \(Practice.cap(sec))").monospacedDigit() } icon: { Image(systemName: Sec.icon(sec)).foregroundStyle(Sec.color(sec)) }
            .font(T.caption).foregroundStyle(over ? Palette.wrong : .secondary)
    }

    /// One block: drag it by the handle; topic, difficulty and count in place, then the Math format and a note to the writer;
    /// duplicate or remove from its menu.
    private func row(_ b: Binding<Block>) -> some View {
        let v = b.wrappedValue
        let one = Practice.skills.first { $0.name == v.skill }
        return VStack(alignment: .leading, spacing: 4) { HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).frame(width: 14)
            Image(systemName: Sec.icon(v.section)).foregroundStyle(Sec.color(v.section)).frame(width: 18)
            // Its own equatable view: progress ticks redraw this page, and a rebuilt Menu closes its open submenus.
            TopicMenu(id: v.id, title: v.title) { sec, d, sk in   // by id: a kept-over closure must not edit a block that moved
                guard let i = practice.blocks.firstIndex(where: { $0.id == v.id }) else { return }
                practice.blocks[i].section = sec; practice.blocks[i].domain = d; practice.blocks[i].skill = sk; practice.blocks[i].mine = nil
            }.equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Picker("", selection: b.difficulty) { ForEach(Practice.tiers + ["Mixed"], id: \.self) { Text($0).tag($0) } }
                .labelsHidden().fixedSize()
            Stepper(value: b.count, in: 1...10) { Text("\(v.count)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 20, alignment: .trailing) }
            Menu {
                Button("Duplicate") { if let i = practice.blocks.firstIndex(of: v) { var c = v; c.id = UUID().uuidString; practice.blocks.insert(c, at: i + 1) } }
                Button("Remove", role: .destructive) { practice.blocks.removeAll { $0.id == v.id } }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        HStack(spacing: 8) {
            if v.section == Sec.math, one.map({ $0.spr > 0 }) ?? true {   // a skill that is always multiple choice has no choice here
                Picker("", selection: b.format) {
                    Text("Both formats").tag(String?.none)
                    Text(Practice.choice).tag(String?.some(Practice.choice))
                    Text("Grid-in").tag(String?.some(Practice.grid))
                }
                .labelsHidden().fixedSize()
            }
            TextField("Focus", text: Binding(get: { v.focus ?? "" }, set: { b.wrappedValue.focus = $0.isEmpty ? nil : String($0.prefix(Practice.focusLimit)) }))
                .textFieldStyle(.plain)
        }
        .controlSize(.small).font(.system(size: 12))
        .padding(.leading, 48)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 40)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    private var resultsPicker: some View {
        let tests = store.sessions.filter { s in s.keys.contains { s.correct($0) != nil } }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Build from").font(T.card)
            Toggle("All tests", isOn: Binding(get: { chosen.isSuperset(of: tests.map(\.id)) }, set: { chosen = $0 ? Set(tests.map(\.id)) : [] }))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tests) { s in
                        Toggle(isOn: Binding(get: { chosen.contains(s.id) }, set: { if $0 { chosen.insert(s.id) } else { chosen.remove(s.id) } })) {
                            Text("\(s.title)\(s.logged ? " · logged" : "")").lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            HStack {
                Spacer()
                Button("Build") { practice.blocks = Practice.fromResults(tests.filter { chosen.contains($0.id) }); picking = false }
                    .buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
            }
        }
        .font(.system(size: 13))
        .padding(L.inset).frame(width: 300)
    }

    private var testSetup: some View {
        let secs = testSections == "Both" ? [Practice.rw, Sec.math] : [testSections]
        let minutes = secs.map { Int(Sec.limit($0) / 60) * 2 }.reduce(0, +) + (secs.count > 1 ? 10 : 0)
        return VStack(alignment: .leading, spacing: 12) {
            Segments(items: [("Both", "Both"), (Sec.name(Practice.rw), Practice.rw), ("Math", Sec.math)], value: $testSections)
            VStack(spacing: 6) {
                ForEach(secs, id: \.self) { sec in
                    ForEach([1, 2], id: \.self) { n in
                        HStack(spacing: 10) {
                            Image(systemName: Sec.icon(sec)).foregroundStyle(Sec.color(sec)).frame(width: 18)
                            Text("\(Sec.name(sec)) · Module \(n)").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Practice.cap(sec)) questions · \(Int(Sec.limit(sec) / 60)) min").font(T.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).frame(height: 36)
                        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                    }
                    if sec == Practice.rw, secs.count > 1 {
                        Text("10-minute break").font(T.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 38)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Label("\(minutes / 60) h \(minutes % 60) min", systemImage: "clock").font(T.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Module 2 adapts to Module 1").font(T.caption).foregroundStyle(.secondary)
            }
            startButton(secs.count == 1 ? Sec.color(secs[0]) : .accentColor, disabled: false) { practice.makeTest(secs) }
        }
    }

    private func startButton(_ tint: Color, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text("Start").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent).tint(tint).buttonBorderShape(.roundedRectangle(radius: L.inner))
            .disabled(disabled || !Brain.ready)   // no Return shortcut: generating costs a model call, so only a click starts it
    }

    // MARK: Progress

    private func progress(_ id: String) -> some View {
        let rows = practice.rows(id)
        let s = practice.set(id)
        let ready = rows.map(\.ready).reduce(0, +), of = max(1, rows.map(\.of).reduce(0, +))
        let busy = rows.contains { $0.step == "Writing" || $0.step == "Checking" }
        let canStart = s.map { $0.full ? ($0.modules?.first?.count ?? 0) > 0 : !$0.questions.isEmpty } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(ready)").font(T.big).monospacedDigit()
                Text("of \(of) ready").font(T.body).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(ready), total: Double(of)).tint(Palette.right)
            ScrollView {
                VStack(spacing: 6) { ForEach(rows) { r in progressRow(id, r) } }
            }
            .scrollFade()
            HStack(spacing: 10) {
                // Same height, font and corner as Start: one button family.
                Button { busy ? practice.cancel(id) : practice.close(id) } label: {
                    Text(busy ? "Cancel" : "Close").font(.system(size: 17, weight: .semibold)).frame(width: 140, height: 44)
                }
                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: L.inner))
                .keyboardShortcut(busy ? .cancelAction : nil)
                Button { practice.start(id) } label: {
                    Text(ready >= of ? "Start" : "Start Now").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: L.inner))
                .disabled(!canStart)
            }
        }
    }

    private func progressRow(_ id: String, _ r: Practice.Row) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Sec.icon(r.section)).foregroundStyle(Sec.color(r.section)).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let e = r.error { Text(e).font(T.caption).foregroundStyle(Palette.wrong).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if r.error != nil {
                Button("Retry") { practice.retry(id, r.parts) }.controlSize(.small)
            } else if r.step == "Writing" || r.step == "Checking" {
                ProgressView().controlSize(.small)
                Text("\(r.step) · \(r.ready) of \(r.of)").font(T.caption).foregroundStyle(.secondary).monospacedDigit()
            } else if !r.step.isEmpty {
                Text(r.step).font(T.caption).foregroundStyle(.tertiary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.right)
                Text(r.dropped > 0 ? "\(r.ready) kept · \(r.dropped) dropped" : "\(r.ready) ready").font(T.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    // MARK: Past sets

    /// The same questions again from zero; the earlier score is replaced when the retake is finished.
    private func retake(_ id: String) { practice.restart(id); practice.open = id }

    private var past: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(practice.sets) { s in
                    Button { practice.open = s.id } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 2) { ForEach(s.sections, id: \.self) { Image(systemName: Sec.icon($0)).foregroundStyle(Sec.color($0)) } }
                                .frame(minWidth: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.domain).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Text("\(s.full ? "Full test" : "\(s.questions.count) questions") · \(s.difficulty) · \(s.date.formatted(date: .abbreviated, time: .shortened))").font(T.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if s.done {
                                Text("\(s.score) of \(s.order.count)").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                                    .padding(.trailing, 36)   // room for Retake
                            } else {
                                Text("Resume").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 12).frame(height: 52)
                        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .trailing) {
                        if s.done {
                            Button { retake(s.id) } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28) }
                                .buttonStyle(.borderless).help("Retake: the same questions, answers cleared").padding(.trailing, 8)
                        }
                    }
                    .contextMenu {
                        if s.done { Button("Retake", systemImage: "arrow.counterclockwise") { retake(s.id) } }
                        Button("Delete", role: .destructive) { practice.sets.removeAll { $0.id == s.id } }
                    }
                }
            }
        }
        .scrollFade()
    }
}

// MARK: - Explanation

/// The explanation of one question: the key point, why the student's pick fails, the solution, the trap, words, and Desmos.
/// Shown in the results and, in practice questions, under the question once it is checked.
struct PracticeExplain: View {
    let q: PracticeQuestion
    let w: PracticeSet.Work
    var ink: Color = Rich.ink

    var body: some View {
        let ok = Session.same(w.answer, q.correct)
        let mine = w.answer.flatMap { Practice.letters.firstIndex(of: $0) }
        let why = mine.flatMap { q.choiceNotes.indices.contains($0) ? q.choiceNotes[$0] : nil }.flatMap { $0.isEmpty ? nil : $0 } ?? q.trapJa
        VStack(alignment: .leading, spacing: 14) {
            if !q.keyPoint.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "key.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.yellow)
                    Rich.text(q.keyPoint, size: 17, weight: .semibold, color: .primary, ink: ink).textSelection(.enabled)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            }
            if !ok, !why.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    head(w.answer.map { "Why \($0) doesn't work" } ?? "Why you missed it", "xmark.octagon.fill", Palette.wrong)
                    Rich.text(why, color: .primary, ink: ink).textSelection(.enabled)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.wrong.opacity(0.1), in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 24) {
                part("Solution", "lightbulb.fill", .orange) { steps(q.solutionJa) }
                if ok, !q.trapJa.isEmpty { part("Watch out", "exclamationmark.triangle.fill", .orange) { Rich.text(q.trapJa, ink: ink) } }
                let words = q.vocab.filter { $0.en.trimmingCharacters(in: .whitespaces).count > 1 }
                if !words.isEmpty {
                    part("Words", "character.book.closed.fill", .purple) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                            ForEach(words, id: \.self) { v in GridRow { Text(v.term).fontWeight(.semibold).foregroundStyle(Color.primary); Text(v.note).foregroundStyle(Color.primary.opacity(0.7)) } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(L.inset)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            if q.section == Sec.math, !q.desmos.isEmpty {
                Practice.calculator(q.desmos, focus: q.desmosFocus.isEmpty ? nil : q.desmosFocus).frame(height: 320)
            }
        }
    }

    private func head(_ title: String, _ icon: String, _ tint: Color) -> some View {
        Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(tint) }.font(.system(size: 15, weight: .semibold))
    }

    private func part<C: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            head(title, icon, tint)
            // Color.primary, not .secondary: a hierarchical .primary inside .secondary would stay grey, and light grey on the well is hard to read.
            content().font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.8)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Numbered steps with the step number in a circle, as in the question view.
    private func steps(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(QuestionView.steps(text).enumerated()), id: \.offset) { _, l in
                let n = l.prefix(while: \.isNumber), rest = l.dropFirst(n.count)
                if !n.isEmpty, let mark = rest.first, ".)".contains(mark) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(n).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
                        Rich.text(rest.dropFirst().trimmingCharacters(in: .whitespaces), ink: ink)
                    }
                } else { Rich.text(l, ink: ink) }
            }
        }
    }
}

// MARK: - Results

struct PracticeResults: View {
    let id: String
    @ObservedObject var practice = Practice.shared
    @State private var pick: Int?

    var body: some View {
        if let s = practice.set(id), let first = s.order.first {
            let k = pick.flatMap { s.order.contains($0) ? $0 : nil } ?? first
            HStack(alignment: .top, spacing: L.gap) {
                Panel { summary(s, k) }.frame(width: 320)
                Panel { ScrollView { detail(s, k) }.scrollIndicators(.never) }
            }
            .padding(L.gap)
        }
    }

    /// The questions in groups: one per module of a full test, else one.
    private func groups(_ s: PracticeSet) -> [(title: String?, items: [Int])] {
        guard let mods = s.modules else { return [(nil, s.questions.indices.map { $0 })] }
        return mods.filter { $0.count > 0 }.map { ("\(Sec.name($0.section)) · Module \($0.number)", Array($0.range)) }
    }

    private func summary(_ s: PracticeSet, _ k: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { practice.open = nil } label: { Label("Practice", systemImage: "chevron.left") }
                .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(s.score)").font(T.hero)
                Text("of \(s.order.count)").font(T.section).foregroundStyle(.secondary)
            }
            if s.sections.count > 1 {
                HStack(spacing: 16) {
                    ForEach(s.sections, id: \.self) { sec in
                        let sc = s.score(sec)
                        Label { Text("\(sc.right) of \(sc.total)").monospacedDigit() } icon: { Image(systemName: Sec.icon(sec)).foregroundStyle(Sec.color(sec)) }
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(s.domain).lineLimit(2)
                let mods = s.modules?.filter { $0.count > 0 }   // a full test runs on module clocks
                let used = mods.map { $0.map(\.used).reduce(0, +) } ?? s.work.map(\.seconds).reduce(0, +)
                Text("\(s.difficulty) · \(Fmt.clock(used)) of \(Fmt.clock(mods.map { $0.map(\.limit).reduce(0, +) } ?? s.limit))").monospacedDigit()
            }
            .font(T.caption).foregroundStyle(.secondary)
            if let sid = s.session, Store.shared.session(sid) != nil {
                Button { Store.shared.nav = .session(sid) } label: { Label("Open Test Review", systemImage: "chart.bar.fill") }.buttonStyle(.bordered)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups(s), id: \.items) { g in
                        if let t = g.title { Text(t).font(T.card).foregroundStyle(.secondary).padding(.top, 6).padding(.leading, 4) }
                        ForEach(Array(g.items.enumerated()), id: \.element) { n, q in qrow(s, q, n + 1, k) }
                    }
                }
            }
            .scrollFade()
        }
    }

    private func qrow(_ s: PracticeSet, _ q: Int, _ n: Int, _ k: Int) -> some View {
        let ok = s.right(q), w = s.work[q]
        return Button { pick = q } label: {
            HStack(spacing: 10) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(ok ? Palette.right : Palette.wrong)
                Text("Question \(n)").font(.system(size: 13.5, weight: .medium))
                if s.sections.count > 1, s.modules == nil { Image(systemName: Sec.icon(s.questions[q].section)).font(.system(size: 11)).foregroundStyle(Sec.color(s.questions[q].section)) }
                Spacer()
                Text(w.answer ?? "—").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(ok ? Palette.right : Palette.wrong).lineLimit(1)
                Text(Fmt.clock(w.seconds)).font(.system(size: 12)).monospacedDigit().foregroundStyle(w.seconds > s.pace(q) ? Palette.wrong : .secondary).frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(q == k ? Palette.well : .clear, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ s: PracticeSet, _ k: Int) -> some View {
        let q = s.questions[k], w = s.work[k], ok = s.right(k)
        let n = (groups(s).first { $0.items.contains(k) }?.items.firstIndex(of: k) ?? k) + 1
        return VStack(alignment: .leading, spacing: L.gap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Question \(n)").font(T.section)
                Text("\(q.skill) · \(q.difficulty)").font(T.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Label(Fmt.clock(w.seconds), systemImage: "clock").font(T.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {   // the question as it was asked, with the key and the student's pick
                if !q.passage.isEmpty { PassageText(text: q.passage, size: 16) }
                Practice.serif(q.question, size: 16).fixedSize(horizontal: false, vertical: true)
                if q.choices.isEmpty {
                    HStack(spacing: 8) {
                        Text("Correct").foregroundStyle(.secondary)
                        Text(q.correct).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Palette.right)
                        if !ok {
                            Text("You answered").foregroundStyle(.secondary).padding(.leading, L.inner)
                            Text(w.answer ?? "—").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Palette.wrong)
                        }
                    }
                    .font(.system(size: 13.5, weight: .medium))
                } else {
                    ForEach(Array(zip(Practice.letters, q.choices)), id: \.0) { letter, text in
                        let tint: Color? = letter == q.correct ? Palette.right : letter == w.answer ? Palette.wrong : nil
                        HStack(spacing: 12) {
                            Text(letter).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint == nil ? Color.primary : .white)
                                .frame(width: 26, height: 26).background(Circle().fill(tint ?? .clear))
                                .overlay(Circle().strokeBorder(tint ?? Color.primary.opacity(0.5), lineWidth: 1.5))
                            Practice.serif(text, size: 15).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(L.inset)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            PracticeExplain(q: q, w: w)
        }
    }
}


/// The topic picker of a block: section, then domain, then skill.
private struct TopicMenu: View, Equatable {
    let id: String, title: String
    let pick: (String, String, String) -> Void
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.title == b.title }
    var body: some View {
        Menu {
            ForEach([Practice.rw, Sec.math], id: \.self) { sec in
                Menu(Sec.name(sec)) {
                    Button("All Topics") { pick(sec, "", "") }
                    Divider()
                    ForEach(Practice.domains(sec), id: \.self) { d in
                        Menu(d) {
                            Button("All of \(d)") { pick(sec, d, "") }
                            Divider()
                            ForEach(Practice.skills(sec, d), id: \.name) { s in Button(s.name) { pick(sec, d, s.name) } }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}
