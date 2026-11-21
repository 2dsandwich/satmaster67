import Combine
import SwiftUI

// MARK: - Study plan engine. API for the screens
//
// Everything reads `PlanStore.shared` (@MainActor ObservableObject). Rules cite tutor-research.md (R1–R15).
//
// Goal and sittings (Profile.swift)
//   plan.profile: Profile                  @Published; assign to change. sittings, priorScores, days, minutes, targetScore,
//                                          focus, skips, pins, reminders (Bool), remindAt (minutes after midnight)
//   plan.nextSitting: Sitting?             next booked sitting, today's included: the countdown ("Today" on the day)
//   plan.goal: Profile.Goal                date the plan works toward (after today), booked or not ("Mar 6 · Not booked")
//   plan.needsScore: [Sitting]             booked sittings before today without a score, not snoozed ("How did Nov 7 go?")
//   plan.recordScore(sitting:rw:math:)     official section scores; total = sum; re-plans
//   plan.snooze(sitting:)                  "Not out yet": asks again in 7 days (Sitting.snoozedUntil)
//   plan.baseline: Planner.Baseline?       latest of official sitting, test official total, prior score (spec 1.2)
//
// The plan
//   plan.days: [StudyDay]                  today up to the sitting; plan.history: past days with done / missed
//   plan.today: StudyDay?                  today's session (nil: no study today)
//   StudyDay: date, phase, tasks, minutes, minutesDone
//   StudyTask: id (UUID, stable across re-plans), kind, title, short (pill: "Words in Context + Boundaries", "Review Practice 9", "Redo 12"),
//              detail, minutes, why (one line from data),
//              target (what Start opens: TaskTarget), count (cards to redo / misses to review), done, carried, missed,
//              blocks ([Block] for a .practice target: hand to Practice.make)
//   plan.toggle(day, task) / plan.isDone(day, task)
//   plan.phases: [(phase, days)]           in order, study days per phase
//   plan.feasibility: Planner.Feasibility  gap, weeks, neededHours (gap table R2), plannedHours, neededPerWeek,
//                                          budgetPerWeek (hours), status: onTrack | tight | notEnough | unknown (no score)
//   plan.mastery: Mastery                  .ranking(target:focus:) priorities, .mastered, .weakest, .domains, .skills
//   plan.streak, plan.active(day)
//
// Suggestions (Suggestions.swift)
//   plan.suggestions: [Suggestion]         pending, newest first: kind, title, why, changes ([PlanChange]), sitting, state
//   plan.accept(id) / plan.dismiss(id)     accept applies the change and re-plans; a dismissed trigger never returns
//   plan.suggestionLog / plan.suggestion(id) every suggestion with its state: pending | accepted | dismissed (chat card)
//
// Notifications (Notify.swift)
//   Notifier.permission() async -> Bool    ask once (onboarding / Settings), then set profile.reminders = true
//   Notifier.scheduled: [Reminder]         what is scheduled (or would be, under SAT_DATA)

/// "Now" for the plan and every screen built on it; snapshots shift it to render the plan on another day.
enum Clock {
    nonisolated(unsafe) static var shift: TimeInterval = 0
    static var now: Date { Date().addingTimeInterval(shift) }
}

extension Calendar {
    func isToday(_ d: Date) -> Bool { isDate(d, inSameDayAs: Clock.now) }
}

/// What Start opens for a task.
enum TaskTarget: Codable, Hashable {
    case bluebook(String)         // a Bluebook full test by name
    case appTest                  // an in-app full practice test
    case review(String)           // a finished test's misses (session id; "" for a test still to come)
    case errorLog                 // every miss so far, final week
    case cards                    // the mistake flashcards due
    case words                    // the Words deck
    case practice([Drill])        // an in-app Practice set
    case module(String)           // a timed module preset: Practice.rw or Sec.math
    case none
}

/// One skill (or domain) in a drill set, at one difficulty.
struct Drill: Codable, Hashable { var section: String; var domain: String; var skill: String; var difficulty: String; var count: Int }

