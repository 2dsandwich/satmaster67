import AppKit
import SwiftUI

// MARK: - Pieces shared by Today, Plan, Tutor and the menu

extension Fmt {
    /// "55 min", "2 h", "2 h 15".
    static func hm(_ m: Int) -> String { m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)" }
    static func day(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    static func short(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
}

extension Calendar {
    /// Weeks run Monday to Sunday on Today, Plan, Tutor and the onboarding plan.
    static var week: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    /// Weekday numbers (1 = Sunday) Monday first, for the study-day pickers.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
}

extension PlanStore {
    /// What the tutor asks right now: sittings to score, then changes to accept, then notes, each oldest first.
    /// Today, Plan and Tutor all show this list.
    var tutorItems: [TutorCard.Item] {
        let s = suggestions.filter { $0.kind != .askScore }.reversed()
        return needsScore.map { .score($0) } + (s.filter { $0.kind != .info } + s.filter { $0.kind == .info }).map { .suggestion($0) }
    }
    /// Every planned day, past and ahead, by start of day.
    var byDay: [Date: StudyDay] {
        Dictionary((history + days).map { (Calendar.current.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
    }
    /// Today's first task still to do: the highlighted row on Today, the menu's Today line.
    var nextTask: StudyTask? { today.flatMap { d in d.tasks.first { $0.kind != .rest && !isDone(d.date, $0) } } }
    /// A booked sitting on today's date: Today shows the sitting, not a session.
    var sittingToday: Sitting? { profile.sittings.first { $0.booked && Calendar.current.isToday($0.date) } }
    /// The countdown every screen shows: the next sitting, or on a sitting's day the one after it.
    var countdown: (date: Date, days: Int, booked: Bool) {
        let cal = Calendar.current, g = goal
        let date = sittingToday == nil ? (nextSitting?.date ?? g.date) : g.date
        let booked = sittingToday == nil ? (nextSitting != nil || g.booked) : g.booked
        return (date, cal.dateComponents([.day], from: cal.startOfDay(for: Clock.now), to: cal.startOfDay(for: date)).day ?? 0, booked)
    }
    /// The Bluebook test the tracker records: the one picked, unless it was taken (or ticked) already; then the plan's
    /// next one, else the first not taken. So the menu names the test Today and Plan show next.
    func trackChoice(_ pick: String) -> String {
        guard TestChoice.bluebook.contains(pick) else { return pick }
        let done = Set(Store.shared.sessions.compactMap(\.test) + history.flatMap(\.tasks).filter(\.done).compactMap(\.test) + profile.priorScores.compactMap(\.testName))
        guard done.contains(pick) else { return pick }
        return days.flatMap(\.tasks).compactMap(\.test).first { !done.contains($0) } ?? TestChoice.bluebook.first { !done.contains($0) } ?? pick
    }
    /// Full tests in date order: taken (tracked or logged), sittings, and the planned ones up to the goal.
    var fullTests: [FullTest] {
        let cal = Calendar.current, today = cal.startOfDay(for: Clock.now)
        var out = Planner.tests(Store.shared.sessions).map { t in
            let s = Store.shared.session(t.id)
            return FullTest(date: t.date, name: t.name ?? s?.title ?? "Full test", note: s?.scoreNote ?? "No results", kind: .taken, session: t.id)
        }
        // A planned test on a day gone by: ticked with no results in the app (as a test timed only), or missed.
        for d in history {
            guard let t = d.tasks.first(where: { $0.kind == .test }), !out.contains(where: { $0.name == t.title || cal.isDate($0.date, inSameDayAs: d.date) }) else { continue }
            out.append(FullTest(date: d.date, name: t.title, note: t.done ? "No results" : "Missed", kind: t.done ? .taken : .missed))
        }
        for s in profile.sittings where s.booked || s.date >= today {
            let past = cal.startOfDay(for: s.date) < today
            let note = s.total.map { $0.formatted() } ?? (past ? "Score pending" : cal.isToday(s.date) ? "Today" : s.booked ? "Booked" : "Not booked")
            out.append(FullTest(date: s.date, name: "SAT", note: note, kind: .sitting, pending: past && s.total == nil))
        }
        if sittingToday == nil, !goal.booked, goal.sitting == nil { out.append(FullTest(date: goal.date, name: "SAT", note: "Not booked", kind: .sitting)) }
        for d in days { if let t = d.tasks.first(where: { $0.kind == .test }), !isDone(d.date, t) { out.append(FullTest(date: d.date, name: t.title, note: "Planned", kind: .planned)) } }
        return out.sorted { $0.date < $1.date }
    }
}

/// One full test on the list: taken, an official sitting, planned, or a planned one whose day passed.
struct FullTest: Hashable {
    enum Kind { case taken, sitting, planned, missed }
    var date: Date, name: String, note: String, kind: Kind
    var session: String? = nil
    var pending = false                 // a sitting passed, its score not in yet
}

/// The one look for a card's actions everywhere (suggestions, score entry, Start): the main one in accent, the rest in a well.
/// Drawn here, not bordered-prominent, so the accent stays when the window isn't key and Tutor, Today and Plan match.
struct CardButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View { Label(primary: primary, configuration: configuration) }
    private struct Label: View {
        let primary: Bool, configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label.font(.system(size: 13, weight: .semibold)).lineLimit(1)
                .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12).frame(height: 28)
                .background(primary ? Color.accentColor : Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == CardButton {
    static func card(primary: Bool = false) -> CardButton { CardButton(primary: primary) }
}

/// "R&W [620] + Math [710] = 1,330": how a pair of section scores is typed everywhere (Today, Plan, Settings).
struct ScoreSum<A: View, B: View>: View {
    let total: Int?
    @ViewBuilder let rw: A
    @ViewBuilder let math: B
    var body: some View {
        HStack(spacing: 6) {
            rw
            Text("+").foregroundStyle(.secondary)
            math
            if let total {   // the sum once both are typed
                Text("=").foregroundStyle(.secondary)
                Text(total.formatted()).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
        .fixedSize()
    }
}

/// A section score well with the section's name beside it in its color, as the score header shows a score.
func scoreWell<F: View>(_ name: String, _ sec: String, _ field: F) -> some View {
    HStack(spacing: 5) {
        Text(name).font(T.caption.weight(.semibold)).foregroundStyle(Sec.color(sec))
        field.textFieldStyle(.plain).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 50, height: 26)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }
}

/// The tutor's proposal: a suggestion to accept or dismiss, or the score of a sitting that passed.
/// Compact: one 64-pt row (Plan, narrow Today).
struct TutorCard: View {
    enum Item: Identifiable {
        case suggestion(Suggestion), score(Sitting)
        var id: String { switch self { case .suggestion(let s): s.id; case .score(let s): "score:" + s.id } }
    }
    let item: Item
    var compact = false
    var more: [Item] = []               // the cards not shown, behind "N more suggestions" in this one
    @ObservedObject var plan = PlanStore.shared
    @State private var rw = ""
    @State private var math = ""
    @State private var showMore = false

    var body: some View {
        Group {
            // The score row needs its fields whole: a column too narrow for them gets the full card, not a clipped row.
            if compact, case .score = item { ViewThatFits(in: .horizontal) { row; card } } else if compact { row } else { card }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }

    private var row: some View {
        HStack(spacing: 12) {
            CoachFace(size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(T.card).lineLimit(1)
                if !why.isEmpty { Text(why).font(T.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if case .score = item { fields }
            buttons
        }
        .padding(.horizontal, L.inset).padding(.vertical, 10).frame(minHeight: 64)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            CoachFace(size: 24)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(T.card).fixedSize(horizontal: false, vertical: true)
                    if !why.isEmpty { Text(why).font(T.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                if case .score = item { fields }
                buttons
            }
            Spacer(minLength: 0)
        }
        .padding(L.inset)
    }

    private var title: String {
        switch item {
        case .suggestion(let s): s.title
        case .score(let s): compact ? "\(Fmt.short(s.date)) SAT score" : "How did your \(Fmt.short(s.date)) SAT go?"
        }
    }

    private var why: String {
        switch item {
        case .suggestion(let s): s.why
        case .score: compact ? "" : "Scores come out about two weeks after the test."
        }
    }

    private var fields: some View {
        let a = ScoreSheet.section(rw).value, b = ScoreSheet.section(math).value
        return ScoreSum(total: a.flatMap { x in b.map { x + $0 } }) {
            scoreWell("R&W", Practice.rw, TextField("R&W", text: $rw, prompt: Text("")))
        } math: {
            scoreWell("Math", Sec.math, TextField("Math", text: $math, prompt: Text("")))
        }
    }

    // The more button beside the actions, or under them when the column is too narrow for both.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actions; moreButton }.fixedSize()
            VStack(alignment: .leading, spacing: 8) { actions; moreButton }.fixedSize()
        }
    }

    @ViewBuilder private var moreButton: some View {
        if !more.isEmpty {
            Button("\(more.count) more \(more.count == 1 ? "suggestion" : "suggestions")") { showMore = true }.buttonStyle(.card())
                .popover(isPresented: $showMore, arrowEdge: .bottom) {
                    VStack(spacing: 8) { ForEach(more) { TutorCard(item: $0) } }
                        .padding(8).frame(width: 380).background(Palette.bg)
                }
        }
    }

    @ViewBuilder private var actions: some View {
        switch item {
        case .suggestion(let s):
            HStack(spacing: 8) {
                if s.kind != .info { Button("Accept") { withAnimation { plan.accept(s.id) } }.buttonStyle(.card(primary: true)) }
                Button("Dismiss") { withAnimation { plan.dismiss(s.id) } }.buttonStyle(.card())
            }
            .fixedSize()
        case .score(let s):
            let a = ScoreSheet.section(rw).value, b = ScoreSheet.section(math).value
            HStack(spacing: 8) {
                Button("Save") { if let a, let b { withAnimation { plan.recordScore(sitting: s.id, rw: a, math: b) } } }
                    .buttonStyle(.card(primary: true)).disabled(a == nil || b == nil)
                Button("Not out yet") { withAnimation { plan.snooze(sitting: s.id) } }.buttonStyle(.card())
            }
            .fixedSize()
        }
    }
}

/// The tutor's cards, at most `limit`; the last one shown holds the rest behind "N more suggestions" (a popover with the same cards).
struct TutorCards: View {
    let items: [TutorCard.Item]
    var limit = 2
    var compact = false

    var body: some View {
        if !items.isEmpty {
            let shown = Array(items.prefix(limit))
            VStack(spacing: 8) {
                ForEach(shown) { TutorCard(item: $0, compact: compact, more: $0.id == shown.last?.id ? Array(items.dropFirst(limit)) : []) }
            }
        }
    }
}

/// One task of a session: tick, kind icon (section-colored for skill work), title over why, minutes, Start.
struct TaskRow: View {
    let day: Date, task: StudyTask
    var primary = false
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var practice = Practice.shared

    var body: some View {
        let done = plan.isDone(day, task), rest = task.kind == .rest
        HStack(spacing: 12) {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { plan.toggle(day, task) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(done ? Palette.right : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).opacity(rest ? 0 : 1).disabled(rest)
            .accessibilityLabel(done ? "Mark \(task.title) not done" : "Mark \(task.title) done")
            Image(systemName: task.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(task.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).font(.system(size: 14, weight: .semibold)).strikethrough(done).lineLimit(1).help(task.title)
                HStack(spacing: 4) {
                    if task.carried && !done { Image(systemName: "arrow.turn.down.right") }
                    Text(done ? "Done" : task.why)
                }
                .font(T.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if task.minutes > 0 { Text(Fmt.hm(task.minutes)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).monospacedDigit().fixedSize() }
            if !done && task.target != .none {
                Button { Actions.start(task) } label: { Text(Actions.label(task)).frame(minWidth: 44) }.buttonStyle(.card(primary: primary))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(primary && !done ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        .opacity(done ? 0.55 : 1)
    }
}

/// A task in a week row: icon, short title, minutes. Click for what and why, and Start.
struct TaskPill: View {
    let day: Date, task: StudyTask
    var minutes = true
    var cap: CGFloat? = nil
    @ObservedObject var plan = PlanStore.shared
    @State private var open = false

    var body: some View {
        let done = plan.isDone(day, task)
        Button { open = true } label: {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark" : task.carried ? "arrow.turn.down.right" : task.icon)
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(done ? Palette.right : task.tint)
                Text(task.short).font(.system(size: 12, weight: .medium)).strikethrough(task.missed).frame(maxWidth: cap ?? .infinity, alignment: .leading)
                if task.missed { Text("Missed").font(.system(size: 11)).foregroundStyle(Palette.wrong) }
                else if minutes && task.minutes > 0 { Text(Fmt.hm(task.minutes)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).frame(height: 24)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            .opacity(done || task.missed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.title)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label(task.title, systemImage: task.icon).font(T.card)
                Text("\(Fmt.day(day))\(task.minutes > 0 ? " · " + Fmt.hm(task.minutes) : "")").font(T.caption).foregroundStyle(.secondary)
                if !task.why.isEmpty { Text(task.why).font(T.caption).fixedSize(horizontal: false, vertical: true) }
                if !done && task.target != .none && day >= Calendar.current.startOfDay(for: Clock.now) {
                    Button(Actions.label(task)) { open = false; Actions.start(task) }.buttonStyle(.card(primary: true))
                }
            }
            .padding(L.inset).frame(width: 260, alignment: .leading)
        }
    }
}

/// A day's tasks as pills, every one shown, wrapping onto more lines when they don't fit one (or all on one line).
struct PillRow: View {
    let day: StudyDay
    var minutes = true
    var cap: CGFloat? = nil             // the longest a pill's name may run (the narrow Plan week)
    var oneLine = false                 // every pill on one line, however long
    var body: some View {
        let pills = ForEach(day.tasks.filter { $0.kind != .rest }) { TaskPill(day: day.date, task: $0, minutes: minutes, cap: cap) }
        // A layout, not ViewThatFits: it measures at the width it is given, so the week around it sizes true.
        if oneLine { HStack(spacing: 6) { pills } } else { Flow(spacing: 6) { pills } }
    }
}

/// A non-task fact in a week row (a sitting, a test taken before the plan): icon, name, note, in a pill like the tasks.
struct FactPill: View {
    let icon: String, name: String, note: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.accentColor)
            Text(name).font(.system(size: 12, weight: .semibold))
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 8).frame(height: 24)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }
}

/// How one day of a week went or will go.
enum DayMark {
    case done, partial, open, missed, test, off, sitting

    @MainActor static func of(_ d: Date, _ day: StudyDay?, plan: PlanStore) -> DayMark {
        let cal = Calendar.current
        if plan.profile.sittings.contains(where: { $0.booked && cal.isDate($0.date, inSameDayAs: d) }) { return .sitting }
        guard let day, day.tasks.contains(where: { $0.kind != .rest }) else {
            // Before the plan: a full test taken that day shows as done (the flag is for tests still to take).
            return Planner.tests(Store.shared.sessions).contains { cal.isDate($0.date, inSameDayAs: d) } ? .done : .off
        }
        let work = day.tasks.filter { $0.kind != .rest }, done = work.count { plan.isDone(d, $0) }
        if done == work.count { return .done }
        if done > 0 { return .partial }
        if d < cal.startOfDay(for: Clock.now) { return .missed }
        return work.contains(where: { $0.kind == .test }) ? .test : .open
    }

    @ViewBuilder var view: some View {
        switch self {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.right)
        case .partial: Image(systemName: "circle.lefthalf.filled").foregroundStyle(Color.accentColor)
        case .open: Image(systemName: "circle").foregroundStyle(.secondary)
        case .missed: Image(systemName: "xmark.circle").foregroundStyle(Palette.wrong)
        case .test: Image(systemName: "flag.circle.fill").foregroundStyle(Color.accentColor)
        case .sitting: Image(systemName: "flag.checkered.circle.fill").foregroundStyle(Color.accentColor)
        case .off: Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
        }
    }
}

/// Monday to Sunday of this week: one mark per day, then minutes done of planned. Today and Tutor show the same strip.
struct WeekStrip: View {
    @ObservedObject var plan = PlanStore.shared

    var body: some View {
        let cal = Calendar.week, byDay = plan.byDay
        let start = cal.dateInterval(of: .weekOfYear, for: Clock.now)!.start
        let dates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let week = dates.compactMap { byDay[$0] }
        let planned = week.reduce(0) { $0 + $1.minutes }, done = week.reduce(0) { s, d in s + d.tasks.filter { plan.isDone(d.date, $0) }.reduce(0) { $0 + $1.minutes } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { d in
                    let today = cal.isToday(d)
                    VStack(spacing: 6) {
                        Text(cal.veryShortWeekdaySymbols[cal.component(.weekday, from: d) - 1]).font(T.caption.weight(today ? .bold : .regular))
                            .foregroundStyle(today ? Color.accentColor : .secondary)
                        DayMark.of(d, byDay[d], plan: plan).view.font(.system(size: 17)).frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if planned > 0 {
                HStack(spacing: 10) {
                    Meter(value: Double(done) / Double(planned), tint: Palette.right)
                    Text("\(Fmt.hm(done)) of \(Fmt.hm(planned))").font(T.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                }
            }
        }
    }
}

/// What to take to the SAT, each tickable (the day before and on the day).
struct BringList: View {
    static let items = ["Admission ticket", "Photo ID", "Charged device with Bluebook", "Pencils", "Calculator"]
    @State private var ticked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bring").font(T.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Self.items, id: \.self) { i in
                Button { ticked.formSymmetricDifference([i]) } label: {
                    Label(i, systemImage: ticked.contains(i) ? "checkmark.circle.fill" : "circle").font(T.body)
                        .foregroundStyle(ticked.contains(i) ? .secondary : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }
}

// MARK: - Today's header

/// The countdown to the next sitting on the left ("SAT today" on the day), the latest score against the target on the right.
struct ScoreHeader: View {
    let width: CGFloat
    var narrow = false
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var store = Store.shared

    var body: some View {
        let c = plan.countdown, sat = plan.sittingToday != nil
        let note = [sat ? "Then \(Fmt.day(c.date))" : Fmt.day(c.date), c.booked ? "Booked" : "Not booked", !sat && (1...7).contains(c.days) ? "Final week" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Button { store.nav = .plan } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(sat ? "SAT" : "\(c.days)").font(.system(size: narrow ? 48 : 64, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                        Text(sat ? "today" : c.days == 1 ? "day" : "days").font(T.section).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Text(note).font(T.body).foregroundStyle(.secondary).lineLimit(1)
                    if !c.booked { Link("Book", destination: Actions.registration).font(T.body.weight(.medium)) }
                }
            }
            .frame(width: (width - 2 * L.inset) * 0.34, alignment: .leading)
            Divider().padding(.trailing, L.inset)
            score
        }
        .padding(L.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var score: some View {
        let target = plan.profile.targetScore
        if let b = plan.baseline {
            // The latest official sitting, when the score shown is a practice test's: scored, or still to come out.
            let cal = Calendar.current
            let sitting = plan.profile.sittings.filter { $0.booked && cal.startOfDay(for: $0.date) < cal.startOfDay(for: Clock.now) }.max { $0.date < $1.date }
            let official = sitting.flatMap { s in s.id == b.id ? nil : "SAT \(Fmt.short(s.date)): " + (s.total.map { $0.formatted() } ?? "score pending") }
            Button { if let s = store.session(b.id), let o = Opening.review([s]) { store.open(o) } else { store.nav = .settings } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(b.total.formatted()).font(T.big).monospacedDigit()
                        Text("of 1,600").font(.system(size: 15)).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("Target").font(T.body).foregroundStyle(.secondary)
                        Text(target.formatted()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Palette.right).monospacedDigit()
                    }
                    ScaleBar(value: b.total, target: target)
                    HStack(spacing: 14) {
                        if let rw = b.rw { part("R&W", rw, Practice.rw) }
                        if let m = b.math { part("Math", m, Sec.math) }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(b.source + (b.date.map { " · " + Fmt.short($0) } ?? ""))
                            if let official { Text(official) }
                        }
                        .font(T.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("No score yet").font(T.section).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("Target").font(T.body).foregroundStyle(.secondary)
                    Text(target.formatted()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Palette.right).monospacedDigit()
                }
                ScaleBar(value: nil, target: target)
            }
        }
    }

    private func part(_ name: String, _ v: Int, _ sec: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(name).font(T.caption.weight(.semibold)).foregroundStyle(Sec.color(sec))
            Text("\(v)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }
}

/// 400 to 1,600 with the score filled and the target marked; the scale under it like the score card in a review.
struct ScaleBar: View {
    let value: Int?, target: Int

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let x = { (v: Int) in g.size.width * CGFloat(min(1600, max(400, v)) - 400) / 1200 }
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.well).frame(height: 8)
                    if let v = value { Capsule().fill(Color.accentColor.gradient).frame(width: max(8, x(v)), height: 8) }
                    Capsule().fill(Palette.right).frame(width: 3, height: 16).offset(x: x(target) - 1.5)
                }
            }
            .frame(height: 16)
            HStack {
                ForEach(Array([400, 800, 1200, 1600].enumerated()), id: \.offset) { i, t in
                    Text(t.formatted()).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                    if i < 3 { Spacer() }
                }
            }
        }
    }
}

// MARK: - This week and full tests (Today)

/// The week strip; opens the Plan.
struct WeekCard: View {
    var body: some View {
        Button { Store.shared.nav = .plan } label: {
            Panel("This week", icon: "calendar") { Image(systemName: "chevron.right").foregroundStyle(.tertiary) } content: { WeekStrip() }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full tests from the first taken to the sitting: what each scored, what is planned, the sittings. As many as fit,
/// the nearest to today kept (`keep`). A taken test opens its review; a sitting opens Settings.
struct TestsCard: View {
    var most = 99
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var store = Store.shared

    var body: some View {
        let all = plan.fullTests
        Panel("Full tests", icon: "doc.text") {
            ViewThatFits(in: .vertical) {
                ForEach(Array(stride(from: min(all.count, most), through: 1, by: -1)), id: \.self) { n in
                    VStack(spacing: 2) { ForEach(Array(Self.keep(all, n).enumerated()), id: \.offset) { _, t in row(t) } }
                }
                Color.clear.frame(height: 0)
            }
            Spacer(minLength: 0)
        }
    }

    /// The `n` most relevant, in date order: a sitting waiting for its score, then the next ones ahead and the latest
    /// ones behind in turn, so the far future and the far past go first.
    static func keep(_ all: [FullTest], _ n: Int, today: Date = Calendar.current.startOfDay(for: Clock.now)) -> [FullTest] {
        let ahead = all.filter { !$0.pending && $0.date >= today }, behind = Array(all.filter { !$0.pending && $0.date < today }.reversed())
        var order = all.filter(\.pending)
        for i in 0..<max(ahead.count, behind.count) {
            if i < ahead.count { order.append(ahead[i]) }
            if i < behind.count { order.append(behind[i]) }
        }
        return order.prefix(n).sorted { $0.date < $1.date }
    }

    private func row(_ t: FullTest) -> some View {
        Button {
            if let id = t.session, let s = store.session(id), let o = Opening.review([s]) { store.open(o) }
            else if t.kind == .sitting { store.nav = .settings }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: t.kind == .sitting ? "flag.checkered" : t.kind == .taken ? "doc.text.fill" : "flag.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle([.taken, .missed].contains(t.kind) ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor)).frame(width: 16)
                Text(Fmt.short(t.date)).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit().frame(width: 52, alignment: .leading)
                Text(t.name).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                let quiet = t.kind == .planned || t.note == "No results"
                Text(t.note).font(.system(size: 13, weight: quiet || t.kind == .missed ? .regular : .semibold))
                    .foregroundStyle(t.kind == .missed ? AnyShapeStyle(Palette.wrong) : quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)).monospacedDigit().fixedSize()
            }
            .frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline (Plan)

/// Today to the next sitting: phases as segments, full tests as flags, the sittings at both ends.
struct PlanTimeline: View {
    let days: [StudyDay]
    var narrow = false
    @ObservedObject var plan = PlanStore.shared
    @State private var scoring = false
    @State private var flag: Date?

    var body: some View {
        let cal = Calendar.current, today = cal.startOfDay(for: Clock.now)
        let goal = plan.goal, end = cal.startOfDay(for: goal.date)
        let past = plan.profile.sittings.filter { $0.booked && cal.startOfDay(for: $0.date) <= today }.max { $0.date < $1.date }
        Panel {
            HStack(alignment: .center, spacing: L.inset) {
                VStack(alignment: .leading, spacing: 2) {
                    if let s = past {
                        Text("\(Fmt.short(s.date)) · SAT").font(T.card)
                        if cal.isToday(s.date) { Text("Today").font(T.caption).foregroundStyle(.secondary) }
                        else if let t = s.total { Text(t.formatted()).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit() }
                        else if plan.needsScore.contains(where: { $0.id == s.id }) {
                            Button("Add score") { scoring = true }.buttonStyle(.card())
                                .popover(isPresented: $scoring) { TutorCard(item: .score(s)).frame(width: 400) }
                        } else { Text("Score pending").font(T.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("Today").font(T.card)
                        Text(Fmt.short(today)).font(T.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, alignment: .leading)
                track(today: today, end: end)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Fmt.short(end)) · SAT").font(T.card)
                    if goal.booked { Text("Booked").font(T.caption).foregroundStyle(.secondary) }
                    else { Link("Not booked", destination: Actions.registration).font(T.caption) }
                }
                .frame(width: 104, alignment: .trailing)
            }
            if narrow, plan.days.first?.phase != .taper { hoursLine }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func track(today: Date, end: Date) -> some View {
        let cal = Calendar.current
        let span = Double(max(1, cal.dateComponents([.day], from: today, to: end).day ?? 1))
        // Each phase from its first planned day to the next phase (the first from today), the last to the sitting.
        var starts: [(Phase, Date)] = []
        for d in days where d.tasks.contains(where: { $0.kind != .rest }) && starts.last?.0 != d.phase { starts.append((d.phase, cal.startOfDay(for: d.date))) }
        if !starts.isEmpty { starts[0].1 = today } else if !days.isEmpty { starts = [(.taper, today)] }   // only the rest day is left
        let segs = starts.enumerated().map { i, s in (phase: s.0, from: s.1, to: i + 1 < starts.count ? starts[i + 1].1 : end) }
        let tests = days.compactMap { d in d.tasks.first { $0.kind == .test }.map { (date: cal.startOfDay(for: d.date), task: $0) } }
        return GeometryReader { g in
            let w = g.size.width
            let x = { (d: Date) in w * CGFloat(Double(cal.dateComponents([.day], from: today, to: d).day ?? 0) / span) }
            let names = tests.map { t in "\(t.task.test ?? "Full test") · \(Fmt.short(t.date))" }
            let shown = Self.flags(tests.map { x($0.date) }, names, width: w)
            let labelX = Self.labels(segs.map { (x($0.from), $0.phase.name) }, width: w)
            ZStack(alignment: .topLeading) {
                ForEach(Array(tests.enumerated()).filter { shown[$0.offset] != nil }, id: \.offset) { i, t in
                    let labelled = shown[i] == true
                    Button { flag = t.date } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill").foregroundStyle(Color.accentColor)
                            if labelled { Text(names[i]).foregroundStyle(.secondary) }
                        }
                        .font(.system(size: 10, weight: .semibold)).fixedSize()
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { flag == t.date }, set: { if !$0 { flag = nil } }), arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.task.title).font(T.card)
                            Text("\(Fmt.day(t.date)) · about \(Fmt.hm(t.task.minutes))").font(T.caption).foregroundStyle(.secondary)
                            Text(t.task.why).font(T.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(L.inset).frame(width: 240, alignment: .leading)
                    }
                    .alignmentGuide(.leading) { d in -min(x(t.date) - 4, w - d.width) }
                }
                HStack(spacing: 2) {
                    if segs.isEmpty { Capsule().fill(Color.primary.opacity(0.12)) }
                    ForEach(Array(segs.enumerated()), id: \.offset) { i, s in
                        Capsule().fill(i == 0 ? Color.accentColor : Color.primary.opacity(0.12)).frame(width: max(4, x(s.to) - x(s.from) - 2))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 10).offset(y: 20)
                ForEach(Array(segs.enumerated()).filter { labelX[$0.offset] != nil }, id: \.offset) { i, s in
                    Text(s.phase.name).font(T.caption.weight(i == 0 ? .semibold : .regular)).foregroundStyle(i == 0 ? Color.accentColor : .secondary).fixedSize()
                        .offset(x: labelX[i]!, y: 36)
                }
            }
        }
        .frame(height: 52)
    }

    /// Flags left to right: true keeps its label, false only the flag, nil hides it (it would sit on a label).
    /// shortcut: label widths are estimated from their length at 10 pt; measure them if the font changes.
    static func flags(_ xs: [CGFloat], _ labels: [String], width: CGFloat) -> [Int: Bool] {
        var out: [Int: Bool] = [:], end = -CGFloat.infinity
        for (i, x) in xs.enumerated() {
            let w = 16 + CGFloat(labels[i].count) * 5.6, from = min(x - 4, width - w)
            if from >= end { out[i] = true; end = from + w + 10 }
            else if x - 4 >= end { out[i] = false; end = x + 10 }
        }
        return out
    }

    /// Phase names under their segment's start, pushed right past the one before and pulled left to end in the track;
    /// a middle name with no room near its segment is dropped (nil) rather than drawn over the others.
    /// shortcut: widths estimated at 6.5 pt a character for 12-pt text; measure them if the font changes.
    static func labels(_ items: [(x: CGFloat, name: String)], width: CGFloat) -> [CGFloat?] {
        let w = items.map { CGFloat($0.name.count) * 6.5 }
        var out: [CGFloat?] = [], end: CGFloat = 0
        for (i, it) in items.enumerated() { let x = max(it.x, end); out.append(x); end = x + w[i] + 12 }
        var limit = width
        for i in items.indices.reversed() {
            let x = min(out[i]!, limit - w[i])
            let before = i > 0 ? (out[i - 1] ?? 0) + w[i - 1] + 12 : 0
            if i > 0 && i < items.count - 1 && (x < before || out[i]! - x > 40) { out[i] = nil; continue }   // no room, or far from its segment
            out[i] = max(0, x); limit = out[i]! - 12
        }
        return out
    }

    private var hoursLine: some View {
        let f = plan.feasibility
        return Group {
            if f.status == .unknown { Text("No score yet").foregroundStyle(.secondary) }
            else {
                Text("Needs \(Int(f.neededPerWeek.rounded())) h a week · plan \(Int((f.plannedHours / f.weeks).rounded())) h · \(Text(Hours.word(f.status)).foregroundStyle(Hours.tint(f.status)))")
            }
        }
        .font(T.caption.weight(.medium)).monospacedDigit()
    }
}

/// Hours needed for the gain (R2) against the hours planned, per week.
enum Hours {
    static func word(_ s: Planner.Feasibility.Status) -> String {
        switch s { case .onTrack: "On track"; case .tight: "Tight"; case .notEnough: "Not enough"; case .unknown: "No score yet" }
    }
    static func tint(_ s: Planner.Feasibility.Status) -> Color {
        switch s { case .onTrack: Palette.right; case .tight: .orange; case .notEnough: Palette.wrong; case .unknown: .secondary }
    }
}

// MARK: - Skills

/// One skill on one line, the same everywhere: rank (✓ when mastered, the section's icon where ranks would differ),
/// short name (full on hover), right of seen, accuracy. Click for a practice set on it.
struct SkillRow: View {
    enum Lead { case rank(Int), mastered, section }
    let area: Mastery.Area
    var lead = Lead.section
    @ObservedObject var plan = PlanStore.shared

    var body: some View {
        let a = area
        Button { Practice.shared.begin(Planner.drill([a], minutes: 20, high: plan.profile.targetScore >= 1400).blocks ?? [], timer: false) } label: {
            HStack(spacing: 8) {
                Group {
                    switch lead {
                    case .rank(let n): Text("\(n)").foregroundStyle(Sec.color(a.section))
                    case .mastered: Image(systemName: "checkmark").foregroundStyle(Palette.right)
                    case .section: Image(systemName: Sec.icon(a.section)).foregroundStyle(Sec.color(a.section))
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().frame(width: 16, alignment: .leading)
                Text(a.short).font(.system(size: 13)).lineLimit(1).layoutPriority(1)   // the name whole; the meter gives way
                Spacer(minLength: 6)
                Text(a.seen > 0 ? "\(a.right)/\(a.seen)" : "").font(T.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                Meter(value: a.rate ?? 0, tint: a.rate.map(rateTint) ?? .clear).frame(minWidth: 20, maxWidth: 44)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .opacity({ if case .mastered = lead { 0.6 } else { 1 } }())
        }
        .buttonStyle(.plain)
        .help("\(a.name)\(a.seen > 0 ? ": \(a.right) of \(a.seen) right" : "")")
    }
}

/// What the drills work on next: Mastery's priorities, the same list as Plan, Tutor and the suggestions. Sized to them.
struct PrioritiesCard: View {
    @ObservedObject var plan = PlanStore.shared

    var body: some View {
        let p = plan.profile
        Panel(p.focus.isEmpty ? "Priorities" : "Priorities · focus set", icon: "scope") {
            VStack(spacing: 2) { ForEach(plan.mastery.priorities(target: p.targetScore, focus: p.focus)) { SkillRow(area: $0) } }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
