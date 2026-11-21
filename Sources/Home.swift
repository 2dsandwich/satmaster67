import AppKit
import Charts
import SwiftUI

// MARK: - Surfaces

extension Palette {
    /// Window background: black in dark mode (like Fitness), Apple's grouped gray in light mode.
    static let bg = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : NSColor(white: 0.949, alpha: 1) })
    /// Cards sit one step up from the background.
    static let surface = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.11, alpha: 1) : .white })
    /// Wells inside a card (tiles, fields).
    static let well = Color.primary.opacity(0.06)
}

/// A card with an optional title row: icon + title on the left, an accessory on the right.
struct Panel<Content: View, Accessory: View>: View {
    let title: String?, icon: String?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(_ title: String? = nil, icon: String? = nil, @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.accessory = accessory(); self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                    Text(title).font(T.card)
                    Spacer(minLength: 8)
                    accessory
                }
                .font(T.card)
            }
            content
        }
        .padding(L.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }
}

extension View {
    /// A list scrolling inside a card fades out at the bottom instead of cutting a row in half; the margin keeps the last row clear of the fade.
    func scrollFade() -> some View {
        scrollIndicators(.never).contentMargins(.bottom, 24, for: .scrollContent)
            .mask { VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24) } }
    }
}

/// Page title like Apple's large titles: bold word, quiet subtitle, an optional control at the trailing edge.
struct PageTitle<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let trailing: Trailing
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) { self.title = title; self.subtitle = subtitle; self.trailing = trailing() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 30, weight: .bold))
            if let subtitle { Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            trailing
        }
        .frame(height: 36)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// A switch that reads on or off at a glance, also when the window isn't key (the system switch turns gray there):
/// accent track and knob right when on, gray track and knob left when off.
struct Switch: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View { Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(Style()) }

    private struct Style: ToggleStyle {
        func makeBody(configuration: Configuration) -> some View {
            Capsule().fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.15))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5).padding(2)
                }
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
                .contentShape(Capsule())
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityAddTraits(.isToggle)
        }
    }
}

// MARK: - Main window

