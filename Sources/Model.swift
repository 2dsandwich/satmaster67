import Foundation
import SwiftUI

/// One stay on one question. Leaving and coming back makes a second visit.
struct Visit: Codable, Hashable {
    var section = "Math"       // "Math" or "Reading and Writing"; a full Bluebook test has both
    var module: Int
    var number: Int
    var start: Date
    var end: Date?
    var shot: String?          // "shots/M1-7_v2.jpg", the last frame seen during this visit
    var covered: Bool?         // Bluebook's question navigator hides the choices in that frame (nil = not checked yet)
    var pane: [Double]?        // the question pane beside Desmos or a passage: x, y, w, h (0–1, top-left origin)
    var key: String { Session.key(section, module, number) }
    var seconds: Double { (end ?? Date()).timeIntervalSince(start) }
}

struct Vocab: Codable, Hashable {
    var en: String
    var ja: String
    var note: String

    /// The word as listed: lowercase like a dictionary entry ("Barring" → "barring"), unless it's an acronym or a
    /// name with capitals inside it ("NASA", "McDonald").
    var term: String {
        guard let f = en.first, f.isUppercase, !en.dropFirst().contains(where: \.isUppercase) else { return en }
        return f.lowercased() + en.dropFirst()
    }
}

/// What the model returns for one question (field names match the JSON schema in Tutor).
struct Analysis: Codable, Hashable {
    var questionEn: String
    var questionJa: String
    var topic: String
    var skill: String
    var difficulty: String
    var correctAnswer: String
    var studentAnswer: String
    var verdict: String        // correct | wrong | unanswered | unclear
    var solutionJa: String
    var wordingJa: String
    var trapJa: String
    var timeJa: String
    var vocab: [Vocab]
    var mistakeCause: String?  // none | misread | vocabulary | grammar | calculation | concept | time | guess
    var coachLine: String?     // one sentence the coach says about this question
    var keyPhrase: String?     // the English words on screen that decide the question
    var keyPoint: String?      // the one idea to remember (explanations from Nov 6 on)
    var desmos: [String]?      // Desmos expressions that solve or check a Math question (empty when Desmos doesn't help)
    var desmosFocus: String?   // the point on that graph where the answer is read, e.g. "(14,0)"
}

/// The coach's summary of a whole test.
struct Debrief: Codable, Hashable {
    struct Fix: Codable, Hashable {
        var cause: String
        var titleJa: String
        var whyJa: String
        var drillJa: String
        var questions: [String]
    }
    var headlineJa: String
    var summaryJa: String
    var praiseJa: String
    var fixes: [Fix]
    var pacing: String?      // how the time went, with the evidence (reviews from Nov 6 on)
    var goal: String?        // one measurable goal for the next practice test
}

struct ChatLine: Codable, Hashable {
    var fromStudent: Bool
    var text: String
}

struct QState: Codable, Hashable {
    var guessed = false
    var flagged = false
    var mark: Bool?            // the student's own right/wrong; wins over the model's verdict
    var analysis: Analysis?
    var chat: [ChatLine] = []
    var convo: Data?           // raw API messages, replayed unchanged for follow-ups
    var highlight: [Double]?   // key phrase box in the screenshot: x, y, w, h (0–1, top-left origin)
    var error: String?
    var image: String?         // a picture of the question added after the test (e.g. from Khan Academy); wins over the tracker's
    var cause: String?         // older single pick; kept so earlier picks still load
    var causes: [String]?      // why the student says they missed it, one or more (wins over the tutor's guess)
    /// The student's reasons, newest format first.
    var reasons: [String] { causes ?? cause.map { [$0] } ?? [] }
    var memo: String?          // the student's own note on this question
}

struct Session: Codable, Identifiable, Hashable {
    var id: String
    var start: Date
    var end: Date?
    var test: String?          // "SAT Practice 4" or the student's own name for other material
    var section = "Math"
    var source = ""
    var total: Int?            // "of 22" read from Bluebook
    var visits: [Visit] = []
    var q: [String: QState] = [:]
    var debriefs: [String: Debrief] = [:]   // one per section
    var debrief: Debrief?                   // set only on a one-section view from only(_:)
    var official: Official?                 // imported from My Practice

    /// "M1-7" (Math module 1, question 7) or "R2-5" (Reading and Writing module 2, question 5).
    static func key(_ section: String, _ module: Int, _ number: Int) -> String {
        "\(section == "Math" ? "M" : "R")\(module)-\(number)"
    }
    static func section(of key: String) -> String { key.hasPrefix("R") ? "Reading and Writing" : "Math" }
    static func parts(_ key: String) -> (Int, Int, Int) {   // (section order, module, number)
        let p = key.dropFirst().split(separator: "-").compactMap { Int($0) }
        return (key.hasPrefix("R") ? 0 : 1, p.first ?? 0, p.last ?? 0)   // Bluebook order: R&W, then Math
    }

    /// Sections in test order.
    var sections: [String] {
        ["Reading and Writing", "Math"].filter { s in visits.contains { $0.section == s } || (logged && keys.contains { Session.section(of: $0) == s }) }
    }

