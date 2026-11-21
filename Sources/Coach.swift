import SwiftUI

/// Everything a tutor would know walking in: who the student is, the goal, the scores, the weak spots, the week.
/// Sent with every AI request (explanations, debriefs, chat) so the tutor is the same person everywhere.
@MainActor enum Student {
    /// The reasons the student picked for their misses, most common first. "concept" is counted per section (a math idea
    /// in Math, the passage's logic in Reading and Writing), so it keeps its section's name.
    static func reasons(_ sessions: [Session]) -> [(id: String, section: String?, count: Int)] {
        var n: [String: Int] = [:]
        for s in sessions { for k in s.keys where s.correct(k) != true { for r in s.q[k]?.reasons ?? [] { n[r == "concept" ? "\(r)|\(Session.section(of: k))" : r, default: 0] += 1 } } }
        let order = Cause.all.map(\.id)
        return n.map { k, v in let p = k.split(separator: "|").map(String.init); return (p[0], p.count > 1 ? p[1] : nil, v) }
            .sorted { (-$0.count, order.firstIndex(of: $0.id) ?? 99, $0.section ?? "") < (-$1.count, order.firstIndex(of: $1.id) ?? 99, $1.section ?? "") }
    }

    static func brief() -> String {
        let p = PlanStore.shared.profile, sessions = Store.shared.sessions
        var lines: [String] = []
        lines.append("Student: \(p.name.isEmpty ? "unnamed" : p.name), grade \(p.grade).")
        let plan = PlanStore.shared, goal = p.goal()
        for s in p.sittings {
            lines.append("Official SAT \(s.date.formatted(date: .complete, time: .omitted)): " + (s.total.map { "taken, \($0) (R&W \(s.rw!), Math \(s.math!))" }
                ?? (s.date < Calendar.current.startOfDay(for: Clock.now) ? "taken, score not in yet" : s.booked ? "booked" : "aiming for it, not booked")) + ".")
        }
        lines.append("The plan works toward \(goal.date.formatted(date: .complete, time: .omitted))\(goal.booked ? "" : " (not booked)"), "
                     + "\(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Clock.now), to: goal.date).day ?? 0) days away. Target \(p.targetScore).")
        for s in p.priorScores { lines.append("Score before the app: \(s.testName ?? s.kind.rawValue.uppercased()) \(s.total)\(s.date.map { " on " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "").") }
        if let b = plan.baseline { lines.append("Baseline: \(b.total) from \(b.source).") }
        let f = plan.feasibility
        if f.status != .unknown { lines.append("Hours: \(f.neededHours) h needed for the gap (PrepScholar's table), \(Int(f.plannedHours.rounded())) h planned until then (\(f.status.rawValue)).") }
        let done = sessions.filter { $0.end != nil }
        if !done.isEmpty { lines.append("Practice test results (quote these exactly; never work out or recall a score yourself):") }
        for s in done.prefix(4) {
            let st = Stats(s.sections.map { s.only($0) })
            var line = "- \(s.title) on \(s.start.formatted(date: .abbreviated, time: .omitted)): "
                + (st.marked == 0 ? "not graded yet" : "\(st.right) of \(st.marked) right\(s.official?.answers.isEmpty == false ? " (College Board's record)" : "")")
            if let o = s.official, let t = o.total { line += ", official \(t) (R&W \(o.readingWriting.map(String.init) ?? "?"), Math \(o.math.map(String.init) ?? "?"))" }
            lines.append(line + ".")
        }
        if done.isEmpty { lines.append("No practice tests taken yet.") }
        let rank = plan.mastery.priorities(target: p.targetScore, focus: p.focus).map { a in a.name + (a.seen > 0 ? " \(a.right)/\(a.seen)" : "") }
        lines.append("Drill priorities (official weight × miss rate): " + rank.joined(separator: ", ") + ".")
        let mastered = plan.mastery.mastered.map(\.name)
        if !mastered.isEmpty { lines.append("Mastered lately: " + mastered.joined(separator: ", ") + ".") }
        let sets = Practice.shared.sets.filter { $0.done && !$0.full }.prefix(3).map { "\($0.domain) \($0.score)/\($0.questions.count)" }
        if !sets.isEmpty { lines.append("Latest practice sets: " + sets.joined(separator: ", ") + ".") }
        if let g = sessions.first(where: { $0.end != nil })?.debriefs.values.compactMap(\.goal).first { lines.append("Goal set after the latest test: \(g)") }
        lines.append("Flashcards: \(CardStore.shared.tally(.mistake).due) past misses due, \(CardStore.shared.tally(.word).due) words due.")
        let why = reasons(sessions).compactMap { r in Cause.of(r.id, section: r.section).map { "\($0.name) \(r.count)" } }
        if !why.isEmpty { lines.append("Why they miss, in their own words, across all tests (misses per reason): " + why.joined(separator: ", ") + ".") }
        let notes = sessions.lazy.flatMap { s in s.keys.reversed().compactMap { k in
            s.q[k]?.memo.flatMap { m in m.isEmpty ? nil : "- \(s.title) \(s.label(k)): \(m.count > 120 ? m.prefix(120) + "…" : m)" }
        } }.prefix(3)
        if !notes.isEmpty { lines.append("Their latest notes on questions:\n" + notes.joined(separator: "\n")) }
        let names = Calendar.current.shortWeekdaySymbols
        lines.append("Studies on " + p.days.sorted().map { names[$0 - 1] }.joined(separator: ", ") + ", \(p.minutes) min a day.")
        if !p.focus.isEmpty { lines.append("Focus set: " + p.focus.joined(separator: ", ") + ".") }
        if !p.skips.isEmpty { lines.append("Days off: " + p.skips.sorted().joined(separator: ", ") + ".") }
        if !p.pins.isEmpty { lines.append("Pinned tests: " + p.pins.sorted { $0.key < $1.key }.map { "\($0.value) on \($0.key)" }.joined(separator: ", ") + ".") }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Clock.now)!
        let week = (plan.history.filter { $0.date >= weekAgo } + plan.days.prefix(7)).map { d in
            "\(Planner.day.string(from: d.date)) (\(d.date.formatted(.dateTime.weekday(.abbreviated))), \(d.phase.rawValue)): "
                + d.tasks.map { "\($0.title) \($0.minutes)m" + ($0.done ? " done" : $0.missed ? " missed" : $0.carried ? " carried over" : "") }.joined(separator: ", ")
        }
        if !week.isEmpty { lines.append("Plan, last 7 days and the next study days:\n" + week.joined(separator: "\n")) }
        let sug = plan.suggestionLog.suffix(8).map { "- \($0.title) (\($0.state.rawValue)): \($0.why)" }
        if !sug.isEmpty { lines.append("Suggestions so far (the student accepts or dismisses each):\n" + sug.joined(separator: "\n")) }
        lines.append("Today is \(Planner.day.string(from: Clock.now)) (\(Clock.now.formatted(.dateTime.weekday(.wide)))).")
        return lines.joined(separator: "\n")
    }
}

/// The tutor you talk to about your plan. It answers like a good human tutor and can change the schedule;
/// every change is checked here before it is applied, and can be undone.
@MainActor final class Coach: ObservableObject {
    static let shared = Coach()
    struct Line: Codable, Hashable, Identifiable {
        var id = UUID()
        var fromStudent: Bool
        var text: String
        var changes: [String] = []
        var undo: Profile?               // lines from before suggestions: Undo restores this
        var suggestion: String?          // the Suggestion holding `changes`, to accept or dismiss
    }
    @Published var lines: [Line] = Files.load("coach.json", as: [Line].self) ?? [] { didSet { Files.save(Array(lines.suffix(60)), "coach.json") } }
    @Published var busy = false