struct MainView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var sidebar = Sidebar.shared
    @State private var logging = false   // the "Log a practice test" sheet
    @State private var sheet = false     // a sheet is open: the page behind stops reacting to the pointer
    @State private var beforeSettings: Store.Nav?   // the Settings button toggles back to this page

    var body: some View {
        if !plan.profile.onboarded {
            OnboardingView().frame(minWidth: 900, minHeight: 640)
        } else {
            NavigationSplitView(columnVisibility: $sidebar.columns) {
                List(selection: $store.nav) {
                    Label("Today", systemImage: "sun.max.fill").tag(Store.Nav.today)
                    Label("Tutor", systemImage: "bubble.left.and.text.bubble.right.fill").tag(Store.Nav.tutor)
                    Label("Plan", systemImage: "calendar").tag(Store.Nav.plan)
                    Label("Practice", systemImage: "pencil.and.list.clipboard").tag(Store.Nav.practice)
                    Label("Flashcards", systemImage: "rectangle.on.rectangle.angled").tag(Store.Nav.cards)
                    Label("Words", systemImage: "character.book.closed").tag(Store.Nav.vocab)
                    Section {
                        ForEach(store.sessions) { s in
                            SessionRow(s: s).tag(Store.Nav.session(s.id))
                                .contextMenu { Button("Move to Trash", role: .destructive) { store.delete(s.id) } }
                        }
                    } header: {
                        HStack {
                            Text("Practice tests")
                            Spacer()
                            Button { logging = true } label: { Image(systemName: "plus") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Log a test you took without the tracker")
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
                .toolbar {   // one button at the sidebar's trailing edge; macOS moves it into the main toolbar while the sidebar is hidden
                    ToolbarSpacer(.flexible)
                    ToolbarItem { Button { sidebar.toggle() } label: { Label(sidebar.hidden ? "Show Sidebar" : "Hide Sidebar", systemImage: "sidebar.left") } }
                }
            } detail: {
                Group {
                    switch store.nav ?? .today {
                    case .today: TodayView()
                    case .tutor: CoachView()
                    case .plan: PlanView()
                    case .practice: PracticeView()
                    case .cards: FlashcardsView()
                    case .vocab: VocabView()
                    case .settings: SettingsView()
                    case .session(let id): SessionView(sid: id).id(id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bg)
                .allowsHitTesting(!sheet && !logging)
                .toolbar {
                    ToolbarItem {
                        Button {
                            if store.nav == .settings { store.nav = beforeSettings ?? .today }
                            else { beforeSettings = store.nav; store.nav = .settings }
                        } label: { Label("Settings", systemImage: "gearshape") }
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 640)
            .sheet(isPresented: $logging) { LogTestSheet() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willBeginSheetNotification)) { _ in sheet = true }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { _ in sheet = false }
        }
    }
}

/// Sidebar shown or hidden, shared by the toolbar button and View > Show/Hide Sidebar.
@MainActor final class Sidebar: ObservableObject {
    static let shared = Sidebar()
    @Published var columns = NavigationSplitViewVisibility.all
    var hidden: Bool { columns == .detailOnly }
    func toggle() { withAnimation { columns = hidden ? .all : .detailOnly } }
}

// MARK: - Today

/// What to do right now, and how far the test is: the countdown and score, today's session, the tutor's cards, this week, the full tests.
struct TodayView: View {
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var store = Store.shared

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 2 * L.gap, narrow = g.size.width < 820
            let cards = plan.tutorItems, final = plan.days.first?.phase == .taper && plan.sittingToday == nil
            VStack(alignment: .leading, spacing: L.gap) {
                PageTitle(title: "Today", subtitle: Clock.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                ScoreHeader(width: w, narrow: narrow)
                if narrow {
                    TutorCards(items: cards, limit: 1, compact: true)
                    // The final week's short session lists every day left: the week goes under it when there is room.
                    if final { ViewThatFits(in: .vertical) { VStack(spacing: L.gap) { session; WeekCard() }; session } } else { session }
                } else if final {
                    // The final week's sessions are short: the week sits under them, the tests and priorities on the right.
                    HStack(alignment: .top, spacing: L.gap) {
                        VStack(spacing: L.gap) {
                            session.fixedSize(horizontal: false, vertical: true)
                            WeekCard()
                        }
                        .frame(width: (w - L.gap) * 0.62)
                        VStack(spacing: L.gap) {
                            TutorCards(items: cards, limit: 1)
                            TestsCard().fixedSize(horizontal: false, vertical: true)
                            PrioritiesCard()
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: L.gap) {
                        session.frame(width: (w - L.gap) * 0.62)
                        // One card at a time here (the rest behind "N more suggestions"), so the week and the tests always fit.
                        VStack(spacing: L.gap) {
                            TutorCards(items: cards, limit: 1)
                            WeekCard()
                            if cards.isEmpty { PrioritiesCard() }   // the tests nearest today fill the rest
                            TestsCard()
                        }
                    }
                }
            }
            .padding(L.gap)
        }
    }

    // Today's tasks; an off day shows the next study day (studying ahead ticks it), the day before the SAT rests,
    // and on the day it is the sitting and what to bring. The next study days fill the rest of the card.
    @ViewBuilder private var session: some View {
        let cal = Calendar.current, days = plan.days
        let today = plan.today?.tasks.isEmpty == false ? plan.today : nil
        let next = days.first { !cal.isToday($0.date) && $0.tasks.contains { $0.kind != .rest } }
        // Sized to its content when every day left fits its list (the final week, the eve), not stretched empty.
        let more = { (d: Date) in days.count { $0.date > d && !$0.tasks.isEmpty } > 8 }
        if plan.sittingToday != nil {
            Panel("SAT today", icon: "flag.checkered") {
                BringList()
                ahead(after: cal.startOfDay(for: Clock.now))
            }
            .fixedSize(horizontal: false, vertical: !more(cal.startOfDay(for: Clock.now)))
        } else if let day = today ?? next {
            let work = day.tasks.filter { $0.kind != .rest }
            let done = !work.isEmpty && work.allSatisfy { plan.isDone(day.date, $0) }
            let first = work.first { !plan.isDone(day.date, $0) }
            Panel(today == nil ? "Next: \(Fmt.day(day.date))" : "Today's session", icon: "checklist") {
                if !work.isEmpty {
                    Text("\(done ? "Done" : day.phase.name) · \(Fmt.hm(day.minutes))").font(T.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } content: {
                VStack(spacing: 4) {
                    ForEach(day.tasks) { t in TaskRow(day: day.date, task: t, primary: t.id == first?.id) }
                }
                if day.tasks.contains(where: { $0.kind == .rest }) { BringList() }
                ahead(after: day.date)
            }
            .fixedSize(horizontal: false, vertical: !more(day.date))
        } else {
            Panel("Today's session", icon: "checklist") {
                Text("No study days before the next sitting.").font(T.body).foregroundStyle(.secondary)
                Button("Add a sitting") { store.nav = .settings }.buttonStyle(.card(primary: true))
                Spacer(minLength: 0)
            }
        }
    }

    /// The next study days after `day`, as many as fit, then the rest day and the sitting; a pill starts its task early.
    /// Last try (0): the next day alone on one line, names shortened.
    private func ahead(after day: Date) -> some View {
        let all = Array(plan.days.filter { $0.date > day && !$0.tasks.isEmpty }.prefix(8))
        let eve = all.last?.tasks.allSatisfy { $0.kind == .rest } == true && plan.goal.booked
        return ViewThatFits(in: .vertical) {
            ForEach(all.isEmpty ? [] : Array(stride(from: all.count, through: 1, by: -1)) + [0], id: \.self) { k in
                let n = max(k, 1), dense = k == 0
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next").font(T.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(all.prefix(n)) { d in
                        HStack(spacing: 8) {
                            Text(d.minutes > 0 ? "\(Fmt.day(d.date)) · \(Fmt.hm(d.minutes))" : Fmt.day(d.date)).font(T.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 128, alignment: .leading)
                            if d.tasks.contains(where: { $0.kind != .rest }) {
                                PillRow(day: d, minutes: false, cap: dense ? [150, 150, 150, 110][min(d.tasks.count, 3)] : nil, oneLine: dense)
                            }
                            else { Label("Rest", systemImage: "moon.zzz.fill").font(.system(size: 12)).foregroundStyle(.secondary) }
                        }
                    }
                    if n == all.count && eve {
                        HStack(spacing: 8) {
                            Text(Fmt.day(plan.goal.date)).font(T.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 128, alignment: .leading)
                            FactPill(icon: "flag.checkered", name: "SAT", note: "Booked")
                        }
                    }
                }
                .padding(.top, 8)
            }
            Color.clear.frame(height: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Thin rounded progress bar.
struct Meter: View {
    let value: Double
    var tint: Color = .accentColor
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                if value > 0 { Capsule().fill(tint).frame(width: max(6, g.size.width * min(1, value))) }
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Scores across tests

enum Score {
    /// Latest total: official when imported, otherwise nothing (a raw count isn't a score).
    static func latest(_ sessions: [Session]) -> (value: Int, official: Bool, test: String)? {
        sessions.first { $0.official?.total != nil }.map { ($0.official!.total!, true, $0.title) }
    }

    /// Points for the trend: official totals if any test has one, else percent right.
    static func points(_ sessions: [Session]) -> [(value: Int, official: Bool)] {
        let done = sessions.filter { $0.end != nil }.reversed()
        let official = done.compactMap { $0.official?.total }
        if !official.isEmpty { return official.map { ($0, true) } }
        return done.compactMap { s in
            let st = Stats(s.sections.map { s.only($0) })
            return st.marked > 0 ? (st.right * 100 / st.marked, false) : nil
        }
    }

    static func headline(_ p: [(value: Int, official: Bool)]) -> String {
        guard let last = p.last else { return "" }
        let unit = last.official ? "" : "% right"
        guard p.count > 1 else { return "\(last.value)\(unit) on your first test" }
        let d = last.value - p[p.count - 2].value
        return d == 0 ? "Holding at \(last.value)\(unit)" : "\(d > 0 ? "Up" : "Down") \(abs(d))\(last.official ? " points" : " points of %") since last test"
    }

    struct Domain { let name: String; let rate: Double; let total: Int }

    /// Accuracy by official domain across every test, weakest first (ties by name), from the one skill model.
    @MainActor static func domains(_ sessions: [Session]) -> [Domain] {
        Mastery(sessions: sessions).weakest.map { Domain(name: $0.domain, rate: $0.rate!, total: $0.seen) }
    }
}

// MARK: - Plan

/// Where the plan goes until the next sitting and whether the hours add up: the timeline, the tutor's cards,
/// the weeks, hours needed against planned (the full tests in the final week), and the skills in priority order.
struct PlanView: View {
    @ObservedObject var plan = PlanStore.shared
    @ObservedObject var store = Store.shared
    @State private var week = 0   // weeks from this one

    var body: some View {
        let days = plan.days
        let final = days.first?.phase == .taper
        GeometryReader { g in
            let w = g.size.width - 2 * L.gap, narrow = g.size.width < 820
            VStack(alignment: .leading, spacing: L.gap) {
                PageTitle(title: "Plan")
                PlanTimeline(days: days, narrow: narrow)
                // Narrow: one card across the page, so the week below keeps its height.
                if narrow { TutorCards(items: plan.tutorItems, limit: 1, compact: true) }
                HStack(alignment: .top, spacing: L.gap) {
                    VStack(spacing: L.gap) {
                        if !narrow { TutorCards(items: plan.tutorItems, compact: true) }
                        weekCard(narrow: narrow)
                    }
                    .frame(width: (w - L.gap) * (narrow ? 0.56 : 0.62))
                    VStack(spacing: L.gap) {
                        // Final week: the skills at their size, the tests nearest today in the room left.
                        if final { TestsCard() }
                        else if !narrow { hours.fixedSize(horizontal: false, vertical: true) }
                        skills.fixedSize(horizontal: false, vertical: final)
                    }
                }
            }
            .padding(L.gap)
        }
    }

    // Weeks Monday to Sunday: each day's tasks as pills, sittings, tests taken before the plan; the next week too when it fits.
    // ‹ › page through past weeks and up to the sitting.
    private func weekCard(narrow: Bool) -> some View {
        let cal = Calendar.week, byDay = plan.byDay
        let now = cal.dateInterval(of: .weekOfYear, for: Clock.now)!.start
        let start = cal.date(byAdding: .weekOfYear, value: week, to: now)!
        let shown = (0..<7).compactMap { byDay[cal.date(byAdding: .day, value: $0, to: start)!] }
        let planned = shown.reduce(0) { $0 + $1.minutes }, done = shown.reduce(0) { s, d in s + d.tasks.filter { plan.isDone(d.date, $0) }.reduce(0) { $0 + $1.minutes } }
        let first = plan.history.first.map { cal.dateComponents([.weekOfYear], from: now, to: cal.dateInterval(of: .weekOfYear, for: $0.date)!.start).weekOfYear ?? 0 } ?? 0
        let last = cal.dateComponents([.weekOfYear], from: now, to: cal.dateInterval(of: .weekOfYear, for: plan.goal.date)!.start).weekOfYear ?? 0
        // The week after, while it is still before the sitting; past the sitting, the week before (what was done).
        let after = cal.date(byAdding: .weekOfYear, value: 1, to: start)!, beyond = after > cal.startOfDay(for: plan.goal.date)
        let next = beyond ? cal.date(byAdding: .weekOfYear, value: -1, to: start)! : after
        return Panel(week == 0 ? "This week" : "Week of \(Fmt.short(start))", icon: "calendar") {
            if planned > 0 { Text("\(Fmt.hm(done)) of \(Fmt.hm(planned))").font(T.caption).foregroundStyle(.secondary).monospacedDigit() }
            HStack(spacing: 2) {
                Button { week -= 1 } label: { Image(systemName: "chevron.left") }.disabled(week <= min(0, first)).accessibilityLabel("Week before")
                Button { week += 1 } label: { Image(systemName: "chevron.right") }.disabled(week >= max(0, last)).accessibilityLabel("Week after")
            }
            .buttonStyle(.borderless)
        } content: {
            // The other week below, as many of its days as fit; then this week alone, then each day on one line.
            ViewThatFits(in: .vertical) {
                ForEach([7, 6, 5, 4, 3, 2, 1], id: \.self) { n in
                    VStack(alignment: .leading, spacing: 8) {
                        rows(start, narrow: narrow)
                        Text(week == 0 ? (beyond ? "Last week" : "Next week") : week == (beyond ? 1 : -1) ? "This week" : "Week of \(Fmt.short(next))").font(T.card).padding(.top, 4)
                        rows(next, narrow: narrow, days: n)
                    }
                }
                rows(start, narrow: narrow)
                rows(start, narrow: narrow, dense: true)
            }
            if plan.days.isEmpty && plan.nextSitting == nil {
                Button("Add a sitting") { store.nav = .settings }.buttonStyle(.card(primary: true))
            }
        }
    }

    /// Dense: each day on one line, names shortened to fit, when the wrapped week is too tall for the card.
    private func rows(_ start: Date, narrow: Bool, days: Int = 7, dense: Bool = false) -> some View {
        let cal = Calendar.week, byDay = plan.byDay
        let taken = plan.fullTests.filter { $0.kind == .taken }
        return VStack(spacing: 2) {
            ForEach((0..<days).map { cal.date(byAdding: .day, value: $0, to: start)! }, id: \.self) { d in
                let day = byDay[d], today = cal.isToday(d)
                let sitting = plan.profile.sittings.first { $0.booked && cal.isDate($0.date, inSameDayAs: d) }
                let test = taken.first { cal.isDate($0.date, inSameDayAs: d) }
                let done = sitting == nil && DayMark.of(d, day, plan: plan) == .done
                HStack(spacing: 6) {
                    Text("\(d.formatted(.dateTime.weekday(.abbreviated))) \(cal.component(.day, from: d))").font(.system(size: 13, weight: today ? .bold : .medium)).monospacedDigit()
                        .foregroundStyle(today ? Color.accentColor : d < cal.startOfDay(for: Clock.now) ? .secondary : .primary)
                        .frame(width: 52, alignment: .leading)
                    Group {
                        if let s = sitting {
                            FactPill(icon: "flag.checkered", name: "SAT", note: s.total.map { $0.formatted() } ?? (today ? "Today" : d < cal.startOfDay(for: Clock.now) ? "Score pending" : "Booked"))
                        } else if let day, day.tasks.contains(where: { $0.kind != .rest }) {
                            let n = day.tasks.count { $0.kind != .rest }
                            // Two pills a line in the narrow week; dense, all of them on one.
                            PillRow(day: day, minutes: !narrow && !dense, cap: dense ? [150, 150, 85, 45][min(n, 3)] : narrow ? 150 : nil, oneLine: dense)
                        } else if let t = test {
                            FactPill(icon: "doc.text.fill", name: t.name, note: t.note)
                        } else if day != nil {
                            Label("Rest", systemImage: "moon.zzz.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            Text("Off").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.trailing, done ? 18 : 0)   // room for the day's check
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.right) } }
                .padding(.horizontal, 8).padding(.vertical, 2).frame(minHeight: 30)
                .fixedSize(horizontal: false, vertical: true)   // a wrapped day keeps its lines; the week picks fewer days instead
                .background(today ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            }
        }
        .padding(.horizontal, -8)
    }

    // Hours the gain needs (R2) against the hours the plan holds, per week to the sitting.
    private var hours: some View {
        let f = plan.feasibility, planned = f.plannedHours / f.weeks
        let top = max(1, f.neededPerWeek, planned)
        return Panel("Hours", icon: "clock") {
            if f.status != .unknown { Text(Hours.word(f.status)).font(T.caption.weight(.semibold)).foregroundStyle(Hours.tint(f.status)) }
        } content: {
            if f.status == .unknown || plan.baseline == nil {
                Text("No score yet").font(T.body).foregroundStyle(.secondary)
            } else {
                let weeks = Int(f.weeks.rounded())
                Text("\(plan.baseline!.total.formatted()) → \(plan.profile.targetScore.formatted()) · \(weeks) \(weeks == 1 ? "week" : "weeks")").font(T.body).monospacedDigit()
                VStack(spacing: 8) {
                    bar("Needed", f.neededPerWeek, top, Hours.tint(f.status))
                    bar("Planned", planned, top, .accentColor)
                }
            }
        }
    }

    private func bar(_ name: String, _ h: Double, _ top: Double, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(name).font(T.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Meter(value: h / top, tint: tint)
            Text("\(Int(h.rounded())) h a week").font(T.caption.weight(.medium)).monospacedDigit().frame(width: 72, alignment: .trailing)
        }
    }

    // Skills in the order the plan drills them, four per section at every size, with how many of how many were right;
    // up to two mastered ones last, dimmed. Click one for a practice set on it.
    private var skills: some View {
        let p = plan.profile, m = plan.mastery
        let rank = m.ranking(target: p.targetScore, focus: p.focus)
        return Panel("Skills", icon: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach([Practice.rw, Sec.math], id: \.self) { sec in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Sec.name(sec)).font(T.caption.weight(.semibold)).foregroundStyle(Sec.color(sec))
                        ForEach(Array(rank.filter { $0.section == sec }.prefix(4).enumerated()), id: \.element.id) { i, a in SkillRow(area: a, lead: .rank(i + 1)) }
                        ForEach(m.mastered.filter { $0.section == sec }.prefix(2)) { a in SkillRow(area: a, lead: .mastered) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

}

func rateTint(_ r: Double) -> Color { r < 0.6 ? Palette.wrong : r < 0.8 ? .orange : Palette.right }

/// Phases as one bar, widths by study days, today at the left edge; the current one in accent, as on the Plan's timeline.
struct PhaseStrip: View {
    let days: [StudyDay]
    let end: Date?

    var body: some View {
        let groups = Phase.allCases.map { ph in (ph, days.filter { $0.phase == ph && $0.tasks.contains { $0.kind != .rest } }.count) }.filter { $0.1 > 0 }
        let total = max(1, groups.reduce(0) { $0 + $1.1 })
        GeometryReader { g in
            HStack(spacing: 3) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(i == 0 ? Color.accentColor : Color.primary.opacity(0.12)).frame(height: 10)
                        Text("\(item.0.name) · \(item.1) days").font(T.caption.weight(i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? Color.accentColor : .secondary).lineLimit(1).fixedSize()
                    }
                    .frame(width: max(96, (g.size.width - CGFloat(groups.count - 1) * 3) * CGFloat(item.1) / CGFloat(total)), alignment: .leading)
                }
            }
        }
        .frame(height: 32)
    }
}

extension StudyTask.Kind {
    var tint: Color {
        // Never a section color (purple, cyan), teal (equations), green or red: those mean something else here.
        switch self { case .test: .accentColor; case .review: .brown; case .cards: .orange; case .drill: .gray; case .module: .yellow; case .words: .mint; case .rest: .gray }
    }
    var name: String {
        switch self { case .test: "Full test"; case .review: "Review"; case .cards: "Redo misses"; case .drill: "Drill"; case .module: "Timed module"; case .words: "Words"; case .rest: "Rest" }
    }
}

/// The Question Bank in the browser: the second way to drill a topic, after your own misses in the app.
struct BankButton: View {
    var body: some View {
        Button { NSWorkspace.shared.open(Actions.questionBank) } label: {
            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 18).contentShape(Rectangle())   // no taller than a task line
        }
        .buttonStyle(.plain).help("Open the Question Bank").accessibilityLabel("Open the Question Bank")
    }
}

/// What "Start" opens for each task, all in the app except a Bluebook test.
@MainActor enum Actions {
    static let questionBank = URL(string: "https://satsuitequestionbank.collegeboard.org/")!
    static let registration = URL(string: "https://satsuite.collegeboard.org/sat/registration")!

    static func start(_ t: StudyTask) {
        let store = Store.shared, practice = Practice.shared
        switch t.target {
        case .bluebook(let name):   // the tracker names the test it records after the one Start picked
            UserDefaults.standard.set(name, forKey: "test")
            openBluebook()
        case .appTest: practice.begin([], timer: true, test: true)
        case .review(let id):
            if let o = Opening.review(store.session(id).map { [$0] } ?? store.sessions) { store.open(o) }
        case .errorLog, .cards:
            UserDefaults.standard.set(Card.Kind.mistake.rawValue, forKey: "cardsDeck")
            store.nav = .cards
        case .words: store.nav = .vocab
        case .practice: practice.begin(t.blocks ?? [], timer: false)
        case .module(let sec): practice.begin(Practice.preset(sec == Sec.math ? "Math module" : "R&W module", store.sessions), timer: true)
        case .none: break
        }
    }

    /// "Continue" while the set this task opens is still open, else "Start".
    static func label(_ t: StudyTask) -> String {
        let p = Practice.shared
        let open: String? = switch t.target {
        case .practice: p.current(t.blocks ?? [])
        case .module(let sec): p.current(Practice.preset(sec == Sec.math ? "Math module" : "R&W module", Store.shared.sessions))
        case .appTest: p.current([], test: true)
        default: nil
        }
        return open == nil ? "Start" : "Continue"
    }

    static func openBluebook() {
        let found = ["/Applications/Bluebook Exams.app", "/Applications/Bluebook.app"].first { FileManager.default.fileExists(atPath: $0) }
        if let found { NSWorkspace.shared.open(URL(fileURLWithPath: found)) }
        else { NSWorkspace.shared.open(URL(string: "https://bluebook.collegeboard.org/students/download-bluebook")!) }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var plan = PlanStore.shared
    @State private var key = ""
    @State private var provider = Brain.provider
    @State private var pins = Dictionary(uniqueKeysWithValues: AITask.allCases.map { ($0, UserDefaults.standard.string(forKey: "brain.\($0.rawValue)") ?? "auto") })
    @State private var auto = Settings.autoAnalyze
    @State private var screen = Capture.allowed
    @State private var access = AXIsProcessTrusted()
    @AppStorage("showBar") private var showBar = true
    @AppStorage("barSize") private var size = 1.0
    @State private var newScore: PriorScore?   // an earlier score being added
    @State private var denied = false          // notifications turned off in System Settings

    @State private var tab: String
    init(tab: String = "Study") { _tab = State(initialValue: tab) }

    var body: some View {
        VStack(alignment: .leading, spacing: L.gap) {
            PageTitle(title: "Settings") {
                Picker("Settings", selection: $tab) { ForEach(["Study", "Tutor", "App"], id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            // Two columns, so a page fits the window without scrolling or empty margins.
            HStack(alignment: .top, spacing: L.gap) {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case "Tutor": tutorGroup; changesGroup
                    case "App": timerGroup; dataGroup
                    default: youGroup; sittingsGroup; earlierGroup
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case "Tutor": modelsGroup
                    case "App": permissionsGroup; shortcutsGroup
                    default: studyGroup; comingGroup
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(L.gap)
        .task {   // while Settings is on screen: notice a permission granted in System Settings
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let s = Capture.allowed, a = AXIsProcessTrusted()
                if s != screen { screen = s }
                if a != access { access = a }
            }
        }
    }

    private var youGroup: some View {
        group("You") {
            row("Name", "person.fill", .blue) {
                TextField("Name", text: $plan.profile.name, prompt: Text("Your name")).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(maxWidth: 240)
            }
            row("Grade", "graduationcap.fill", .indigo) {
                Picker("Grade", selection: $plan.profile.grade) { ForEach(9...12, id: \.self) { Text("Grade \($0)").tag($0) } }.labelsHidden().fixedSize()
            }
        }
    }

    private var sittingsGroup: some View {
        group("Sittings") {
            ForEach(plan.profile.sittings) { s in sittingRow(s) }
            row("Add a date", "plus", .gray) {
                let cal = Calendar.current
                Menu {
                    ForEach(SATDates.all.filter { o in !plan.profile.sittings.contains { cal.isDate($0.date, inSameDayAs: o.date) } }, id: \.date) { o in
                        Button(o.date.formatted(date: .long, time: .omitted) + (o.final ? "" : " (expected)")) {
                            plan.profile.sittings.append(Sitting(date: cal.startOfDay(for: o.date)))
                            plan.profile.sittings.sort { $0.date < $1.date }
                        }
                    }
                } label: { Image(systemName: "calendar.badge.plus") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Add a date")
            }
        }
    }

    private var earlierGroup: some View {
        group("Earlier scores") {
            ForEach(plan.profile.priorScores) { p in
                row(p.testName ?? (p.kind == .psat ? "PSAT" : "SAT"), p.kind == .bluebook ? "doc.text.fill" : "graduationcap.fill", .indigo) {
                    if let d = p.date { Text(d.formatted(.dateTime.month(.abbreviated).year())).foregroundStyle(.secondary) }
                    Text((p.rw.flatMap { r in p.math.map { "\(r) + \($0) = " } } ?? "") + p.total.formatted()).fontWeight(.semibold).monospacedDigit()
                    remove { plan.profile.priorScores.removeAll { $0.id == p.id } }
                }
            }
            if newScore != nil { newScoreRow } else {
                row("Add a score", "plus", .gray) {
                    Menu {
                        Button("PSAT") { newScore = PriorScore(kind: .psat, date: Clock.now, total: 0) }
                        Button("SAT") { newScore = PriorScore(kind: .sat, date: Clock.now, total: 0) }
                        Button("Bluebook test") {
                            let used = Set(plan.profile.priorScores.compactMap(\.testName) + Store.shared.sessions.compactMap(\.test))
                            newScore = PriorScore(kind: .bluebook, date: Clock.now, testName: TestChoice.bluebook.first { !used.contains($0) } ?? TestChoice.bluebook[0], total: 0)
                        }
                    } label: { Image(systemName: "plus.circle") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Add a score")
                }
            }
        }
    }

    private var studyGroup: some View {
        group("Study") {
            row("Target score", "target", .green) {
                Text("\(plan.profile.targetScore)").monospacedDigit()
                Stepper("Target score", value: $plan.profile.targetScore, in: 400...1600, step: 10).labelsHidden()
            }
            row("Study days", "checklist", .orange) {
                HStack(spacing: 6) {
                    ForEach(Calendar.mondayFirst, id: \.self) { d in
                        let on = plan.profile.days.contains(d)
                        Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                            if on, plan.profile.days.count > 1 { plan.profile.days.remove(d) } else { plan.profile.days.insert(d) }
                        }
                        .buttonStyle(.plain).font(T.caption.weight(.semibold))
                        .frame(width: 26, height: 26).foregroundStyle(on ? .white : .secondary)
                        .background(Circle().fill(on ? Color.accentColor : Palette.well))
                        .accessibilityLabel(Calendar.current.weekdaySymbols[d - 1])
                    }
                }
            }
            row("Minutes a day", "clock.fill", .orange) {
                Picker("Minutes a day", selection: $plan.profile.minutes) { ForEach([30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) } }.labelsHidden().fixedSize()
            }
            row("Reminder", "bell.fill", .red) {
                if denied {
                    Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                } else if plan.profile.reminders {
                    DatePicker("Reminder time", selection: Binding(get: { Calendar.current.startOfDay(for: Clock.now).addingTimeInterval(Double(plan.profile.remindAt * 60)) },
                                                                  set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); plan.profile.remindAt = (c.hour ?? 17) * 60 + (c.minute ?? 0) }),
                               displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                }
                Switch(title: "Reminder", isOn: Binding(get: { plan.profile.reminders }, set: { on in
                    guard on else { plan.profile.reminders = false; return }
                    Task { if await Notifier.permission() { plan.profile.reminders = true; denied = false } else { denied = true } }
                }))
            }
        }
    }

    /// The next reminders the plan has scheduled, as the Reminder setting makes them.
    @ViewBuilder private var comingGroup: some View {
        let next = Notifier.requests(plan.profile, days: plan.days, suggestions: plan.suggestions, now: Clock.now).filter { $0.date > Clock.now }.sorted { $0.date < $1.date }.prefix(5)
        if !next.isEmpty {
            group("Coming up") {
                ForEach(Array(next), id: \.id) { r in
                    // A study reminder goes by its day, the time beside it: one line each, so the list fits the small window.
                    let study = r.title == "Today's session"
                    row(study ? r.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " session" : r.title, "bell.fill", .red) {
                        Text(r.date.formatted(study ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    /// What the tutor proposed and what became of it, newest first.
    @ViewBuilder private var changesGroup: some View {
        let done = plan.suggestionLog.filter { $0.state != .pending && [.change, .chat].contains($0.kind) }.suffix(4).reversed()
        if !done.isEmpty {
            group("Plan changes") {
                ForEach(Array(done)) { s in
                    row(s.title, s.state == .accepted ? "checkmark" : "xmark", s.state == .accepted ? .green : .gray) {
                        Text("\(s.state == .accepted ? "Accepted" : "Dismissed") \(Fmt.short(s.created))").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var tutorGroup: some View {
        // Apple Intelligence's trade-off, said once: under the first place it is picked (HIG: inline, no alert).
        group("Tutor") {
            VStack(alignment: .leading, spacing: 0) {
                row("Explains with", "sparkles", .purple) {
                    Picker("Explains with", selection: $provider) { ForEach(Provider.allCases, id: \.self) { p in Text(p.name).tag(p) } }.labelsHidden().fixedSize()
                        .onChange(of: provider) { UserDefaults.standard.set(provider.rawValue, forKey: "brain"); key = "" }
                }
                if provider == .apple { appleWarning }
            }
            // Only when something needs fixing; a working setup needs no status line.
            if provider == .apple, let problem = Brain.appleProblem {
                row("Status", "exclamationmark.triangle.fill", .orange) { Text(problem).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
            } else if provider != .apple, !provider.hasKey, let u = provider.keyURL {
                row("Status", "key.fill", .orange) { Link("Get a \(provider.name) key", destination: u) }
            }
            if provider != .apple {
                row("API key", "key.fill", .gray) {
                    SecureField("API key", text: $key, prompt: Text(provider.hasKey ? "Replace key" : "Paste your key")).textFieldStyle(.roundedBorder).frame(width: 180)
                    Button("Save") { provider.setKey(key.trimmingCharacters(in: .whitespaces)); key = "" }.buttonStyle(.card(primary: true)).disabled(key.isEmpty)
                }
            }
            row("Explain every question when a test ends", "text.bubble.fill", .teal) {
                Switch(title: "Explain every question when a test ends", isOn: $auto).onChange(of: auto) { Settings.autoAnalyze = auto }
            }
        }
    }

    private var modelsGroup: some View {
        let usable = Provider.allCases.filter { $0 == .apple ? Brain.appleReady : $0.hasKey }
        // A pin that can't run (no key, Apple Intelligence off) shows as Auto, which is what runs.
        let pinned = Dictionary(uniqueKeysWithValues: AITask.allCases.map { t in (t, usable.contains { $0.rawValue == pins[t] } ? pins[t]! : "auto") })
        let warnAt = provider == .apple ? nil : AITask.allCases.first { pinned[$0] == Provider.apple.rawValue }
        return group("Model for each task") {
            ForEach(AITask.allCases, id: \.self) { t in
                let pin = pinned[t]!
                VStack(alignment: .leading, spacing: 0) {
                    row(t.name, t.icon, .purple) {
                        Picker(t.name, selection: Binding(get: { pin }, set: { pins[t] = $0; UserDefaults.standard.set($0, forKey: "brain.\(t.rawValue)") })) {
                            Text("Auto (\((provider.hasKey ? provider : Brain.provider).name))").tag("auto")
                            ForEach(usable, id: \.self) { p in Text(p.name).tag(p.rawValue) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    if t == warnAt { appleWarning }
                }
            }
        }
    }

    private var timerGroup: some View {
        group("Floating timer") {
            row("Show during a test", "timer", .orange) {
                Switch(title: "Show during a test", isOn: $showBar).onChange(of: showBar) { AppDelegate.shared?.updateBar() }
            }
            row("Size", "textformat.size", .gray) {
                Picker("Size", selection: $size) { ForEach(Bar.sizes, id: \.scale) { Text($0.name).tag($0.scale) } }.labelsHidden().fixedSize()
            }
        }
    }

    private var permissionsGroup: some View {
        group("Permissions") {
            permission("Screen Recording", "rectangle.dashed.badge.record", .red, ok: screen, pane: "Privacy_ScreenCapture")
            permission("Accessibility", "accessibility", .blue, ok: access, pane: "Privacy_Accessibility")
        }
    }

    private var shortcutsGroup: some View {
        group("Shortcuts") {
            ForEach(HotKeys.list, id: \.label) { h in
                row(h.name, "command", .gray) { Text(h.label).monospaced().foregroundStyle(.secondary) }
            }
        }
    }

    private var dataGroup: some View {
        group("Data") {
            row("Folder", "folder.fill", .blue) {
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: Store.shared.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Store.shared.root)
                }
            }
            row("Setup", "arrow.counterclockwise", .gray) { Button("Run setup again") { plan.profile.onboarded = false } }
        }
    }

    private var appleWarning: some View {
        Label("Apple Intelligence: shorter, less accurate answers, and no screenshots.", systemImage: "exclamationmark.triangle")
            .font(T.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 34).padding(.bottom, 10)
    }

    /// A System Settings section: quiet header, rows on one surface card with inset dividers.
    private func group<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(T.card).foregroundStyle(.secondary).padding(.leading, L.inset)
            VStack(spacing: 0) {
                Group(subviews: rows()) { subs in
                    ForEach(Array(subs.enumerated()), id: \.offset) { i, v in
                        if i > 0 { Divider().padding(.leading, 34) }
                        v
                    }
                }
            }
            .padding(.horizontal, L.inset).padding(.vertical, 4)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))   // badge 6 + inset 16, concentric
        }
    }

    /// One row: white symbol on a colored rounded square, the label, the control right-aligned; the control goes under
    /// the label when the column is too narrow for both.
    private func row<C: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder _ control: () -> C) -> some View {
        let badge = Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24).background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        let c = control()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                badge
                Text(title).font(.system(size: 13)).fixedSize()
                Spacer(minLength: 12)
                HStack(spacing: 8) { c }.fixedSize()
            }
            .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { badge; Text(title).font(.system(size: 13)) }
                HStack(spacing: 8) { Spacer(minLength: 0); c }
            }
            .padding(.vertical, 8)
        }
    }

    /// A sitting: taken ones (past) hold the official scores, coming ones are booked or only aimed for.
    private func sittingRow(_ s: Sitting) -> some View {
        let past = s.date < Calendar.current.startOfDay(for: Clock.now)
        return row(s.date.formatted(.dateTime.month(.abbreviated).day().year()), "flag.checkered", past ? .gray : .blue) {
            if past {
                ScoreSum(total: s.total) { scoreField("R&W", Practice.rw, sitting(s.id, \.rw)) } math: { scoreField("Math", Sec.math, sitting(s.id, \.math)) }
            } else {
                Text(s.booked ? "Booked" : "Not booked").foregroundStyle(.secondary)
                Switch(title: "Booked", isOn: Binding(get: { s.booked }, set: { v in edit(s.id) { $0.booked = v } }))
            }
            remove { plan.profile.sittings.removeAll { $0.id == s.id } }
        }
    }

    private func edit(_ id: String, _ change: (inout Sitting) -> Void) {
        if let i = plan.profile.sittings.firstIndex(where: { $0.id == id }) { change(&plan.profile.sittings[i]) }
    }

    private func sitting(_ id: String, _ kp: WritableKeyPath<Sitting, Int?>) -> Binding<Int?> {
        Binding(get: { plan.profile.sittings.first { $0.id == id }?[keyPath: kp] }, set: { v in edit(id) { $0[keyPath: kp] = v } })
    }

    /// A section score, 200–800 in steps of 10; anything else is left as it was.
    private func scoreField(_ name: String, _ sec: String, _ value: Binding<Int?>) -> some View {
        scoreWell(name, sec, TextField(name, value: Binding(get: { value.wrappedValue }, set: { v in if v.map({ (200...800).contains($0) && $0 % 10 == 0 }) ?? true { value.wrappedValue = v } }),
                                       format: .number.grouping(.never), prompt: Text("")))
    }

    private func remove(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Remove")
    }

    /// The score being added: kind (and Bluebook test), month, both sections.
    private var newScoreRow: some View {
        let n = newScore!
        let rw = Binding<Int?>(get: { newScore?.rw }, set: { newScore?.rw = $0 }), math = Binding<Int?>(get: { newScore?.math }, set: { newScore?.math = $0 })
        return row(n.kind == .psat ? "PSAT" : n.kind == .sat ? "SAT" : "", n.kind == .bluebook ? "doc.text.fill" : "graduationcap.fill", .indigo) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if n.kind == .bluebook {
                        Picker("Test", selection: Binding(get: { newScore?.testName ?? "" }, set: { newScore?.testName = $0 })) {
                            ForEach(TestChoice.bluebook, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    DatePicker("Date", selection: Binding(get: { newScore?.date ?? Clock.now }, set: { newScore?.date = $0 }), in: ...Clock.now, displayedComponents: .date)
                        .labelsHidden().fixedSize()
                    remove { newScore = nil }
                }
                HStack(spacing: 8) {
                    ScoreSum(total: n.rw.flatMap { a in n.math.map { a + $0 } }) { scoreField("R&W", Practice.rw, rw) } math: { scoreField("Math", Sec.math, math) }
                    Button("Add") {
                        guard var s = newScore, let a = s.rw, let b = s.math else { return }
                        s.total = a + b
                        plan.profile.priorScores.append(s)
                        newScore = nil
                    }
                    .buttonStyle(.card(primary: true)).disabled(n.rw == nil || n.math == nil)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func permission(_ name: String, _ icon: String, _ tint: Color, ok: Bool, pane: String) -> some View {
        row(name, icon, tint) {
            if ok { Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.right) }
            else { Button("Open Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!) } }
        }
    }
}
