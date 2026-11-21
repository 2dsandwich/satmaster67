import Foundation

/// A change to the plan the student accepts or dismisses; never applied silently (requirement 3). Saved in suggestions.json.
struct Suggestion: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case info, change, askScore, chat }
    enum State: String, Codable { case pending, accepted, dismissed }
    var id = UUID().uuidString
    var kind: Kind
    var trigger: String                 // what raised it; once seen, the same trigger never raises another
    var title: String
    var why: String
    var changes: [PlanChange] = []
    var sitting: String? = nil          // askScore: the sitting to score
    var created = Clock.now
    var state = State.pending
}

/// One edit to the profile, checked when it is made (Coach.parse, Adviser).
enum PlanChange: Codable, Hashable {
    case minutes(Int)
    case days([Int])                    // Calendar weekdays, 1 = Sunday
    case moveSitting(id: String, to: Date)   // id "" books a new sitting
    case target(Int)
    case dayOff(String), dayOn(String)  // "yyyy-MM-dd"
    case pin(date: String, test: String)
    case focus([String])
    case clearFocus

    func apply(_ p: inout Profile) {
        let cal = Calendar.current
        switch self {
        case .minutes(let m): p.minutes = m
        case .days(let d): p.days = Set(d)
        case .moveSitting(let id, let to):
            let d = cal.startOfDay(for: to)
            p.sittings.removeAll { cal.isDate($0.date, inSameDayAs: d) && $0.id != id && $0.total == nil }
            if let i = p.sittings.firstIndex(where: { $0.id == id }) { p.sittings[i].date = d; p.sittings[i].booked = true }
            else { p.sittings.removeAll { !$0.booked && $0.date > Clock.now }; p.sittings.append(Sitting(date: d)) }
            p.sittings.sort { $0.date < $1.date }
        case .target(let t): p.targetScore = t
        case .dayOff(let d): p.skips.insert(d)
        case .dayOn(let d): p.skips.remove(d)
        case .pin(let date, let test): p.pins = p.pins.filter { $0.value != test }; p.pins[date] = test; p.skips.remove(date)
        case .focus(let f): p.focus = f
        case .clearFocus: p.focus = []
        }
    }

    /// How a chip names it: "60 min a day", "SAT Practice 7 on Thursday, Nov 12".
    @MainActor var label: String {
        let names = Calendar.current.shortWeekdaySymbols
        func when(_ s: String) -> String { Planner.day.date(from: s).map(Coach.label) ?? s }
        switch self {
        case .minutes(let m): return "\(m) min a day"
        case .days(let d): return "Study days: " + d.sorted().map { names[$0 - 1] }.joined(separator: " ")
        case .moveSitting(_, let to): return "Test day \(Coach.label(to))"
        case .target(let t): return "Target \(t)"
        case .dayOff(let d): return "\(when(d)) off"
        case .dayOn(let d): return "Studying \(when(d)) again"
        case .pin(let date, let test): return "\(test) on \(when(date))"
        case .focus(let f): return "Focus: " + f.joined(separator: ", ")
        case .clearFocus: return "Focus back to automatic"
        }
    }
}

/// Watches the plan and raises suggestions (spec 1.5). Pure: the store keeps them and drops triggers already seen.
enum Adviser {
    struct State {
        var profile: Profile
        var today: Date
        var baseline: Planner.Baseline?
        var feasibility: Planner.Feasibility
        var history: [StudyDay]
        var days: [StudyDay]
        var mastery: Mastery
    }

    static let steps = [30, 45, 60, 90, 120]

    static func make(_ s: State) -> [Suggestion] {
        let cal = Calendar.current, p = s.profile, f = s.feasibility
        var out: [Suggestion] = []
        let fmt: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }

        // A sitting passed with no score: ask (1.1).
        for x in p.needsScore(s.today) {
            out.append(Suggestion(kind: .askScore, trigger: "score-ask:\(x.id):\(x.snoozedUntil.map(Planner.day.string) ?? "")", title: "How did \(fmt(x.date)) go?",
                                  why: "Add your R&W and Math scores when they are out.", sitting: x.id))
        }

        // The final week and a sitting's own day: nothing to change any more, only the score to ask for.
        let left = cal.dateComponents([.day], from: cal.startOfDay(for: s.today), to: p.goal(s.today).date).day ?? 0
        if left <= 7 || p.sittings.contains(where: { cal.isDate($0.date, inSameDayAs: s.today) }) { return out }