    static let persona = """
    You are this student's SAT tutor: experienced, warm, direct, and practical. You know the digital SAT (Bluebook, \
    two sections, adaptive modules, 400–1600) and how real tutors plan: a diagnostic first, full practice tests at least \
    two weeks apart (one week in the last month), careful review of every miss, drills on the weakest areas, no new \
    material in the final week, rest before test day. Talk like a person sitting next to them: short paragraphs, plain words, one question at a \
    time when you need to know something. Use what you know about them below; never invent scores or dates. \
    When they ask to change the schedule (or agree to your suggestion), put the change in `changes`; otherwise leave it \
    empty. Changes are shown to the student as a suggestion to accept or dismiss, so say in `reply` what you propose \
    and why. Only use dates on or after today; a test date must be an official SAT date. Name a question the way the app \
    does ("RW1 Q3", "M2 Q7"), so the student can click it.
    """

    static let schema: [String: Any] = {
        func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        let change: [String: Any] = [
            "action": ["type": "string", "enum": ["set_study_days", "set_minutes", "set_test_date", "set_target_score", "day_off", "remove_day_off", "pin_test", "focus", "clear_focus"]],
            "value": s("minutes, score, or test name ('SAT Practice 7') for pin_test; empty otherwise"),
            "date": s("yyyy-MM-dd for set_test_date, day_off, remove_day_off, pin_test; empty otherwise"),
            "list": ["type": "array", "items": ["type": "string"], "description": "weekday names for set_study_days (e.g. Mon), domain names for focus; empty otherwise"],
        ]
        let props: [String: Any] = [
            "reply": s("What you say to the student."),
            "changes": ["type": "array", "items": ["type": "object", "additionalProperties": false, "required": ["action", "date", "list", "value"], "properties": change]],
        ]
        return ["type": "object", "additionalProperties": false, "required": ["changes", "reply"], "properties": props]
    }()