/// One thing to do on one day.
struct StudyTask: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case test, review, cards, drill, module, words, rest }
    var id = UUID().uuidString
    var kind: Kind
    var title: String
    var detail: String
    var minutes: Int
    var why = ""
    var target = TaskTarget.none
    var count: Int? = nil
    var done = false
    var carried = false                // brought from an earlier day that was missed
    var missed = false                 // a past day's task left undone

    var test: String? { if case .bluebook(let n) = target { n } else { nil } }
    /// A few characters for a week pill.
    var short: String {
        switch target {
        case .bluebook(let n): n
        case .appTest: "Full test"
        case .review: title
        case .errorLog: "Error log"
        case .cards: line
        case .words: "Words"
        case .module(let s): s == Sec.math ? "Math module" : "R&W module"
        case .practice(let d): d.map { Mastery.short($0.skill.isEmpty ? $0.domain : $0.skill) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " + ")
        case .none: title
        }
    }
    /// How the task reads in one line of text (tutor greeting, notification, menu): the title, the cards with their count.
    var line: String { kind == .cards ? "Redo \(count ?? 0) misses" : title }
    var domain: String? { if case .practice(let d) = target { d.first?.domain } else { nil } }
    var blocks: [Block]? {
        guard case .practice(let d) = target else { return nil }
        return d.map { Block(section: $0.section, domain: $0.domain, skill: $0.skill, difficulty: $0.difficulty, count: $0.count, mine: true) }
    }
    /// What the task is, so a re-plan keeps its id and tick.
    var key: String {
        switch target {
        case .practice(let d): "drill|" + d.map { $0.skill.isEmpty ? $0.domain : $0.skill }.joined(separator: "+")
        case .review(let id): "review|\(id)"
        case .bluebook(let n): "test|\(n)"
        case .module(let s): "module|\(s)"
        default: "\(kind.rawValue)|\(target)"
        }
    }

    var icon: String {
        if target == .errorLog { return "tray.full.fill" }
        return switch kind {
        case .test: "doc.text.fill"
        case .review: "magnifyingglass"
        case .cards: "rectangle.on.rectangle.angled"
        case .drill: "dumbbell.fill"
        case .module: "stopwatch.fill"
        case .words: "character.book.closed.fill"
        case .rest: "moon.zzz.fill"
        }
    }

    /// The section a drill or timed module works on (nil for other tasks).
    var section: String? {
        if let d = domain { return Planner.mathDomains.contains(d) ? Sec.math : Practice.rw }
        if case .module(let s) = target { return s == Sec.math ? Sec.math : Practice.rw }
        return nil
    }
    /// Drills and timed modules take their section's color; other tasks their kind's.
    var tint: Color { section.map(Sec.color) ?? kind.tint }
}

enum Phase: String, CaseIterable, Codable {
    case diagnose = "Diagnose", build = "Build", practice = "Practice tests", taper = "Final week"   // saved in plan.json
    /// How screens name it.
    var name: String { self == .build ? "Skill building" : rawValue }
}

struct StudyDay: Codable, Identifiable, Hashable {
    var date: Date
    var phase: Phase
    var tasks: [StudyTask]
    var id: Date { date }
    var minutes: Int { tasks.reduce(0) { $0 + $1.minutes } }
    var minutesDone: Int { tasks.filter(\.done).reduce(0) { $0 + $1.minutes } }
}

/// Builds the study plan. Pure: everything it reads is in `Input`, so tests inject "today".
enum Planner {
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static let mathDomains = ["Algebra", "Advanced Math", "Problem-Solving and Data Analysis", "Geometry and Trigonometry"]
    static let rwDomains = ["Craft and Structure", "Information and Ideas", "Standard English Conventions", "Expression of Ideas"]
    /// Official approximate share of questions.
    static let share = Mastery.weight.mapValues { $0 / 100 }
    static let fullTestMinutes = 135      // 2 h 14 of modules plus the 10-minute break (spec 1.4)

    /// A finished full test as the plan sees it.
    struct TestDone: Hashable { var id: String; var name: String?; var date: Date; var misses: Int; var unreviewed: Int }

    struct Input {
        var profile: Profile
        var today: Date
        var tests: [TestDone] = []
        var mastery = Mastery()
        var baseline: Int? = nil
        var cardsDue: [Date] = []         // mistake cards studied before: when each is due next
        var cardsNew = 0                  // mistake cards never studied: due now
        var cardsStudiedToday = 0         // mistake cards studied today
    }

    struct Baseline: Hashable { var total: Int; var rw: Int?; var math: Int?; var source: String; var date: Date?; var id: String }