        // A new score: the priorities are re-ranked (info); if the hours needed outrun the plan by >25%, a bigger week or a later date (R2, R14).
        if let b = s.baseline {
            let top = s.mastery.priorities(target: p.targetScore, focus: p.focus).map(\.short)
            out.append(Suggestion(kind: .info, trigger: "rank:\(b.id)", title: "Priorities: " + top.joined(separator: ", "), why: "Re-ranked after \(b.source)\(b.date.map { " on " + fmt($0) } ?? "") (\(b.total.formatted()))."))
            if f.status == .notEnough {
                let need = f.neededPerWeek, plannedPerWeek = f.plannedHours / f.weeks
                // Planned hours scale with minutes a day and with study days.
                let more = steps.first { $0 > p.minutes && plannedPerWeek * Double($0) / Double(p.minutes) >= need }
                let extra = extraDay(p)
                let why = "\(Int(need.rounded())) h a week needed for \(p.targetScore - b.total) points, the plan has \(Int(plannedPerWeek.rounded())) h."
                if let m = more {
                    out.append(Suggestion(kind: .change, trigger: "hours:\(b.id)", title: "Study \(m) min a day?", why: why, changes: [.minutes(m)]))
                } else if let e = extra, p.days.count < 6, plannedPerWeek * Double(p.days.count + 1) / Double(p.days.count) >= need {
                    out.append(Suggestion(kind: .change, trigger: "hours:\(b.id)", title: "Add \(cal.weekdaySymbols[e - 1])?", why: why, changes: [.days((p.days.sorted() + [e]))]))
                } else if let later = SATDates.all.map(\.date).first(where: { $0 > p.goal(s.today).date }) {
                    out.append(Suggestion(kind: .change, trigger: "hours:\(b.id)", title: "Aim for \(fmt(later)) instead?", why: why,
                                          changes: [.moveSitting(id: p.goal(s.today).sitting?.id ?? "", to: later)]))
                }
            }
        }

        // Two or more planned study days missed in the last 7: a lighter week (R14).
        let week = s.history.filter { cal.dateComponents([.day], from: $0.date, to: s.today).day! <= 7 && $0.tasks.contains { $0.kind != .rest } }
        let missed = week.filter { !$0.tasks.contains(where: \.done) && $0.tasks.contains(where: \.missed) }
        if missed.count >= 2 {
            let lower = steps.last { $0 < p.minutes }
            let why = "\(missed.count) study days missed this week: " + missed.map { $0.date.formatted(.dateTime.weekday(.abbreviated)) }.joined(separator: ", ") + "."
            let key = "missed:\(Planner.day.string(from: missed.last!.date))"
            if let l = lower { out.append(Suggestion(kind: .change, trigger: key, title: "Lighter days: \(l) min?", why: why, changes: [.minutes(l)])) }
            else if let e = extraDay(p) { out.append(Suggestion(kind: .change, trigger: key, title: "Add \(cal.weekdaySymbols[e - 1])?", why: why, changes: [.days(p.days.sorted() + [e])])) }
        }

        // A skill mastered drops out of the drills on its own; say so (R14, KA-mastery).
        for a in s.mastery.mastered {
            out.append(Suggestion(kind: .info, trigger: "mastered:\(a.id)", title: "\(a.name) mastered", why: "\(a.recentRight) of \(a.recentSeen) right in 30 days: out of the drills."))
        }

        // Bluebook's 8 tests run out before the sitting: later full tests are in the app (R3).
        if let d = s.days.first(where: { $0.tasks.contains { $0.target == .appTest } }), d.date <= p.goal(s.today).date {
            out.append(Suggestion(kind: .info, trigger: "bluebook-out:\(Planner.day.string(from: p.goal(s.today).date))", title: "Bluebook tests run out",
                                  why: "All 8 are used by then; from \(fmt(d.date)) full tests are in the app."))
        }

        // Fewer than 4 study days with a gap of 70+ points: one more day (R12).
        if let b = s.baseline, p.targetScore - b.total > 70, p.days.count < 4, let e = extraDay(p) {
            out.append(Suggestion(kind: .change, trigger: "days:\(p.days.sorted())", title: "Add \(cal.weekdaySymbols[e - 1])?",
                                  why: "\(p.targetScore - b.total) points to go; 5 to 6 study days a week work best.", changes: [.days(p.days.sorted() + [e])]))
        }
        return out
    }

    /// Pending suggestions take the text raised now for the same trigger, so a number in one always matches the screen.
    static func update(_ log: inout [Suggestion], from new: [Suggestion]) -> Bool {
        var changed = false
        for i in log.indices where log[i].state == .pending {
            guard let n = new.first(where: { $0.trigger == log[i].trigger }), (n.title, n.why, n.changes) != (log[i].title, log[i].why, log[i].changes) else { continue }
            log[i].title = n.title; log[i].why = n.why; log[i].changes = n.changes; changed = true
        }
        return changed
    }

    /// The day to add: a weekend day first (room for full tests), else the first weekday not studied.
    static func extraDay(_ p: Profile) -> Int? { ([7, 1] + Array(2...6)).first { !p.days.contains($0) } }
}
