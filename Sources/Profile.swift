import Foundation

/// One official SAT date the student sat or is booked for (or, not booked, is aiming for).
struct Sitting: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var date: Date                      // an official date from SATDates, start of day
    var booked = true                   // false: the date they aim for, not registered yet
    var rw: Int?, math: Int?            // the official section scores, once known
    var snoozedUntil: Date?             // "Not out yet": ask again from this day (scores come out about 2 weeks after)
    var total: Int? { rw.flatMap { r in math.map { r + $0 } } }
}

/// A score the student had before the app: an official SAT or PSAT, or a Bluebook practice test.
struct PriorScore: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case sat, psat, bluebook }
    var id = UUID().uuidString
    var kind: Kind
    var date: Date?
    var testName: String?               // Bluebook: "SAT Practice 4" (that test is then used up)
    var rw: Int?, math: Int?
    var total: Int
}

/// The student's goal and week; set in onboarding, editable in Settings. Saved as profile.json.
struct Profile: Codable, Hashable {
    var sittings: [Sitting] = []        // past and booked official dates; the plan works toward the next booked one
    var priorScores: [PriorScore] = []
    var targetScore = 1400
    var days: Set<Int> = [2, 3, 4, 5, 7] // weekdays they study (Calendar: 1 = Sunday … 7 = Saturday)
    var minutes = 60                    // per study day
    var onboarded = false
    var name = ""
    var grade = 11                      // school grade (9–12)
    var pins: [String: String] = [:]    // "yyyy-MM-dd" → practice test pinned to that day (set by the tutor or you)
    var skips: Set<String> = []         // "yyyy-MM-dd" days off
    var focus: [String] = []            // domains to drill first, overriding the computed priorities
    var reminders = false               // local notifications: study days, test eves, sittings
    var remindAt = 17 * 60              // minutes after midnight for the study-day reminder (product choice: 17:00)

    /// What the plan works toward: the next booked sitting after today; else the date they aim for; else the next official
    /// date at least 8 weeks out (not booked). On a sitting's own day the plan already points at the one after it.
    struct Goal: Hashable { var date: Date; var booked: Bool; var sitting: Sitting? }

    func goal(_ now: Date = Clock.now) -> Goal {
        let cal = Calendar.current, today = cal.startOfDay(for: now)
        let ahead = sittings.filter { cal.startOfDay(for: $0.date) > today }.sorted { $0.date < $1.date }
        if let s = ahead.first(where: \.booked) ?? ahead.first { return Goal(date: cal.startOfDay(for: s.date), booked: s.booked, sitting: s) }
        let eight = cal.date(byAdding: .day, value: 56, to: today)!
        return Goal(date: SATDates.all.map(\.date).first { $0 >= eight } ?? eight, booked: false, sitting: nil)
    }
    /// The next booked sitting, today's included (the countdown reads "Today" on the day).
    func nextSitting(_ now: Date = Clock.now) -> Sitting? {
        let cal = Calendar.current, today = cal.startOfDay(for: now)
        return sittings.filter { $0.booked && cal.startOfDay(for: $0.date) >= today }.min { $0.date < $1.date }
    }
    /// Booked sittings before today with no score yet, unless snoozed: ask how it went.
    func needsScore(_ now: Date = Clock.now) -> [Sitting] {
        let cal = Calendar.current, today = cal.startOfDay(for: now)
        return sittings.filter { $0.booked && $0.total == nil && cal.startOfDay(for: $0.date) < today && ($0.snoozedUntil.map { cal.startOfDay(for: $0) <= today } ?? true) }
            .sorted { $0.date < $1.date }
    }