    /// The latest score: an official sitting, a test's official total, or a score from before the app (spec 1.2).
    static func baseline(_ p: Profile, sessions: [Session], today: Date = Clock.now) -> Baseline? {
        var all = p.sittings.compactMap { s in s.total.map { Baseline(total: $0, rw: s.rw, math: s.math, source: "SAT", date: s.date, id: s.id) } }
        all += sessions.compactMap { s in s.official?.total.map { Baseline(total: $0, rw: s.official?.readingWriting, math: s.official?.math, source: s.title, date: s.end ?? s.start, id: s.id) } }
        all += p.priorScores.map { Baseline(total: $0.total, rw: $0.rw, math: $0.math, source: $0.testName ?? ($0.kind == .psat ? "PSAT" : "SAT"), date: $0.date, id: $0.id) }
        return all.filter { ($0.date ?? .distantPast) <= today }.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// Prep hours for a gain, PrepScholar's table (R2).
    static func hours(gap: Int) -> Int { gap <= 0 ? 0 : gap <= 30 ? 10 : gap <= 70 ? 20 : gap <= 130 ? 40 : gap <= 200 ? 80 : 150 }

    struct Feasibility: Hashable {
        enum Status: String { case onTrack, tight, notEnough, unknown }
        var gap: Int                      // target − baseline (0 without a score)
        var weeks: Double                 // to the goal
        var neededHours: Int
        var plannedHours: Double          // task minutes planned from today to the goal
        var neededPerWeek: Double
        var budgetPerWeek: Double         // study days × minutes
        var status: Status
    }

    /// Needed hours vs planned: on track when the plan covers them, tight within 25% short, else not enough (spec 1.4).
    static func feasibility(_ p: Profile, baseline: Int?, days: [StudyDay], today: Date) -> Feasibility {
        let cal = Calendar.current
        let weeks = max(1, Double(cal.dateComponents([.day], from: cal.startOfDay(for: today), to: p.goal(today).date).day ?? 0)) / 7
        let planned = Double(days.flatMap(\.tasks).filter { $0.kind != .rest }.reduce(0) { $0 + $1.minutes }) / 60
        let budget = Double(p.days.count * p.minutes) / 60
        guard let b = baseline else { return Feasibility(gap: 0, weeks: weeks, neededHours: 0, plannedHours: planned, neededPerWeek: 0, budgetPerWeek: budget, status: .unknown) }
        let need = hours(gap: p.targetScore - b)
        let status: Feasibility.Status = Double(need) <= planned ? .onTrack : Double(need) <= planned * 1.25 ? .tight : .notEnough
        return Feasibility(gap: max(0, p.targetScore - b), weeks: weeks, neededHours: need, plannedHours: planned, neededPerWeek: Double(need) / weeks, budgetPerWeek: budget, status: status)
    }

    /// The plan from today to the sitting, after the history kept from `old`. Re-planning keeps every task's id and tick
    /// when the same task is still planned that day; today's finished tasks never change.
    @MainActor static func make(_ inp: Input, old: [StudyDay] = []) -> [StudyDay] {
        let cal = Calendar.current, p = inp.profile, today = cal.startOfDay(for: inp.today)
        func add(_ n: Int, _ d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d)! }
        func gap(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0 }
        let history = old.filter { $0.date < today && gap($0.date, today) <= 120 }.map { d in
            var d = d
            for i in d.tasks.indices where !d.tasks[i].done && d.tasks[i].kind != .rest { d.tasks[i].missed = true }
            return d
        }
        let past = history.flatMap(\.tasks)
        let oldToday = old.first { cal.isDate($0.date, inSameDayAs: today) }
        let end = p.goal(today).date
        let taperStart = add(-7, end), practiceStart = add(-28, end), eve = add(-1, end)
        // R3: 14 days apart; 7 when the previous one is within 4 weeks of the sitting (spec 1.4). Dated, so it never shifts as days pass.
        func spacing(_ prev: Date) -> Int { gap(prev, end) < 28 ? 7 : 14 }

        let tests = inp.tests.sorted { $0.date < $1.date }
        let ticked = Set((past + (oldToday?.tasks ?? [])).filter(\.done).compactMap { t -> String? in if case .review(let id) = t.target { id } else { nil } })
        let sat = p.sittings.filter { $0.booked && cal.startOfDay(for: $0.date) <= today }.map { cal.startOfDay(for: $0.date) }
        // A full test ticked done counts as taken, even before its results are in the app.
        let ticks = history.compactMap { d in d.tasks.first { $0.kind == .test && $0.done }.map { (date: cal.startOfDay(for: d.date), name: $0.test) } }
        var lastFull = (tests.map { cal.startOfDay(for: $0.date) } + sat + ticks.map(\.date)).max()   // a sitting is a full test too
        var lastName = lastFull.map { d in sat.contains(d) ? "your SAT" : tests.last { cal.isDate($0.date, inSameDayAs: d) }?.name ?? ticks.last { $0.date == d }?.name ?? "your last full test" }
        let used = Set(tests.compactMap(\.name) + p.priorScores.compactMap(\.testName) + ticks.compactMap(\.name))
        var remaining = TestChoice.bluebook.filter { t in !used.contains(t) && oldToday?.tasks.contains { $0.test == t } != true }
        let diagnose = inp.baseline == nil && lastFull == nil                   // R1
        var drillTurn = past.count { $0.kind == .drill }                        // rotation carries on across days (W1)
        var moduleTurn = past.count { $0.kind == .module }
        // Study days since the last timed module; a test day leaves it as it was, as it did when the plan was made (a new day re-plans the same days).
        let studied = history.filter { $0.tasks.contains { ![.rest, .test].contains($0.kind) } }
        var sinceModule = studied.lastIndex { $0.tasks.contains { $0.kind == .module } }.map { studied.count - 1 - $0 } ?? 99
        var taperModule = history.contains { $0.date >= taperStart && $0.tasks.contains { $0.kind == .module } }
        let weekendStudy = p.days.contains(1) || p.days.contains(7)
        let sittingDays = Set(p.sittings.filter(\.booked).map { cal.startOfDay(for: $0.date) })
        let pins = p.pins.filter { !p.skips.contains($0.key) }
        let top = inp.mastery.priorities(target: p.targetScore, focus: p.focus)
        let words = top.contains { $0.skill == "Words in Context" || ($0.skill == nil && $0.domain == "Craft and Structure") }
        let lastMisses = tests.last?.misses

        // Reviews still to do: the newest test, and any from the last two weeks, with misses that have no cause yet (R4, R5).
        struct Pending { var id: String; var title: String; var misses: Int; var date: Date }
        var reviews = tests.enumerated().filter { i, t in t.unreviewed > 0 && !ticked.contains(t.id) && (i == tests.count - 1 || gap(t.date, today) <= 14) }
            .map { Pending(id: $0.1.id, title: $0.1.name ?? "your full test", misses: $0.1.unreviewed, date: cal.startOfDay(for: $0.1.date)) }
        // A full test ticked with no results in the app has no misses to review: no review for it.
        let cardDue = inp.cardsDue.sorted()
        // Cards a ticked redo covered are not due again: count from the day after it, as the plan did when it was made.
        var lastStudy = history.last { $0.tasks.contains { $0.kind == .cards && $0.done } }?.date, firstStudy = true

        var days: [StudyDay] = []
        var d = today
        while d < end {
            defer { d = add(1, d) }
            let ds = Planner.day.string(from: d), wd = cal.component(.weekday, from: d), left = gap(d, end)
            if d == eve {   // always rest, studied or not (R13)
                days.append(StudyDay(date: d, phase: .taper, tasks: [StudyTask(kind: .rest, title: "Rest", detail: "Sleep early. Pack your device, charger, photo ID and admission ticket.",
                                                                                minutes: 0, why: "The SAT is tomorrow.", target: .none)]))
                continue
            }
            if sittingDays.contains(d) { continue }
            let pinned = left >= 7 ? pins[ds] : nil
            guard pinned != nil || (p.days.contains(wd) && !p.skips.contains(ds)) else { continue }
            // Test day: kept as planned, unless that test was since ticked on an earlier day.
            if cal.isDate(d, inSameDayAs: today), let o = oldToday, let t = o.tasks.first(where: { $0.kind == .test }), !ticks.contains(where: { $0.name != nil && $0.name == t.test }) {
                days.append(o); lastFull = max(lastFull ?? d, d); lastName = t.test ?? "your full test"
                if !t.done && !tests.contains(where: { cal.isDate($0.date, inSameDayAs: d) }) { reviews.append(Pending(id: "", title: lastName!, misses: lastMisses ?? 30, date: d)) }
                continue
            }
            let phase: Phase = d >= taperStart ? .taper : d >= practiceStart ? .practice : .build

            // A full test: never in the last 6 days; ≥14 days before the sitting unless none in the 14 days before; weekends (R3).
            let since = lastFull.map { gap($0, d) } ?? 999
            let first = diagnose && !days.contains { $0.tasks.contains { $0.kind == .test } }
            let pinSoon = pins.keys.contains { k in k > ds && (Planner.day.date(from: k).map { gap(d, $0) < spacing(d) } ?? false) }
            let auto = left >= 7 && (first || (since >= (lastFull.map(spacing) ?? 0) && (!weekendStudy || [1, 7].contains(wd)) && !pinSoon && (left >= 14 || since >= 14)))
            if pinned != nil || auto {
                let name = pinned ?? remaining.first { !pins.values.contains($0) }
                remaining.removeAll { $0 == name }
                let long = p.minutes < fullTestMinutes ? " Longer than your usual \(p.minutes) min." : ""
                let why = first ? "No score yet: this test is your starting point."
                    : pinned != nil ? "Pinned for this day."
                    : "\(since) days after \(lastName ?? "your last full test")."
                days.append(StudyDay(date: d, phase: first ? .diagnose : phase, tasks: [
                    StudyTask(kind: .test, title: name ?? "Full practice test", detail: (name == nil ? "In the app, timed" : "In Bluebook, timed") + ", in one sitting with the break." + long,
                              minutes: fullTestMinutes, why: why, target: name.map { .bluebook($0) } ?? .appTest)]))
                reviews.append(Pending(id: "", title: name ?? "your full test", misses: lastMisses ?? 30, date: d))
                lastFull = d; lastName = name ?? "your full test"
                continue
            }

            var room = max(15, p.minutes), tasks: [StudyTask] = []
            if let i = reviews.firstIndex(where: { $0.date < d }) {   // the day after a test, or the next study day (R4)
                let r = reviews.remove(at: i)
                let m = min(room, 60, max(10, Int((1.5 * Double(r.misses)).rounded(.up))))
                tasks.append(StudyTask(kind: .review, title: "Review \(r.title)", detail: "Pick why you missed each one, then redo it without a timer.", minutes: m,
                                       why: r.id.isEmpty ? "Within two days of the test." : "\(r.misses) \(r.misses == 1 ? "miss has" : "misses have") no reason yet.",
                                       target: .review(r.id), count: r.misses))
                room -= m
            }
            // Misses due for a blind redo (R6): due since the last study day; today also the new ones.
            let from = lastStudy.map { add(1, $0) } ?? .distantPast
            let due = cardDue.count { $0 >= from && $0 < add(1, d) } + (firstStudy ? inp.cardsNew + inp.cardsStudiedToday : 0)
            lastStudy = d; firstStudy = false
            if due > 0, room >= 5 {
                let m = min(room, 20, max(5, Int((1.5 * Double(due)).rounded(.up))))
                tasks.append(StudyTask(kind: .cards, title: "Redo misses", detail: "\(due) \(due == 1 ? "card" : "cards") from past misses, answer before you flip.",
                                       minutes: m, why: "\(due) past \(due == 1 ? "miss is" : "misses are") due again.", target: .cards, count: due))
                room -= m
            }
            func module() {
                let math = moduleTurn % 2 == 1   // R&W first, then Math, alternating for good (W1)
                let m = math ? 35 : 32
                guard room >= m else { return }
                moduleTurn += 1
                tasks.append(StudyTask(kind: .module, title: math ? "Math module" : "R&W module",
                                       detail: math ? "22 questions in 35 minutes." : "27 questions in 32 minutes.", minutes: m,
                                       why: "Pacing at test length; \(math ? "R&W" : "Math") was the last one.", target: .module(math ? Sec.math : Practice.rw)))
                room -= m
            }
            if phase == .taper {   // R13: no new topics, one timed module, the error log
                if !taperModule { module(); taperModule = tasks.contains { $0.kind == .module } }
                if room >= 10 {
                    let all = tests.reduce(0) { $0 + $1.misses }
                    tasks.append(StudyTask(kind: .review, title: "Error log", detail: "Redo past misses without a timer. Nothing new this week.", minutes: min(room, 30),
                                           why: all > 0 ? "\(all) misses across your full tests." : "Misses from your practice.", target: .errorLog))
                }
            } else {
                // Timed modules between the full tests: every other study day in the last four weeks, every third before (product choice).
                if sinceModule >= (phase == .practice ? 1 : 2) { module() }
                if words, room >= 30 {
                    tasks.append(StudyTask(kind: .words, title: "Words", detail: "Study the words due in the Words deck.", minutes: 10,
                                           why: "Words in Context is a top priority.", target: .words))
                    room -= 10
                }
                // Drill blocks of 20–30 minutes, two skills interleaved per block (R10), retrieval in a Practice set (R11).
                var k = Int((Double(room) / 30).rounded(.up))
                while k > 1, room / k < 20 { k -= 1 }
                if room >= 20, !top.isEmpty {
                    // By priority (R7): #1 in two blocks of three, #2 in two, #3 and #4 in one; the day's blocks top pair first.
                    let turns = [(0, 1), (0, 2), (1, 3)]
                    var pairs: [[Int]] = []
                    for _ in 0..<k {
                        let (a, b) = turns[drillTurn % turns.count]
                        pairs.append([a % top.count, b % top.count].reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } })
                        drillTurn += 1
                    }
                    for pair in pairs.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                        tasks.append(drill(pair.map { top[$0] }, minutes: min(30, room / k), high: p.targetScore >= 1400))
                    }
                }
            }
            sinceModule = tasks.contains { $0.kind == .module } ? 0 : sinceModule + 1
            if !tasks.isEmpty { days.append(StudyDay(date: d, phase: phase, tasks: tasks)) }
        }
        return history + reconcile(days, old: old, history: history, today: today, inp)
    }

    /// A drill block: each skill at one band above its accuracy (R8), half the time answering at SAT pace, half checking.
    @MainActor static func drill(_ pair: [Mastery.Area], minutes: Int, high: Bool) -> StudyTask {
        var drills: [Drill] = []
        for a in pair {
            let pace = a.section == Sec.math ? 95.0 : 71.0
            let n = max(2, Int(Double(minutes) / Double(pair.count) * 60 / (pace * 2)))
            let band = Mastery.band(a.rate)
            for (lvl, c) in zip(band, band.count == 2 ? [(n + 1) / 2, n / 2] : [n]) where c > 0 {   // no random split: re-plans stay identical
                drills.append(Drill(section: a.section, domain: a.domain, skill: a.skill ?? "", difficulty: lvl, count: c))
            }
        }
        // The title names the skills in this order, so the counts alone fit the row.
        let why = pair.allSatisfy({ $0.seen > 0 }) ? pair.map { "\($0.right) of \($0.seen)" }.joined(separator: " and ") + " right" : pair.map { a in
            a.seen > 0 ? "\(a.short): \(a.right) of \(a.seen) right" : "\(a.domain): \(Int(Mastery.weight[a.domain] ?? 0))% of \(a.section == Sec.math ? "Math" : "R&W")"
        }.joined(separator: "; ") + (high && pair.contains { $0.emSeen > 0 } ? "; easy and medium misses first" : "")
        return StudyTask(kind: .drill, title: pair.map(\.short).joined(separator: " + "), detail: "Practice set mixing both, then check every miss.",
                         minutes: minutes, why: why + ".", target: .practice(drills))
    }

    /// Keeps ids and ticks of tasks still planned, today's finished tasks, and marks carried and finished ones.
    private static func reconcile(_ new: [StudyDay], old: [StudyDay], history: [StudyDay], today: Date, _ inp: Input) -> [StudyDay] {
        let cal = Calendar.current
        let byDay = Dictionary(old.filter { $0.date >= today }.map { (cal.startOfDay(for: $0.date), $0.tasks) }, uniquingKeysWith: { a, _ in a })
        let missedReviews = Set(history.flatMap(\.tasks).filter { $0.kind == .review && $0.missed }.map(\.key))
        let missedCards = history.last { $0.tasks.contains { $0.kind != .rest } }?.tasks.contains { $0.kind == .cards && $0.missed } ?? false
        var days = new
        if let kept = byDay[today], !days.contains(where: { cal.isDate($0.date, inSameDayAs: today) }), kept.contains(where: \.done) {
            days.insert(StudyDay(date: today, phase: new.first?.phase ?? .build, tasks: []), at: 0)   // no longer a study day: its finished tasks stay
        }
        for i in days.indices {
            let isToday = cal.isDate(days[i].date, inSameDayAs: today)
            var prev = byDay[cal.startOfDay(for: days[i].date)] ?? []
            if isToday { prev = prev.map { auto($0, inp, today: true) } }
            var used = Set<String>()
            for j in days[i].tasks.indices {
                var t = days[i].tasks[j]
                // Same task, or a tick from before plan.json (no target) on a task of the same kind.
                if let o = prev.first(where: { !used.contains($0.id) && $0.key == t.key }) ?? prev.first(where: { !used.contains($0.id) && $0.target == .none && $0.kind == t.kind }) {
                    used.insert(o.id)
                    if isToday && o.done && o.target != .none { t = o } else { t.id = o.id; t.done = o.done }
                }
                if t.kind == .review { t.carried = missedReviews.contains(t.key) }
                if t.kind == .cards, isToday { t.carried = missedCards }
                days[i].tasks[j] = auto(t, inp, today: isToday)
            }
            if isToday { days[i].tasks = prev.filter { $0.done && !used.contains($0.id) && $0.target != .none } + days[i].tasks }
        }
        return days.filter { !$0.tasks.isEmpty }
    }

    /// Done without a tick: the test was taken, every miss has a reason, today's cards were studied.
    private static func auto(_ t: StudyTask, _ inp: Input, today: Bool) -> StudyTask {
        var t = t
        switch t.target {
        case .bluebook(let n): if inp.tests.contains(where: { $0.name == n }) { t.done = true }
        case .review(let id): if let x = inp.tests.first(where: { $0.id == id }), x.unreviewed == 0 { t.done = true }
        case .cards: if today, inp.cardsStudiedToday > 0, inp.cardsStudiedToday >= (t.count ?? 0) || inp.cardsNew + inp.cardsDue.count(where: { $0 <= inp.today }) == 0 { t.done = true }
        default: break
        }
        return t
    }

    /// Finished full tests: a Bluebook test by name, or any test with both sections (an in-app full test).
    static func tests(_ sessions: [Session]) -> [TestDone] {
        sessions.filter { $0.end != nil && (TestChoice.bluebook.contains($0.test ?? "") || $0.sections.count == 2) }.map { s in
            let miss = s.keys.filter { s.correct($0) == false }
            return TestDone(id: s.id, name: TestChoice.bluebook.contains(s.test ?? "") ? s.test : nil, date: s.end!, misses: miss.count,
                            unreviewed: miss.count { s.q[$0]?.reasons.isEmpty != false })
        }
    }

    /// Domains to drill, weakest first, from the one skill model (kept for Practice's defaults).
    @MainActor static func weakest(_ sessions: [Session]) -> [String] {
        let w = Mastery(sessions: sessions).weakest
        return w.count >= 2 ? w.prefix(2).map(\.domain) : zip(mathDomains, rwDomains).flatMap { [$0, $1] }
    }

    /// Old done.json ticks ("yyyy-MM-dd|kind|title") as days: past ticks become history, today's match by kind.
    static func migrate(_ ticks: Set<String>) -> [StudyDay] {
        var byDay: [Date: [StudyTask]] = [:]
        for t in ticks.sorted() {
            let parts = t.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, let d = day.date(from: parts[0]), let k = StudyTask.Kind(rawValue: parts[1]) else { continue }
            byDay[Calendar.current.startOfDay(for: d), default: []].append(StudyTask(kind: k, title: parts[2], detail: "", minutes: 0, done: true))
        }
        return byDay.keys.sorted().map { StudyDay(date: $0, phase: .build, tasks: byDay[$0]!) }
    }

    /// Phases in order with their study days.
    static func phases(_ days: [StudyDay]) -> [(phase: Phase, days: Int)] {
        Phase.allCases.map { ph in (ph, days.count { $0.phase == ph && $0.tasks.contains { $0.kind != .rest } }) }.filter { $0.1 > 0 }
    }
}