    /// Logged by hand after the fact: no visits (so no timing), questions from College Board's record.
    var logged: Bool { visits.isEmpty && !(official?.answers.isEmpty ?? true) }

    /// The same test narrowed to one section: its own pace, stats and debrief.
    func only(_ sec: String) -> Session {
        var s = self
        s.section = sec
        s.visits = visits.filter { $0.section == sec }
        if logged { s.official?.answers = (official?.answers ?? [:]).filter { Session.section(of: $0.key) == sec } }
        s.debrief = debriefs[sec]
        return s
    }

    /// Official digital SAT pace: Math 35 min / 22, Reading and Writing 32 min / 27.
    var pace: Double { section == "Reading and Writing" ? 32 * 60 / 27 : 35 * 60 / 22 }

    var keys: [String] {
        (visits.isEmpty ? Set(official?.answers.keys.map { $0 } ?? []) : Set(visits.map(\.key))).map { ($0, Session.parts($0)) }
            .sorted { ($0.1.0, $0.1.1, $0.1.2) < ($1.1.0, $1.1.1, $1.1.2) }.map(\.0)
    }

    /// Tests a visit against `key` by its fields, so no key string is built per visit.
    private func on(_ key: String) -> (Visit) -> Bool {
        let (o, m, n) = Session.parts(key)
        guard Session.key(o == 0 ? "Reading and Writing" : "Math", m, n) == key else { return { _ in false } }
        return { ($0.section == "Math") == (o == 1) && $0.module == m && $0.number == n }
    }

    func seconds(_ key: String, now: Date = Date()) -> Double {
        let f = on(key)
        return visits.reduce(0) { f($1) ? $0 + ($1.end ?? now).timeIntervalSince($1.start) : $0 }
    }

    func visitCount(_ key: String) -> Int { let f = on(key); return visits.count(where: f) }

    /// The student's own picture, else the newest frame that shows every choice, else the newest frame.
    func shot(_ key: String) -> String? {
        if let image = q[key]?.image { return image }
        let f = on(key)
        return (visits.last { f($0) && $0.shot != nil && $0.covered != true } ?? visits.last { f($0) && $0.shot != nil })?.shot
    }

    /// The tutor can explain it: there is a picture, or College Board's question text.
    func explainable(_ key: String) -> Bool { shot(key) != nil || official?.answers[key]?.question != nil }

    /// The part of a screenshot to show: the question and its choices. Math only, so Desmos is left out; R&W keeps the passage.
    func pane(_ shot: String) -> CGRect? {
        guard let v = visits.first(where: { $0.shot == shot }), v.section == "Math", let p = v.pane, p.count == 4 else { return nil }
        return CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
    }

    /// true = right, false = wrong, nil = not known yet.
    func correct(_ key: String) -> Bool? {
        if let m = q[key]?.mark { return m }
        if let a = official?.answers[key] {
            if let r = a.right { return r }
            if !a.correct.isEmpty { return Session.same(a.yours, a.correct) }   // no pick against a known key: omitted, so wrong
            // Nothing known from College Board: the tutor's verdict, or not graded.
        }
        switch q[key]?.analysis?.verdict {
        case "correct": return true
        case "wrong", "unanswered": return false
        default: return nil
        }
    }

    /// Where `correct(key)` comes from.
    func grade(_ key: String) -> Grade? {
        if q[key]?.mark != nil { return .mine }
        if official?.answers[key] != nil { return .official }
        return correct(key) == nil ? nil : .estimate
    }

    /// Answers match ignoring case, spaces and equivalent forms like ".5" and "1/2".
    static func same(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        func norm(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace } }
        func value(_ s: String) -> Double? {
            let p = norm(s).split(separator: "/")
            if p.count == 2, let x = Double(p[0]), let y = Double(p[1]), y != 0 { return x / y }
            return Double(norm(s))
        }
        let options = b.split(separator: ",").map { String($0) }   // grid-ins can list several accepted answers
        return options.contains { o in norm(o) == norm(a) || (value(o) != nil && value(o) == value(a)) }
    }

    var title: String { test ?? start.formatted(date: .abbreviated, time: .shortened) }
    /// The score every list shows (sidebar, menu, Full tests): the scaled total when there is one, else right of marked,
    /// else "No results" once it ended (timed only, its answers not in the app); nil while it runs.
    var scoreNote: String? {
        if let t = official?.total { return t.formatted() }
        let m = keys.filter { correct($0) != nil }
        return !m.isEmpty ? "\(m.count { correct($0) == true })/\(m.count)" : end == nil ? nil : "No results"
    }

    func label(_ key: String) -> String {
        let (_, m, n) = Session.parts(key)
        let groups = Set(keys.map { k -> String in let p = Session.parts(k); return "\(p.0)\(p.1)" })
        guard groups.count > 1 else { return "Q\(n)" }
        return "\(Session.section(of: key) == "Math" ? "M" : "RW")\(m) Q\(n)"
    }

    var studyTime: Double { let now = Date(); return visits.reduce(0) { $0 + ($1.end ?? now).timeIntervalSince($1.start) } }   // every visit belongs to one key

    var modules: [Int] { visits.isEmpty ? Set(keys.map { Session.parts($0).1 }).sorted() : Set(visits.map(\.module)).sorted() }
    func keys(_ module: Int) -> [String] { keys.filter { Session.parts($0).1 == module } }
    /// Time spent on questions in a module (review-page time not counted).
    /// Time in a module, never past its limit (a visit left open on Bluebook's end screen would run over).
    func used(_ module: Int) -> Double {
        var t = 0.0, sec: String?
        for v in visits where v.module == module { t += v.seconds; sec = sec ?? v.section }
        return min(t, (sec == "Math" ? 35 : 32) * 60)
    }
}