    /// The tutor speaks first in an empty chat, from the plan (no AI call needed): today's session, or the next one.
    /// The same tasks, titles and minutes as Today.
    var opener: String {
        let plan = PlanStore.shared, cal = Calendar.current
        func session(_ d: StudyDay) -> String? {
            let open = d.tasks.filter { $0.kind != .rest && !plan.isDone(d.date, $0) }
            guard !open.isEmpty else { return nil }
            return open.map(\.line).joined(separator: ", ") + ". \(Fmt.hm(open.reduce(0) { $0 + $1.minutes }))."
        }
        let sat = plan.sittingToday != nil ? "Your SAT is today. " : ""
        if let t = plan.today, let s = session(t) { return sat + "Today: " + s }
        let done = plan.today?.tasks.contains { $0.kind != .rest } == true ? "Today's session is done. " : ""
        if let n = plan.days.first(where: { !cal.isToday($0.date) && session($0) != nil }), let s = session(n) {
            return sat + done + "Next, \(Fmt.day(n.date)): " + s
        }
        return sat + done + "Nothing planned before \(Fmt.day(plan.goal.date))."
    }

    func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        lines.append(Line(fromStudent: true, text: q))
        busy = true
        Task {
            defer { busy = false }
            let history = lines.suffix(12).map { l -> [String: Any] in
                ["role": l.fromStudent ? "user" : "assistant", "content": [["type": "text", "text": l.text]]]
            }
            let system = Self.persona + "\n\nWhat you know about the student:\n" + Student.brief()
            do {
                let raw = try await Brain.send(task: .tutor, system: system, messages: Array(history), schema: Self.schema, base: Files.base, effort: "medium")
                guard let j = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { throw Provider.Failure.empty(Brain.provider(for: .tutor)) }
                let reply = j["reply"] as? String ?? ""
                let changes = parse(j["changes"] as? [[String: Any]] ?? [])
                let s = changes.isEmpty ? nil : PlanStore.shared.suggest(chat: changes, title: changes.map(\.label).joined(separator: ", "), why: reply)
                lines.append(Line(fromStudent: false, text: reply, changes: changes.map(\.label), suggestion: s?.id))
            } catch {
                lines.append(Line(fromStudent: false, text: "I couldn't reach your tutor: \(error.localizedDescription)"))
            }
        }
    }

    func undo(_ line: Line) {
        guard let p = line.undo, let i = lines.firstIndex(of: line) else { return }
        withAnimation(.smooth(duration: 0.3)) { PlanStore.shared.profile = p }
        lines[i].undo = nil
        lines[i].changes = lines[i].changes.map { "Undone: " + $0 }
    }

    /// "Thursday, Nov 12": how a person writes a date in a note.
    static func label(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }

    /// Checks each change against what is possible and keeps the valid ones; they wait as a Suggestion for Accept.
    func parse(_ changes: [[String: Any]], now: Date = Clock.now) -> [PlanChange] {
        let p = PlanStore.shared.profile, cal = Calendar.current
        let today = Planner.day.string(from: now)
        let names = cal.shortWeekdaySymbols.map { $0.lowercased().prefix(3) }
        var out: [PlanChange] = []
        for c in changes {
            let value = (c["value"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let date = (c["date"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let list = c["list"] as? [String] ?? []
            let parsed = Planner.day.date(from: date), validDate = parsed != nil && date >= today
            switch c["action"] as? String {
            case "set_study_days":
                let days = Set(list.compactMap { n in names.firstIndex(of: n.lowercased().prefix(3)).map { $0 + 1 } })
                if !days.isEmpty { out.append(.days(days.sorted())) }
            case "set_minutes":
                if let m = Int(value), (15...240).contains(m) { out.append(.minutes(m)) }
            case "set_test_date":   // official dates only, after today (fixes W8)
                if validDate, date > today, let d = parsed, SATDates.all.contains(where: { cal.isDate($0.date, inSameDayAs: d) }) {
                    out.append(.moveSitting(id: p.nextSitting(now).flatMap { cal.isDate($0.date, inSameDayAs: now) ? nil : $0.id } ?? "", to: d))
                }
            case "set_target_score":
                if let v = Int(value), (400...1600).contains(v) { out.append(.target(v / 10 * 10)) }
            case "day_off":
                if validDate { out.append(.dayOff(date)) }
            case "remove_day_off":
                if p.skips.contains(date) { out.append(.dayOn(date)) }
            case "pin_test":
                // Never in the last 6 days before the sitting: the plan keeps them for review and rest.
                let early = cal.date(byAdding: .day, value: -6, to: p.goal(now).date).map { date < Planner.day.string(from: $0) } ?? true
                if validDate, early, let t = TestChoice.bluebook.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { out.append(.pin(date: date, test: t)) }
            case "focus":
                let doms = list.filter { Planner.share[$0] != nil }
                if !doms.isEmpty { out.append(.focus(doms)) }
            case "clear_focus":
                if !p.focus.isEmpty { out.append(.clearFocus) }
            default: break
            }
        }
        return out
    }

    static func selfCheck() -> [String] {
        var f: [String] = []
        let c = Coach(), ps = PlanStore.shared
        let saved = ps.profile
        defer { ps.profile = saved }
        let cal = Calendar.current, today = cal.startOfDay(for: Clock.now)
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
        func key(_ n: Int) -> String { Planner.day.string(from: day(n)) }
        var start = Profile(); start.sittings = [Sitting(date: day(40))]
        ps.profile = start
        let future = key(5)
        let parsed = c.parse([["action": "set_minutes", "value": "45", "date": "", "list": []],
                              ["action": "set_minutes", "value": "9999", "date": "", "list": []],
                              ["action": "day_off", "value": "", "date": "2000-01-01", "list": []],
                              ["action": "pin_test", "value": "sat practice 7", "date": future, "list": []],
                              ["action": "pin_test", "value": "SAT Practice 99", "date": future, "list": []],
                              ["action": "focus", "value": "", "date": "", "list": ["Algebra", "Made Up"]],
                              ["action": "set_study_days", "value": "", "date": "", "list": ["Mon", "wednesday"]]])
        if parsed != [.minutes(45), .pin(date: future, test: "SAT Practice 7"), .focus(["Algebra"]), .days([2, 4])] { f.append("coach: validation kept \(parsed)") }
        if !parsed.map(\.label).contains("SAT Practice 7 on \(label(day(5)))") { f.append("coach: chip reads like a date, not ISO") }
        // Nothing changes until the student accepts.
        let s = ps.suggest(chat: parsed, title: "t", why: "w")
        if ps.profile != start || ps.suggestion(s.id)?.state != .pending { f.append("coach: a chat change applied without Accept") }
        ps.accept(s.id)
        let p = ps.profile
        if p.minutes != 45 || p.pins[future] != "SAT Practice 7" || p.focus != ["Algebra"] || p.days != [2, 4] || ps.suggestion(s.id)?.state != .accepted { f.append("coach: accept applied \(p)") }
        let d = ps.suggest(chat: [.minutes(90)], title: "t", why: "w")
        ps.dismiss(d.id)
        if ps.profile.minutes != 45 || ps.suggestion(d.id)?.state != .dismissed { f.append("coach: dismiss changed the plan") }
        // A test date must be an official date after today; a pin never in the last 6 days.
        let dec5 = SATDates.all.map(\.date).first { $0 > Clock.now }
        if let dec5, c.parse([["action": "set_test_date", "value": "", "date": Planner.day.string(from: dec5), "list": []]]).count != 1 { f.append("coach: an official date was refused") }
        if !c.parse([["action": "set_test_date", "value": "", "date": key(0), "list": []],
                     ["action": "set_test_date", "value": "", "date": key((2...9).first { n in !SATDates.all.contains { cal.isDate($0.date, inSameDayAs: day(n)) } }!), "list": []],
                     ["action": "pin_test", "value": "SAT Practice 8", "date": key(36), "list": []]]).isEmpty { f.append("coach: accepted a pin in the final days or an unofficial test date") }
        return f
    }
}

/// The Tutor page: a messenger chat with the tutor on the left (bubbles as in onboarding, its proposals as
/// Accept / Dismiss cards), the plan it talks about on the right. Numbers on both sides come from Mastery and the plan.
struct CoachView: View {
    @ObservedObject var coach = Coach.shared
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var store = Store.shared

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width >= 820
            VStack(alignment: .leading, spacing: L.gap) {
                header(wide: wide)
                HStack(alignment: .top, spacing: L.gap) {
                    chat
                    if wide { YourPlan().frame(width: 300) }
                }
            }
            .padding(L.gap)
        }
        .environment(\.openURL, QLink.action())   // "RW1 Q3" in a reply opens it in the newest test that has it
    }

    /// The page title, like Today and Plan: what the plan aims at, and how far.
    private func header(wide: Bool) -> some View {
        let c = plan.countdown
        let sub = (plan.sittingToday != nil ? "SAT today · then \(Fmt.short(c.date))" : "Plan for \(Fmt.day(c.date))")
            + (c.booked ? "" : " · Not booked") + (wide ? "" : " · \(c.days) \(c.days == 1 ? "day" : "days")")
        return PageTitle(title: "Tutor", subtitle: sub)
    }

    private var chat: some View {
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if coach.lines.isEmpty { turn(coach.opener) }
                        ForEach(coach.lines) { l in
                            Group {
                                if l.fromStudent { Text(l.text).textSelection(.enabled).bubble(mine: true, fill: Palette.well).frame(maxWidth: .infinity, alignment: .trailing) }
                                else { turn(l.text) { proposal(l) } }
                            }
                            .transition(.opacity.combined(with: .offset(y: 8)))
                        }
                        if coach.busy {
                            HStack(alignment: .top, spacing: 8) { CoachFace(size: 28); TypingDots().background(Palette.well, in: Capsule()) }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: .infinity)
                .chatScrollAnchors()
                .contentMargins(.top, 16, for: .scrollContent)   // clear of the fade when scrolled to the top
                .mask { VStack(spacing: 0) { LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 16); Color.black } }
                .onChange(of: coach.lines.count) { withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo("end") } }
            }
            prompts
            CoachComposer(coach: coach)
        }
        .padding([.horizontal, .bottom], L.inset)   // the top inset is the scroll margin, under the fade
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }

    /// One turn of the tutor: its face once, the reply in a bubble, then anything it proposes.
    private func turn(_ text: String) -> some View { turn(text) { EmptyView() } }
    /// The face sits by the turn's last line, as in Messages, so a long reply scrolled into view still shows who said it.
    private func turn(_ text: String, @ViewBuilder extra: () -> some View) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            CoachFace(size: 28)
            VStack(alignment: .leading, spacing: 6) {
                ChatText(text: text, size: 15, fill: false).bubble(fill: Palette.well)
                extra()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What the tutor proposes to change, waiting for Accept or Dismiss; afterwards it says which. The same card and buttons
    /// as the tutor's cards on Today and Plan, on the chat's well.
    @ViewBuilder private func proposal(_ l: Coach.Line) -> some View {
        if !l.changes.isEmpty {
            let s = l.suggestion.flatMap { plan.suggestion($0) }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(l.changes, id: \.self) { c in
                        Label(c, systemImage: c.hasPrefix("Undone") ? "arrow.uturn.backward" : "calendar.badge.clock").font(T.card)
                    }
                }
                if let s, s.state == .pending {
                    HStack(spacing: 8) {
                        Button("Accept") { withAnimation(.smooth(duration: 0.3)) { plan.accept(s.id) } }.buttonStyle(.card(primary: true))
                        Button("Dismiss") { withAnimation(.smooth(duration: 0.3)) { plan.dismiss(s.id) } }.buttonStyle(.card())
                    }
                } else if let s {
                    Label(s.state == .accepted ? "Accepted" : "Dismissed", systemImage: s.state == .accepted ? "checkmark" : "xmark")
                        .font(T.caption.weight(.medium)).foregroundStyle(.secondary)
                } else if l.undo != nil {   // a change from before proposals waited for Accept
                    Button("Undo") { coach.undo(l) }.buttonStyle(.card())
                }
            }
            .padding(12)
            .frame(maxWidth: 520, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    /// Up to three questions from the student's own state; a tap sends one.
    private var prompts: some View {
        let cal = Calendar.current, weekAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Clock.now))!
        var list = ["Why is my plan like this?"]
        if let m = plan.history.last(where: { $0.date >= weekAgo && $0.tasks.contains(where: \.missed) && !$0.tasks.contains(where: \.done) }) {
            list.append("I missed \(m.date.formatted(.dateTime.weekday(.wide)))")
        }
        if let s = plan.needsScore.first { list.append("My \(s.date.formatted(.dateTime.month(.abbreviated).day())) score is out") }
        if [.tight, .notEnough].contains(plan.feasibility.status) { list.append("I can study more") }
        if plan.nextSitting != nil { list.append("Move my test") }
        let chips = Array(list.prefix(3))
        return ViewThatFits(in: .horizontal) {
            ForEach([3, 2, 1], id: \.self) { n in
                HStack(spacing: 8) { ForEach(chips.prefix(n), id: \.self) { p in Chip(p) { coach.send(p) } }; Spacer(minLength: 0) }
            }
        }
        .disabled(!Brain.ready || coach.busy)
    }
}