/// The plan, saved as plan.json (history and days ahead), re-planned when anything it reads changes.
@MainActor final class PlanStore: ObservableObject {
    static let shared = PlanStore()
    @Published var profile: Profile = Files.load("profile.json", as: Profile.self) ?? Profile() {
        didSet { if profile != oldValue { Files.save(profile, "profile.json"); changed() } }
    }
    private var stored: [StudyDay]
    private(set) var suggestionLog: [Suggestion] = Files.load("suggestions.json", as: [Suggestion].self) ?? []
    private var dirty = true
    private var madeOn: Date?
    private var cache: (mastery: Mastery, baseline: Planner.Baseline?)?
    private var subs: [AnyCancellable] = []

    init() {
        // Earlier versions kept only ticks in done.json; they become history (and today's ticks) once.
        stored = Files.load("plan.json", as: [StudyDay].self) ?? Planner.migrate(Files.load("done.json", as: Set<String>.self) ?? [])
        // @Published fires before the change lands; the plan is rebuilt on the next read.
        subs = [Store.shared.$sessions.sink { [weak self] _ in MainActor.assumeIsolated { self?.changed() } },
                CardStore.shared.$cards.sink { [weak self] _ in MainActor.assumeIsolated { self?.changed() } },
                Practice.shared.$sets.sink { [weak self] _ in MainActor.assumeIsolated { self?.changed() } }]
    }