enum Fmt {
    static func clock(_ s: Double) -> String {
        let t = max(0, Int(s.rounded()))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    /// Dates as ISO strings with milliseconds. Compact: the files are read back by the app, not by hand.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { d, enc in var c = enc.singleValueContainer(); try c.encode(iso.string(from: d)) }
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = iso.date(from: s) else { throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s)) }
            return date
        }
        return d
    }()
}

/// All tests on disk: ~/Library/Application Support/SAT Tracker/sessions/<id>/
@MainActor final class Store: ObservableObject {
    static let shared = Store()
    @Published var sessions: [Session] = []
    @Published var busy: Set<String> = []     // "<session>/<key>" while the model works
    @Published var nav: Nav? = nil { didSet { if nav != oldValue, leave?(oldValue, nav) == false { nav = oldValue } } }
    var leave: ((Nav?, Nav?) -> Bool)?   // asked before the page changes; false keeps it (a full test in progress asks first)
    /// A whole test being explained: questions finished of total (the debriefs run after done == total). nil when idle.
    @Published var progress: [String: Progress] = [:]
    struct Progress: Hashable { var done: Int; var total: Int }

    enum Nav: Hashable { case today, tutor, plan, practice, cards, vocab, settings, session(String) }

    let root: URL = {
        let base = ProcessInfo.processInfo.environment["SAT_DATA"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SAT Tracker")
        return base.appendingPathComponent("sessions")
    }()

    init() { load() }

    func dir(_ id: String) -> URL { root.appendingPathComponent(id) }

    func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        sessions = dirs.compactMap { try? Fmt.decoder.decode(Session.self, from: Data(contentsOf: $0.appendingPathComponent("session.json"))) }
            .sorted { $0.start > $1.start }
    }

    func session(_ id: String) -> Session? { sessions.first { $0.id == id } }

    /// Where the next test review opens (see `open(_:)` and `Opening`); SessionView takes it and clears it.
    @Published var opening: Opening?

    /// Latest unsaved state per test; written together after a short quiet spell.
    private var pending: [String: Session] = [:]
    private let disk = DispatchQueue(label: "Store.disk")

    func save(_ s: Session) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
        // The folder now: callers write shots and events.jsonl into it straight away.
        try? FileManager.default.createDirectory(at: dir(s.id).appendingPathComponent("shots"), withIntermediateDirectories: true)
        if pending.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in MainActor.assumeIsolated { self?.write() } } }
        pending[s.id] = s
    }

    /// Encodes and writes the pending tests off the main thread, in order.
    private func write() {
        let batch = pending, root = root
        pending = [:]
        guard !batch.isEmpty else { return }
        disk.async {
            // Atomic write: a crash mid-write never loses the test.
            for (id, s) in batch {
                if let data = try? Fmt.encoder.encode(s) { try? data.write(to: root.appendingPathComponent(id).appendingPathComponent("session.json"), options: .atomic) }
            }
        }
    }

    /// Writes everything still pending and waits for the disk. Call before quitting.
    func flush() { write(); disk.sync {} }

    func update(_ id: String, _ change: (inout Session) -> Void) {
        guard var s = session(id) else { return }
        change(&s)
        save(s)
    }

    func delete(_ id: String) {
        pending[id] = nil
        disk.sync {}   // a write already queued must not land after the trash
        try? FileManager.default.trashItem(at: dir(id), resultingItemURL: nil)
        sessions.removeAll { $0.id == id }
        if nav == .session(id) { nav = nil }
    }

    /// Older screenshots: which ones the navigator covers and where the question pane is. Runs once per test, off the main thread.
    func checkShots(_ sid: String) async {
        guard let s = session(sid) else { return }
        let todo = s.visits.indices.filter { s.visits[$0].shot != nil && s.visits[$0].covered == nil }
        guard !todo.isEmpty else { return }
        let dir = dir(sid), visits = s.visits
        let found: [(Int, Capture.Layout)] = await Task.detached {
            todo.compactMap { i in
                guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(visits[i].shot!) as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
                return (i, Capture.layout(img))
            }
        }.value
        update(sid) { s in
            let before = Dictionary(uniqueKeysWithValues: s.keys.map { ($0, s.shot($0)) })
            for (i, l) in found where s.visits.indices.contains(i) {
                s.visits[i].covered = l.covered
                s.visits[i].pane = l.pane.map { r in [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }
            }
            for k in s.keys where s.shot(k) != before[k] ?? nil { s.q[k]?.highlight = nil }   // the marker box was for the old frame
        }
    }
}