    /// The day the countdown counts to: the next booked sitting (today's too), else the plan's goal.
    var deadline: Date? { nextSitting()?.date ?? goal().date }
    var daysLeft: Int? {
        deadline.map { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Clock.now), to: $0).day ?? 0) }
    }

    /// The next booked sitting's date. Setting it moves only that sitting (or books one); nil un-books it.
    var nextBooked: Date? {
        get { nextSitting()?.date }
        set {
            let next = nextSitting()
            sittings.removeAll { $0.id == next?.id || (!$0.booked && $0.date > Clock.now) }
            if let d = newValue.map(Calendar.current.startOfDay) {
                sittings.removeAll { Calendar.current.isDate($0.date, inSameDayAs: d) && $0.total == nil }
                sittings.append(Sitting(id: next?.id ?? UUID().uuidString, date: d))
            }
            sittings.sort { $0.date < $1.date }
        }
    }
    /// The official date they aim for while nothing is booked.
    var aim: Date? {
        get { let g = goal(); return g.booked || g.sitting == nil ? nil : g.date }
        set {
            sittings.removeAll { !$0.booked && $0.date > Clock.now }
            if let d = newValue { sittings.append(Sitting(date: Calendar.current.startOfDay(for: d), booked: false)); sittings.sort { $0.date < $1.date } }
        }
    }
}

extension Profile {
    private enum Legacy: String, CodingKey { case testDate, targetMonth, startScore }

    /// Every field is optional on disk, so a profile saved by any earlier version loads. The single test date of
    /// earlier versions becomes a booked sitting; an aimed-for month becomes that month's official SAT date (not booked).
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ v: inout T) { if let x = try? c.decodeIfPresent(T.self, forKey: k) { v = x } }
        get(.sittings, &sittings); get(.priorScores, &priorScores); get(.targetScore, &targetScore); get(.days, &days)
        get(.minutes, &minutes); get(.onboarded, &onboarded); get(.name, &name); get(.grade, &grade); get(.pins, &pins)
        get(.skips, &skips); get(.focus, &focus); get(.reminders, &reminders); get(.remindAt, &remindAt)
        guard !c.contains(.sittings), let old = try? decoder.container(keyedBy: Legacy.self) else { return }
        let cal = Calendar.current
        if let t = try? old.decodeIfPresent(Date.self, forKey: .testDate) {
            sittings = [Sitting(date: cal.startOfDay(for: t))]
        } else if let m = try? old.decodeIfPresent(Date.self, forKey: .targetMonth) {
            let d = SATDates.all.map(\.date).first { cal.isDate($0, equalTo: m, toGranularity: .month) } ?? SATDates.all.map(\.date).first { $0 >= m }
            sittings = [Sitting(date: cal.startOfDay(for: d ?? m), booked: false)]
        }
        if let s = try? old.decodeIfPresent(Int.self, forKey: .startScore) { priorScores = [PriorScore(kind: .sat, total: s)] }
    }
}

/// What College Board's My Practice "Score Details" page says about one test, imported from the page text.
struct Official: Codable, Hashable {
    struct Answer: Codable, Hashable {
        var correct: String                 // official correct answer ("B", "24", "1/24")
        var yours: String?                  // what the student entered, nil if omitted
        var question: String?               // question text when the page includes it
        var passage: String?                // the text the question is about (from Khan Academy's copy of the test)
        var choices: [String]?              // A to D without letters; nil for a grid-in or when not known
        var explanation: String?
        var domain: String?, skill: String?, difficulty: String?
        var right: Bool?                    // My Practice's Correct/Incorrect when the answer letters aren't on the page
    }
    var imported = Date()
    var total: Int?, readingWriting: Int?, math: Int?
    var answers: [String: Answer] = [:]     // by question key: "R1-3", "M2-14"
    var raw = ""                            // the page text as received, kept so it can be read again later
}

/// Where a right/wrong comes from, strongest first.
enum Grade: String { case mine = "You", official = "Official", estimate = "Estimate" }

/// Small JSON files next to the sessions folder.
enum Files {
    static let base: URL = ProcessInfo.processInfo.environment["SAT_DATA"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SAT Tracker")
    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        (try? Data(contentsOf: base.appendingPathComponent(name))).flatMap { try? Fmt.decoder.decode(T.self, from: $0) }
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let d = try? Fmt.encoder.encode(value) { try? d.write(to: base.appendingPathComponent(name), options: .atomic) }
    }
}
