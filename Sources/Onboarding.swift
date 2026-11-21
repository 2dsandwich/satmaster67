import AppKit
import SwiftUI

/// Official SAT dates (College Board, US weekend). The last ones are announced as "anticipated".
enum SATDates {
    private static func d(_ y: Int, _ m: Int, _ day: Int) -> Date { Calendar.current.date(from: DateComponents(year: y, month: m, day: day))! }
    static let all: [(date: Date, final: Bool)] = [
        (d(2026, 11, 7), true), (d(2026, 12, 5), true), (d(2027, 3, 6), true), (d(2027, 5, 1), true), (d(2027, 6, 5), true),
        (d(2027, 8, 28), false), (d(2027, 9, 18), false), (d(2027, 10, 9), false), (d(2027, 11, 6), false), (d(2027, 12, 4), false),
    ]
    static var upcoming: [(date: Date, final: Bool)] { all.filter { $0.date > Clock.now } }
}

/// First launch as a chat with the tutor, laid out like a messenger: a header, the talk from the top down, and a
/// message bar holding this step's answer controls with a send arrow. The tutor's lines are revealed word by word.
/// Every step has a default, Back always works, Return sends. The last step shows the plan as a card in the talk.
struct OnboardingView: View {
    /// The talk in order; a score step for each date already sat (spec 6).
    enum Step: Hashable { case name, dates, score(String), earlier, target, week, reminder, ai, screen, plan }
    static func flow(_ p: Profile) -> [Step] {
        [.name, .dates] + taken(p).map { .score($0.id) } + [.earlier, .target, .week, .reminder, .ai, .screen, .plan]
    }
    /// Chosen dates up to today: sat already.
    static func taken(_ p: Profile) -> [Sitting] { p.sittings.filter { $0.date <= Calendar.current.startOfDay(for: Clock.now) } }

    @State private var step: Int
    @State private var p = OnboardingView.start()
    @State private var adding: PriorScore.Kind?   // the earlier score being typed
    @State private var draft: PriorScore
    init(step: Int = 0, adding: PriorScore.Kind? = nil) {
        _step = State(initialValue: step); _adding = State(initialValue: adding)
        let used = Set(Store.shared.sessions.compactMap(\.test) + Self.start().priorScores.compactMap(\.testName))
        let test = adding == .bluebook ? TestChoice.bluebook.first { !used.contains($0) } : nil
        _draft = State(initialValue: PriorScore(kind: adding ?? .psat, date: Self.months[0], testName: test, total: 0))
    }
    @State private var connect = Brain.provider != .apple || Brain.appleProblem != nil
    @State private var prov = Brain.provider == .apple ? Provider.claude : Brain.provider
    @State private var keys: [Provider: String] = [:]
    @State private var screenOK = Capture.allowed
    @State private var shown = OnboardingView.snapshot ? Int.max : 0   // characters of the tutor's lines revealed so far
    @State private var typing = false   // the dots bubble before a line
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var still
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let snapshot = CommandLine.arguments.contains { $0.hasPrefix("--snapshot") }   // render finished lines off screen

    static func start() -> Profile {
        var p = PlanStore.shared.profile
        if p.sittings.isEmpty { p.nextBooked = SATDates.upcoming.dropFirst().first?.date ?? SATDates.upcoming.first?.date }
        if !p.onboarded { p.reminders = true }   // 17:00 unless they pick another time or Off
        return p
    }

    private var flow: [Step] { Self.flow(p) }
    private var kind: Step { flow[min(step, flow.count - 1)] }