/// The plan the tutor is talking about: the date, this week, what to drill (the same Mastery ranking the tutor
/// is given), and suggestions waiting on Today and Plan.
private struct YourPlan: View {
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var store = Store.shared

    var body: some View {
        let p = plan.profile
        let top = plan.mastery.priorities(target: p.targetScore, focus: p.focus)
        let waiting = plan.tutorItems
        VStack(alignment: .leading, spacing: 14) {
            Text("Your plan").font(T.card)
            sitting
            Divider()
            Button { store.nav = .plan } label: {
                VStack(alignment: .leading, spacing: 8) { label("This week"); WeekStrip() }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                label(p.focus.isEmpty ? "Priorities" : "Priorities · focus set")
                ForEach(top) { SkillRow(area: $0) }
            }
            if !waiting.isEmpty {
                Divider()
                // The same cards Today and Plan show; they wait there.
                Button { store.nav = .today } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            label("Waiting on Today")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        ForEach(waiting.prefix(waiting.count > 3 ? 2 : 3)) { item in Text(title(item)).font(.system(size: 13)).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                        if waiting.count > 3 { Text("\(waiting.count - 2) more").font(.system(size: 13)).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(L.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.35), value: p)
    }

    private func title(_ i: TutorCard.Item) -> String {
        switch i { case .suggestion(let s): s.title; case .score(let s): "How did your \(Fmt.short(s.date)) SAT go?" }
    }

    private func label(_ s: String) -> some View { Text(s).font(T.caption.weight(.semibold)).foregroundStyle(.secondary) }

    /// The countdown, as on Today: the next sitting (on a sitting's day, the one after it) and how far it is.
    private var sitting: some View {
        let c = plan.countdown
        return Button { store.nav = .plan } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if plan.sittingToday != nil { Text("SAT today").font(T.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Text(Fmt.day(c.date)).font(.system(size: 15, weight: .semibold))
                    Text(c.booked ? "Booked" : "Not booked").font(T.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(c.days)").font(T.value).monospacedDigit()
                Text(c.days == 1 ? "day" : "days").font(T.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The draft lives here, so typing re-renders only the composer, not the chat and the plan beside it.
private struct CoachComposer: View {
    @ObservedObject var coach: Coach
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Composer(placeholder: Brain.ready ? "Message your tutor" : "Add an AI in Settings", text: $draft,
                 enabled: Brain.ready, busy: coach.busy, focus: $focused) { coach.send(draft); draft = "" }
            .onAppear { focused = true }
    }
}

/// A button for quick prompts, with the inner radius of the card it sits in.
struct Chip: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: L.inner, style: .continuous).fill(Color.primary.opacity(hover ? 0.14 : 0.075)))
                .contentShape(RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