    private func changed() { dirty = true; cache = nil }

    var mastery: Mastery { inputs().mastery }
    var baseline: Planner.Baseline? { inputs().baseline }
    private func inputs() -> (mastery: Mastery, baseline: Planner.Baseline?) {
        if let c = cache { return c }
        let c = (Mastery(sessions: Store.shared.sessions, practice: Practice.shared.sets), Planner.baseline(profile, sessions: Store.shared.sessions))
        cache = c
        return c
    }

    /// Everything the planner reads, from the stores.
    func input(_ p: Profile, now: Date = Clock.now) -> Planner.Input {
        let cal = Calendar.current
        let tests = Planner.tests(Store.shared.sessions)
        let mistakes = CardStore.shared.cards.filter { $0.kind == .mistake }
        return Planner.Input(profile: p, today: now, tests: tests, mastery: inputs().mastery, baseline: Planner.baseline(p, sessions: Store.shared.sessions, today: now)?.total,
                             // A new card is due from the day it was added, so a ticked redo covers the ones it listed.
                             cardsDue: mistakes.map { $0.isNew ? $0.added : $0.due },
                             cardsStudiedToday: mistakes.count { $0.lastReviewed.map(cal.isToday) ?? false })
    }

    private func refresh() {
        let today = Calendar.current.startOfDay(for: Clock.now)
        guard dirty || madeOn != today else { return }
        dirty = false; madeOn = today
        stored = Planner.make(input(profile), old: stored)
        Files.save(stored, "plan.json")
        let new = Adviser.make(state(today))
        // A suggestion still waiting whose reason is gone (a sitting moved, the final week began) goes away unanswered.
        let live = Set(new.map(\.trigger))
        let stale = suggestionLog.filter { $0.state == .pending && ![.chat, .askScore].contains($0.kind) && !live.contains($0.trigger) }.map(\.id)
        suggestionLog.removeAll { stale.contains($0.id) }
        let updated = Adviser.update(&suggestionLog, from: new)
        let seen = Set(suggestionLog.map(\.trigger))
        let fresh = new.filter { !seen.contains($0.trigger) }
        // A score entered settles its ask; "Not out yet" puts it away until it is asked again.
        let asked = Set(profile.needsScore(today).map(\.id))
        for i in suggestionLog.indices where suggestionLog[i].kind == .askScore && suggestionLog[i].state == .pending && !asked.contains(suggestionLog[i].sitting ?? "") {
            suggestionLog[i].state = profile.sittings.first { $0.id == suggestionLog[i].sitting }?.total != nil ? .accepted : .dismissed
        }
        if !fresh.isEmpty || !stale.isEmpty || updated || suggestionLog.contains(where: { $0.kind == .askScore }) {
            suggestionLog = Array((suggestionLog + fresh).suffix(100))
            Files.save(suggestionLog, "suggestions.json")
        }
        Notifier.schedule(Notifier.requests(profile, days: stored, suggestions: suggestions, now: Clock.now))
    }