    var body: some View {
        let lines = lines(kind)
        let done = shown >= lines.reduce(0) { $0 + $1.count }
        let talk = Array(flow.prefix(step + 1).enumerated())
        VStack(spacing: 0) {
            header(done: done)
            Divider()
            // The whole talk so far, newest at the bottom like Messages: tutor bubbles, the student's answers echoed back.
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(talk, id: \.offset) { i, s in
                        tutor(s, now: i == step, done: done)
                        if i < step { you(echo(s)).transition(.opacity.combined(with: .offset(y: still ? 0 : 10))) }
                    }
                }
                .padding(.vertical, L.inset)
                .column()
            }
            .chatScrollAnchors()
            .scrollIndicators(.never)
            Divider()
            composer(done: done)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .onReceive(poll) { _ in if kind == .screen { screenOK = Capture.allowed } }
        .task(id: step) { await reveal(lines) }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: done)
    }

    // MARK: talking

    /// Light: white bubbles on the gray chat background (like WhatsApp). Dark: gray on black (like Messages).
    private static let bubbleGray = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.17, alpha: 1) : .white })

    /// The chat's title bar: Back, the tutor, and how far along the talk is (or that it's typing).
    private func header(done: Bool) -> some View {
        HStack(spacing: 10) {
            CoachFace(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("SAT Tutor").font(.system(size: 14, weight: .semibold))
                Text(done ? "\(step + 1) of \(flow.count)" : "typing…").font(T.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
        }
        .overlay(alignment: .leading) {   // in the margin, so the tutor's face lines up with the talk below
            if step > 0 {
                Button { go(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).frame(width: 28, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor).help("Back").offset(x: -36)
            }
        }
        .padding(.vertical, 10)
        .column()
        .background(Palette.surface.ignoresSafeArea(edges: .top))
    }

    /// The message bar: this step's answer controls, then the send arrow (Return sends too).
    private func composer(done: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            answer.frame(maxWidth: .infinity, alignment: .leading)
            Button { done ? go(1) : (shown = .max) } label: {
                Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            .help(kind == .plan ? "Let's start" : "Continue")
        }
        .padding(.vertical, 12)
        .column()
        .background(Palette.surface)
    }

    /// A dots bubble before each line, then the line word by word at about 25 ms a character.
    /// A bubble has its final size from its first word.
    private func reveal(_ lines: [String]) async {
        if still || Self.snapshot { shown = .max }
        guard shown == 0 else { return }
        if step == 0 { nameFocused = false }
        var base = 0
        for line in lines {
            withAnimation(.easeOut(duration: 0.18)) { typing = true }
            try? await Task.sleep(for: .milliseconds(650))
            if Task.isCancelled || shown == .max { return }
            var k = 0
            for w in line.split(separator: " ", omittingEmptySubsequences: false) {
                try? await Task.sleep(for: .milliseconds(25 * (w.count + 1)))
                if Task.isCancelled || shown == .max { return }
                k = min(line.count, k + w.count + 1)
                withAnimation(.easeOut(duration: 0.18)) { typing = false; shown = base + k }
            }
            base += line.count
        }
        shown = .max
        if step == 0 { nameFocused = true }
    }

    /// One turn of the tutor: the avatar once, then its bubbles.
    private func tutor(_ s: Step, now: Bool, done: Bool) -> some View {
        let ls = lines(s)
        let starts = ls.indices.map { j in ls[..<j].reduce(0) { $0 + $1.count } }
        return HStack(alignment: .top, spacing: 8) {
            CoachFace(size: 28)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ls.indices, id: \.self) { j in
                    if !now || shown > starts[j] {
                        said(ls[j], now && shown != .max ? shown - starts[j] : .max).bubble(fill: Self.bubbleGray)
                            .transition(.opacity.combined(with: .offset(y: still ? 0 : 8)))
                    }
                }
                if now, typing, !done { TypingDots().background(Self.bubbleGray, in: Capsule()).transition(.opacity) }
                if s == .plan, done { planView.transition(.opacity.combined(with: .offset(y: still ? 0 : 10))) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The student's answer, echoed back after sending.
    private func you(_ text: String) -> some View {
        Text(text).bubble(mine: true, fill: Self.bubbleGray).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private static let day: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }

    private static func list(_ items: [String]) -> String {
        items.count < 3 ? items.joined(separator: " and ") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    private func echo(_ s: Step) -> String {
        let name = p.name.trimmingCharacters(in: .whitespaces)
        switch s {
        case .name: return name.isEmpty ? "I'm in \(p.grade)th grade." : "I'm \(name), in \(p.grade)th grade."
        case .dates:
            let took = Self.taken(p), ahead = p.sittings.filter { !took.contains($0) }
            let parts = (took.isEmpty ? [] : ["took " + Self.list(took.map { Self.day($0.date) })])
                + (ahead.isEmpty ? ["nothing booked yet"] : ["booked " + Self.list(ahead.map { Self.day($0.date) })])
            let line = parts.joined(separator: ", ")
            return line.prefix(1).uppercased() + line.dropFirst() + "."
        case .score(let id):
            guard let t = p.sittings.first(where: { $0.id == id })?.total, let s = p.sittings.first(where: { $0.id == id }) else { return "Not out yet." }
            return "\(s.rw!) and \(s.math!), so \(t.formatted())."
        case .earlier:
            let all = p.priorScores.map { "\($0.total.formatted()) on \($0.testName ?? ($0.kind == .psat ? "the PSAT" : "the SAT"))" }
            return all.isEmpty ? "None." : Self.list(all) + "."
        case .target: return p.targetScore.formatted()
        case .week:
            let m = [30: "30 minutes", 45: "45 minutes", 60: "an hour", 90: "an hour and a half", 120: "two hours"][p.minutes] ?? "\(p.minutes) minutes"
            return "\(p.days.count) \(p.days.count == 1 ? "day" : "days") a week, \(m) each."
        case .reminder:
            guard p.reminders else { return "No reminders." }
            let h = p.remindAt / 60, m = p.remindAt % 60
            return "\(h % 12 == 0 ? 12 : h % 12)\(m > 0 ? String(format: ":%02d", m) : "") \(h < 12 ? "am" : "pm")."
        case .ai: return connect && (prov.hasKey || !(keys[prov] ?? "").isEmpty) ? "Let's use \(prov.name)." : "The built-in one is fine."
        case .screen, .plan: return screenOK ? "Done, it's on." : "I'll turn it on later."
        }
    }

    private func said(_ s: String, _ n: Int) -> Text {
        let i = s.index(s.startIndex, offsetBy: max(0, min(n, s.count)))
        return Text("\(Text(s[..<i]))\(Text(s[i...]).foregroundStyle(.clear))")
    }

    private func lines(_ s: Step) -> [String] {
        let name = p.name.trimmingCharacters(in: .whitespaces)
        switch s {
        case .name: return ["Hi! I'm your SAT tutor.", "What's your name, and what grade are you in?"]
        case .dates: return [name.isEmpty ? "Nice to meet you." : "Nice to meet you, \(name).", "So, when is your SAT?",
                             "Pick every date: ones you took and ones you booked."]
        case .score(let id): return ["What did you get on \(p.sittings.first { $0.id == id }.map { Self.day($0.date) } ?? "that day")?"]
        case .earlier: return [Self.taken(p).isEmpty ? "Any scores so far? An SAT, a PSAT, or Bluebook practice tests." : "Any other scores? PSAT, or Bluebook practice tests."]
        case .target:   // a starting point only when there is one, and where it comes from
            let b = Planner.baseline(p, sessions: Store.shared.sessions)
            return (b.map { ["Your latest score is \($0.total.formatted()), from \($0.source)\($0.date.map { " on " + Fmt.short($0) } ?? "")."] } ?? []) + ["What score are you going for?"]
        case .week: return ["Which days can you study, and for how long?"]
        case .reminder: return ["When should I remind you to study?"]
        case .ai: return ["Which AI should I use to explain your misses?"]
        case .screen: return ["To time every question, I need to see the Bluebook window.",
                              "I only look while a test is running, and the pictures stay on this Mac.",
                              "Can you turn on screen access?"]
        case .plan: return planLines
        }
    }

    /// The date the plan works toward, as the plan card says it.
    private var goalText: String {
        let g = p.goal()
        return g.date.formatted(.dateTime.month(.wide).day()) + (g.booked ? "" : ", not booked yet")
    }

    private func go(_ d: Int) {
        if d > 0 {
            switch kind {
            case .score(let id):   // half-typed scores count as not out yet
                if let i = p.sittings.firstIndex(where: { $0.id == id }), !(Self.valid(p.sittings[i].rw, .sat) && Self.valid(p.sittings[i].math, .sat)) {
                    p.sittings[i].rw = nil; p.sittings[i].math = nil
                }
            case .earlier: if canAdd { add() }
            case .reminder:
                // macOS asks once; a "Don't Allow" turns reminders off. Test runs (SAT_DATA) never ask.
                if p.reminders, !Notifier.offline {
                    Task {
                        guard !(await Notifier.permission()) else { return }
                        p.reminders = false
                        if PlanStore.shared.profile.onboarded { PlanStore.shared.profile.reminders = false }
                    }
                }
            case .ai:
                for (pr, k) in keys where !k.trimmingCharacters(in: .whitespaces).isEmpty { pr.setKey(k) }
                UserDefaults.standard.set(connect && prov.hasKey ? prov.rawValue : Provider.apple.rawValue, forKey: "brain")
            case .plan:
                p.name = p.name.trimmingCharacters(in: .whitespaces)
                p.onboarded = true
                PlanStore.shared.profile = p
                return
            default: break
            }
        }
        let forward = d > 0
        shown = forward && !still ? 0 : .max
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = max(0, min(flow.count - 1, step + d)) }
    }

    // MARK: answers

    @ViewBuilder private var answer: some View {
        switch kind {
        case .name: nameAndGrade
        case .dates: dates
        case .score(let id): scoreEntry(id)
        case .earlier: earlier
        case .target: score
        case .week: week
        case .reminder: reminder
        case .ai: tutor
        case .screen: screen
        case .plan: Text("Let's start").font(.system(size: 15)).padding(.horizontal, 12)   // the reply, ready to send
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    private var nameAndGrade: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(9...12, id: \.self) { g in chip("\(g)th grade", nil, p.grade == g) { p.grade = g }.frame(width: 104) }
            }
            TextField("Your first name", text: $p.name)
                .textFieldStyle(.plain).font(.system(size: 15)).focused($nameFocused)
                .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 36)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    /// Official dates from a year back: tap to add or remove. Past ones were sat, later ones are booked.
    private var dates: some View {
        let cal = Calendar.current, today = cal.startOfDay(for: Clock.now)
        let from = cal.date(byAdding: .year, value: -1, to: today)!
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(SATDates.all.filter { $0.date >= from }, id: \.date) { o in
                let on = p.sittings.contains { cal.isDate($0.date, inSameDayAs: o.date) }
                chip(o.date.formatted(.dateTime.month(.abbreviated).day().year()), on ? (o.date <= today ? "Taken" : "Booked") : o.final ? nil : "expected", on) {
                    if on { p.sittings.removeAll { cal.isDate($0.date, inSameDayAs: o.date) } }
                    else { p.sittings.append(Sitting(date: cal.startOfDay(for: o.date))); p.sittings.sort { $0.date < $1.date } }
                }
            }
            chip("None booked yet", nil, !p.sittings.contains { $0.date > today }) { p.sittings.removeAll { $0.date > today } }
        }
    }

    /// R&W 200–800 and Math 200–800 (SAT and Bluebook tests); PSAT/NMSQT sections run 160–760.
    private static func valid(_ v: Int?, _ k: PriorScore.Kind) -> Bool { v.map { k == .psat ? (160...760).contains($0) : (200...800).contains($0) } ?? false }

    /// A field for one section score, labelled inside like the composer's other wells.
    private func number(_ label: String, _ value: Binding<Int?>) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            TextField("", text: Binding(get: { value.wrappedValue.map(String.init) ?? "" }, set: { value.wrappedValue = Int($0.filter(\.isNumber).prefix(3)) }))
                .textFieldStyle(.plain).monospacedDigit()
        }
        .font(.system(size: 15)).padding(.horizontal, 12).frame(width: 112, height: 36)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    private func total(_ rw: Int?, _ math: Int?, _ k: PriorScore.Kind) -> some View {
        let t = Self.valid(rw, k) && Self.valid(math, k) ? (rw! + math!).formatted() : ""
        return Text("= \(t)").font(.system(size: 15, weight: .semibold)).monospacedDigit().frame(width: 64, alignment: .leading)
    }

    private func scoreEntry(_ id: String) -> some View {
        let s = p.sittings.first { $0.id == id }
        func part(_ path: WritableKeyPath<Sitting, Int?>) -> Binding<Int?> {
            Binding(get: { p.sittings.first { $0.id == id }?[keyPath: path] },
                    set: { v in if let i = p.sittings.firstIndex(where: { $0.id == id }) { p.sittings[i][keyPath: path] = v } })
        }
        return HStack(spacing: 8) {
            number("R&W", part(\.rw))
            Text("+").foregroundStyle(.secondary)   // the same "R&W + Math = total" as Today and Settings
            number("Math", part(\.math))
            total(s?.rw, s?.math, .sat)
            Spacer(minLength: 8)
            chip("Not out yet", nil, s?.rw == nil && s?.math == nil) { if let i = p.sittings.firstIndex(where: { $0.id == id }) { p.sittings[i].rw = nil; p.sittings[i].math = nil } }
                .frame(width: 130)
        }
    }

    private static func month(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).year()) }

    /// A pop-up menu drawn as a well, the height of the fields beside it.
    private func menu(_ title: String, width: CGFloat, @ViewBuilder items: () -> some View) -> some View {
        Menu { items() } label: {
            HStack {
                Text(title).font(.system(size: 15)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(width: width, height: 36)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private static func kindName(_ k: PriorScore.Kind) -> String { k == .bluebook ? "Bluebook test" : k.rawValue.uppercased() }

    /// The first day of this month and the 23 before it, newest first.
    private static let months: [Date] = {
        let cal = Calendar.current, now = cal.date(from: cal.dateComponents([.year, .month], from: Clock.now))!
        return (0..<24).map { cal.date(byAdding: .month, value: -$0, to: now)! }
    }()

    /// Bluebook tests not already taken in the app or added here.
    private var unusedTests: [String] {
        let used = Set(Store.shared.sessions.compactMap(\.test) + p.priorScores.compactMap(\.testName))
        return TestChoice.bluebook.filter { !used.contains($0) }
    }

    private var canAdd: Bool { adding != nil && Self.valid(draft.rw, draft.kind) && Self.valid(draft.math, draft.kind) && (draft.kind != .bluebook || draft.testName != nil) }

    private func add() {
        draft.total = draft.rw! + draft.math!
        p.priorScores.append(draft)
        adding = nil
    }

    private var earlier: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach([PriorScore.Kind.psat, .sat, .bluebook], id: \.self) { k in
                    chip(Self.kindName(k), nil, adding == k) {
                        adding = k
                        draft = PriorScore(kind: k, date: Self.months[0], testName: k == .bluebook ? unusedTests.first : nil, total: 0)
                    }
                    .frame(width: 128)
                }
                chip("No", nil, adding == nil && p.priorScores.isEmpty) { adding = nil; p.priorScores = [] }.frame(width: 128)
            }
            if let k = adding {
                HStack(spacing: 8) {
                    if k == .bluebook {
                        menu(draft.testName ?? "Test", width: 156) { ForEach(unusedTests, id: \.self) { t in Button(t) { draft.testName = t } } }
                    }
                    menu(draft.date.map(Self.month) ?? "Month", width: 116) { ForEach(Self.months, id: \.self) { m in Button(Self.month(m)) { draft.date = m } } }
                    number("R&W", $draft.rw)
                    Text("+").foregroundStyle(.secondary)
                    number("Math", $draft.math)
                    total(draft.rw, draft.math, k)
                    chip("Add", nil, false, add).frame(width: 64).disabled(!canAdd).opacity(canAdd ? 1 : 0.5)
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
            if !p.priorScores.isEmpty {
                Flow(spacing: 8) {
                    ForEach(p.priorScores) { s in
                        HStack(spacing: 8) {
                            Text(s.testName.map { "\($0): \(s.total.formatted())" } ?? "\(Self.kindName(s.kind)) \(s.total.formatted())").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                            if let d = s.date { Text(Self.month(d)).font(.system(size: 14)).foregroundStyle(.secondary) }
                            Button { p.priorScores.removeAll { $0.id == s.id } } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
                        }
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                    }
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: adding)
    }

    private var score: some View {
        HStack(spacing: 16) {
            Text(p.targetScore.formatted()).font(T.value).monospacedDigit().fixedSize().frame(width: 96, alignment: .leading)
                .contentTransition(.numericText(value: Double(p.targetScore))).animation(.smooth(duration: 0.2), value: p.targetScore)
            Slider(value: Binding(get: { Double(p.targetScore) }, set: { p.targetScore = Int($0 / 10) * 10 }), in: 800...1600)
        }
        .frame(height: 36)
    }

    private var week: some View {
        let n = p.days.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Calendar.mondayFirst, id: \.self) { d in
                    let on = p.days.contains(d)
                    Button { if on { if n > 1 { p.days.remove(d) } } else { p.days.insert(d) } } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[d - 1]).font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(on ? .white : .primary)
                            .background(Circle().fill(on ? Color.accentColor : Palette.well))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach([(30, "30 min"), (45, "45 min"), (60, "1 hour"), (90, "1.5 hours"), (120, "2 hours")], id: \.0) { m, t in
                    chip(t, nil, p.minutes == m) { p.minutes = m }.frame(width: 96)
                }
            }
        }
    }

    /// Study days get a reminder at this hour with the day's tasks (Notifier); Off: none at all.
    private var reminder: some View {
        HStack(spacing: 8) {
            ForEach(16...20, id: \.self) { h in
                chip("\(h):00", nil, p.reminders && p.remindAt == h * 60) { p.reminders = true; p.remindAt = h * 60 }.frame(width: 96)
            }
            chip("Off", nil, !p.reminders) { p.reminders = false }.frame(width: 96)
        }
    }

    private var tutor: some View {
        let ok = Brain.appleProblem == nil
        let typed = Binding(get: { keys[prov] ?? "" }, set: { keys[prov] = $0 })
        let linked = prov.hasKey || !(keys[prov] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                option("apple.intelligence", "Built into your Mac", ok ? "Free and private" : (Brain.appleProblem ?? ""), !connect) { connect = false }
                option("person.crop.circle.badge.checkmark", "Your own AI account", "Claude, ChatGPT or Gemini", connect) { connect = true }
            }
            if !connect {
                // The trade-off, said once where the choice is made (HIG: an inline note, not an alert).
                Label {
                    Text("Shorter, less accurate answers, and no screenshots.")
                } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                .font(T.body).foregroundStyle(.secondary)
                .transition(.opacity)
            }
            if connect {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(Provider.allCases.filter { $0 != .apple }, id: \.self) { pr in chip(pr.name, nil, prov == pr) { prov = pr }.frame(width: 110) }
                    }
                    Text("Paste your \(prov.name) key here. It's a password from your \(prov.name) account, and it stays on this Mac.")
                        .font(T.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if linked && (keys[prov] ?? "").isEmpty {
                        Label("\(prov.name) is connected", systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.right)
                    } else {
                        HStack(spacing: 10) {
                            SecureField("Paste your key", text: typed).textFieldStyle(.roundedBorder).frame(width: 300)
                            if let u = prov.keyURL { Link("Get my key", destination: u).font(T.body) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: connect)
    }

    private func option(_ icon: String, _ title: String, _ note: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.accentColor).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(note).font(T.body).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(on ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 60)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            .overlay { if on { RoundedRectangle(cornerRadius: L.inner, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var screen: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if screenOK {
                    Label("Screen access is on", systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.right)
                } else {
                    HStack(spacing: 14) {
                        Button { CGRequestScreenCaptureAccess(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) } label: {
                            Label("Allow screen access", systemImage: "lock.open.fill")
                        }
                        .controlSize(.large)
                        Text("Turn on SAT Tracker in the list, then come back.").font(T.body).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 36, alignment: .leading)
            .animation(.smooth, value: screenOK)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor).frame(width: 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Optional: after a test, paste College Board's Score Details page and your results become exact.")
                        .font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    private func chip(_ title: String, _ note: String?, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 14, weight: on ? .semibold : .regular))
                if let note { Text(note).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(on ? Color.accentColor.opacity(0.15) : Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            .overlay { if on { RoundedRectangle(cornerRadius: L.inner, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: the plan

    private var plan: [StudyDay] { PlanStore.shared.preview(p) }

    /// Two lines from the plan's own numbers.
    private var planLines: [String] {
        let days = plan, tasks = days.flatMap(\.tasks)
        let cal = Calendar.current
        let left = cal.dateComponents([.day], from: cal.startOfDay(for: Clock.now), to: p.goal().date).day ?? 56
        let span = left < 14 ? "\(left) \(left == 1 ? "day" : "days")" : "\(Int((Double(left) / 7).rounded())) weeks"
        let tests = tasks.filter { $0.kind == .test }.count
        let word = NumberFormatter.localizedString(from: tests as NSNumber, number: .spellOut)
        let second = tests == 0 ? "\(span) until \(goalText). No full test this close, just light review."
            : "\(span) until \(goalText): \(word) practice \(tests == 1 ? "test, then its review." : "tests, each reviewed after.")"
        let top = PlanStore.shared.mastery.ranking(target: p.targetScore, focus: p.focus).first
        let third = tasks.contains { $0.kind == .drill } ? top.map { "In between, drills start with \($0.name), your top priority." } : nil
        return [second] + (third.map { [$0] } ?? [])
    }

    private var planView: some View {
        let days = plan
        let cal = Calendar.week
        let today = cal.startOfDay(for: Clock.now)
        let end = p.goal().date
        let first = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let n = max(1, (cal.dateComponents([.day], from: first, to: end).day ?? 0) / 7 + 1)
        let rows: [Int] = n > 8 ? Array(0..<5) + [-1] + [n - 2, n - 1] : Array(0..<n)   // -1: the weeks in between, folded
        let h: CGFloat = rows.count > 6 ? 22 : 26
        let byDay = Dictionary(days.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let sittings = Set(p.sittings.map { cal.startOfDay(for: $0.date) })
        let keys = Self.order.filter { k in days.contains { $0.tasks.contains { Self.key($0) == k } } }
        return VStack(alignment: .leading, spacing: 14) {
            PhaseStrip(days: days, end: end)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Color.clear.frame(width: 50, height: 1)
                    ForEach(0..<7, id: \.self) { i in
                        Text(cal.veryShortWeekdaySymbols[(cal.firstWeekday - 1 + i) % 7]).font(T.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(rows, id: \.self) { w in
                    if w < 0 {
                        Text("\(n - 7) more weeks like these").font(T.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 16)
                    } else {
                        let ws = cal.date(byAdding: .day, value: w * 7, to: first)!
                        HStack(spacing: 4) {
                            Text(ws.formatted(.dateTime.month(.abbreviated).day())).font(T.caption).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 50, alignment: .leading)
                            ForEach(0..<7, id: \.self) { i in
                                let d = cal.date(byAdding: .day, value: i, to: ws)!
                                cell(byDay[d], sat: sittings.contains(d), past: d < today, height: h)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(keys, id: \.self) { k in
                    HStack(spacing: 5) {
                        Circle().fill(Self.color(k)).frame(width: 7, height: 7)
                        Text(k).font(T.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "flag.checkered").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.accentColor)
                    Text("SAT").font(T.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(L.inset)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }

    /// The legend: drills and modules by section (the colors Today and Plan use), the rest by kind.
    private static let order = ["Full test", "Review", Sec.name(Practice.rw), Sec.name(Sec.math), "Redo misses", "Words"]
    private static func key(_ t: StudyTask) -> String? {
        if let s = t.section { return Sec.name(s) }
        return t.kind == .rest ? nil : t.kind.name
    }
    private static func color(_ k: String) -> Color {
        k == Sec.name(Practice.rw) ? Sec.color(Practice.rw) : k == Sec.name(Sec.math) ? Sec.color(Sec.math)
            : [StudyTask.Kind.test, .review, .cards, .words].first { $0.name == k }?.tint ?? .gray
    }

    private func cell(_ day: StudyDay?, sat: Bool, past: Bool, height: CGFloat) -> some View {
        let test = day?.tasks.contains { $0.kind == .test } ?? false
        let keys = (day?.tasks ?? []).compactMap(Self.key).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return ZStack {
            RoundedRectangle(cornerRadius: L.inner, style: .continuous)
                .fill(test ? Color.accentColor : sat ? Color.accentColor.opacity(0.15) : day != nil ? Palette.well : past ? Color.clear : Palette.well.opacity(0.4))
            if sat {
                Image(systemName: "flag.checkered").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accentColor)
            } else if test {
                Image(systemName: "doc.text.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            } else if keys.isEmpty, day != nil {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 3) { ForEach(keys, id: \.self) { k in Circle().fill(Self.color(k)).frame(width: 6, height: 6) } }
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
    }
}

private extension View {
    /// The chat column: header, talk and message bar share one width, centred in a wide window.
    func column() -> some View { frame(maxWidth: 760).padding(.horizontal, L.inset).frame(maxWidth: .infinity) }
}