    private func state(_ today: Date) -> Adviser.State {
        let b = baseline
        let ahead = stored.filter { $0.date >= today }
        return Adviser.State(profile: profile, today: today, baseline: b, feasibility: Planner.feasibility(profile, baseline: b?.total, days: ahead, today: today),
                             history: stored.filter { $0.date < today }, days: ahead, mastery: mastery)
    }

    /// Today and every day up to the sitting.
    var days: [StudyDay] { refresh(); let t = Calendar.current.startOfDay(for: Clock.now); return stored.filter { $0.date >= t } }
    /// Past days as they were planned, with what was done and what was missed.
    var history: [StudyDay] { refresh(); let t = Calendar.current.startOfDay(for: Clock.now); return stored.filter { $0.date < t } }
    var today: StudyDay? { days.first { Calendar.current.isToday($0.date) } }
    var goal: Profile.Goal { profile.goal() }
    var nextSitting: Sitting? { profile.nextSitting() }
    var needsScore: [Sitting] { profile.needsScore() }
    var phases: [(phase: Phase, days: Int)] { Planner.phases(days) }
    var feasibility: Planner.Feasibility { Planner.feasibility(profile, baseline: baseline?.total, days: days, today: Clock.now) }
    var suggestions: [Suggestion] { refresh(); return suggestionLog.filter { $0.state == .pending }.reversed() }

    /// The plan a profile would get, for the onboarding preview (nothing saved).
    func preview(_ p: Profile) -> [StudyDay] { Planner.make(input(p)) }

    func isDone(_ d: Date, _ t: StudyTask) -> Bool { find(t.id).map { stored[$0.0].tasks[$0.1].done } ?? t.done }

    func toggle(_ d: Date, _ t: StudyTask) {
        guard let (i, j) = find(t.id) else { return }
        objectWillChange.send()
        stored[i].tasks[j].done.toggle()
        Files.save(stored, "plan.json")
        if t.kind == .test { changed() }   // a full test ticked counts as taken: the tests after it move up
        Notifier.schedule(Notifier.requests(profile, days: stored, suggestions: suggestions, now: Clock.now))
    }

    private func find(_ id: String) -> (Int, Int)? {
        refresh()
        for (i, d) in stored.enumerated() { if let j = d.tasks.firstIndex(where: { $0.id == id }) { return (i, j) } }
        return nil
    }

    /// The official score of a sitting; the plan then re-plans for the next one.
    func recordScore(sitting id: String, rw: Int, math: Int) {
        guard let i = profile.sittings.firstIndex(where: { $0.id == id }) else { return }
        profile.sittings[i].rw = rw; profile.sittings[i].math = math
        cache = nil
    }

    /// "Not out yet": the score card and its notification come back in 7 days.
    func snooze(sitting id: String) {
        guard let i = profile.sittings.firstIndex(where: { $0.id == id }) else { return }
        profile.sittings[i].snoozedUntil = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Clock.now))
    }

    func suggestion(_ id: String) -> Suggestion? { suggestionLog.first { $0.id == id } }

    /// Applies the suggestion's changes (one profile change, so one re-plan) and keeps it as accepted.
    func accept(_ id: String) {
        guard let i = suggestionLog.firstIndex(where: { $0.id == id }), suggestionLog[i].state == .pending else { return }
        objectWillChange.send()
        var p = profile
        for c in suggestionLog[i].changes { c.apply(&p) }
        suggestionLog[i].state = .accepted
        Files.save(suggestionLog, "suggestions.json")
        profile = p
    }

    func dismiss(_ id: String) {
        guard let i = suggestionLog.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        suggestionLog[i].state = .dismissed
        Files.save(suggestionLog, "suggestions.json")
    }

    /// The tutor chat's changes, waiting for the student's Accept.
    @discardableResult func suggest(chat changes: [PlanChange], title: String, why: String) -> Suggestion {
        objectWillChange.send()
        let s = Suggestion(kind: .chat, trigger: "chat:\(UUID().uuidString)", title: title, why: why, changes: changes)
        suggestionLog = Array((suggestionLog + [s]).suffix(100))
        Files.save(suggestionLog, "suggestions.json")
        return s
    }

    /// A day counts as active when a task was ticked, a test finished, or cards were studied.
    func active(_ d: Date) -> Bool {
        let cal = Calendar.current
        if stored.contains(where: { cal.isDate($0.date, inSameDayAs: d) && $0.tasks.contains(where: \.done) }) { return true }
        if Store.shared.sessions.contains(where: { $0.end.map { cal.isDate($0, inSameDayAs: d) } ?? false }) { return true }
        return CardStore.shared.cards.contains { $0.lastReviewed.map { cal.isDate($0, inSameDayAs: d) } ?? false }
    }

    /// Days in a row up to today (today may still be open without breaking it).
    var streak: Int {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Clock.now), n = 0
        if !active(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        while active(d), n < 365 { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }
}
