import Combine
import SwiftUI

// The test screen for practice questions and full tests, laid out and colored like College Board's Bluebook app.
// It is always light, whatever the app's appearance, and uses no app colors inside the test.

/// Bluebook's colors.
enum BB {
    static func hex(_ v: Int) -> Color { Color(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255) }
    static let page = Color.white, bar = hex(0xF0F2F7), rule = hex(0x505050), ink = hex(0x1A1A1A)
    static let blue = hex(0x2F3FB8), navy = hex(0x1E2B6F), border = hex(0x7A7A7A), band = hex(0xF2F2F2), red = hex(0xC8102E)
    /// Highlight colors, soft like Bluebook's; the first is the default.
    static let marks: [(String, Color)] = [("yellow", hex(0xFCE38A)), ("blue", hex(0xBFDCF7)), ("pink", hex(0xF9C6DA))]
    static func mark(_ name: String) -> Color { marks.first { $0.0 == name }?.1 ?? marks[0].1 }
}

/// A full-width dashed rule, as under Bluebook's top bar and above its bottom bar.
struct Dashes: View {
    var width: CGFloat = 1
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: CGPoint(x: 0, y: width / 2)); p.addLine(to: CGPoint(x: g.size.width, y: width / 2)) }
                .stroke(BB.rule, style: StrokeStyle(lineWidth: width, dash: [6, 4]))
        }
        .frame(height: width)
    }
}

/// Bluebook's navy capsule button (Back, Next, Check).
struct BBButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 22).frame(height: 36)
            .background(BB.blue.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35), in: Capsule())
            .contentShape(Capsule())
    }
}

/// The small outlined capsule (Hide, Go to Review Page).
struct BBOutline: ButtonStyle {
    var size: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: size, weight: .semibold)).foregroundStyle(size > 12 ? BB.blue : BB.ink)
            .padding(.horizontal, size > 12 ? 22 : size).padding(.vertical, size > 12 ? 0 : size / 3)
            .frame(height: size > 12 ? 36 : nil)   // the big one pairs with BBButton, so same height
            .background(Capsule().strokeBorder(size > 12 ? BB.blue : BB.ink, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1).contentShape(Capsule())
            .focusEffectDisabled()
    }
}

// MARK: - Full-test flow

extension Practice {
    /// Module 1's share right decides Module 2: the harder route at 70% or more.
    static func harder(_ s: PracticeSet, _ m: Int) -> Bool {
        guard let r = s.modules?[m].range, !r.isEmpty else { return false }
        return Double(r.filter(s.right).count) >= 0.7 * Double(r.count)
    }

    /// Halfway through Module 1, Module 2 starts on the route the answers so far point to; `lock` keeps it only if the
    /// final score agrees, so the student rarely waits between modules.
    func speculate(_ id: String) {
        guard let s = set(id), let m = s.stage, let mods = s.modules, mods.indices.contains(m + 1), mods[m].number == 1 else { return }
        let answered = mods[m].range.filter { s.work[$0].answer != nil }
        guard !answered.isEmpty, answered.count * 2 >= mods[m].count else { return }
        prepare(id, m + 1, hard: Double(answered.filter(s.right).count) >= 0.7 * Double(answered.count))
    }

    /// Ends the module on screen and moves on. True when a break comes next (between the sections).
    @discardableResult func lock(_ id: String) -> Bool {
        guard let s = set(id), let m = s.stage, let mods = s.modules, mods.indices.contains(m) else { return false }
        if mods[m].number == 1, mods.indices.contains(m + 1), mods[m + 1].count == 0 {
            let hard = Self.harder(s, m)
            update(id) { $0.modules![m + 1].hard = hard }
            parts[id]?.removeAll { $0.module == m + 1 && $0.hard != hard }
            prepare(id, m + 1, hard: hard)
            commit(id, m + 1)   // already written on this route
        }
        update(id) { $0.stage = m + 1 }
        guard mods.indices.contains(m + 1) else { finishTest(id); return false }
        return mods[m + 1].section != mods[m].section
    }

    /// The test is over: it becomes a tracked test, and the tutor reviews each section (one call each).
    private func finishTest(_ id: String) {
        update(id) { $0.done = true }
        guard let s = set(id) else { return }
        let session = Self.session(s)
        Store.shared.save(session)
        update(id) { $0.session = session.id }
        Task { for sec in session.sections { await Tutor.debrief(session.id, sec) } }
    }

    /// A full test as a tracked test: its visits, College Board-style answers with the question text, and each explanation
    /// as the tutor's analysis, so the test reviews, timelines, filters and stats read it like a Bluebook test.
    static func session(_ s: PracticeSet) -> Session {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HHmmss"
        let start = s.visits?.map(\.start).min() ?? s.date
        var out = Session(id: f.string(from: start), start: start)
        out.test = "Practice test · " + start.formatted(.dateTime.month(.abbreviated).day())
        out.source = "SAT Tracker"
        out.visits = (s.visits ?? []).map { var v = $0; v.end = v.end ?? v.start; return v }
        var o = Official()
        for mod in s.modules ?? [] {
            let close = out.visits.filter { $0.section == mod.section && $0.module == mod.number }.compactMap(\.end).max() ?? start
            for (j, i) in mod.range.enumerated() {
                let q = s.questions[i], w = s.work[i], key = Session.key(mod.section, mod.number, j + 1), right = s.right(i)
                if !out.visits.contains(where: { $0.key == key }) {   // never opened: it still counts, as a blank
                    out.visits.append(Visit(section: mod.section, module: mod.number, number: j + 1, start: close, end: close))
                }
                o.answers[key] = .init(correct: q.correct, yours: w.answer, question: q.question, passage: q.passage.isEmpty ? nil : q.passage,
                                       choices: q.choices.isEmpty ? nil : q.choices, domain: q.domain, skill: q.skill, difficulty: q.difficulty, right: right)
                let note = w.answer.flatMap { letters.firstIndex(of: $0) }.flatMap { q.choiceNotes.indices.contains($0) ? q.choiceNotes[$0] : nil }
                var st = QState()
                st.flagged = w.marked
                st.analysis = Analysis(questionEn: q.passage.isEmpty ? q.question : q.passage + "\n\n" + q.question, questionJa: "", topic: q.domain,
                                       skill: q.skill, difficulty: q.difficulty, correctAnswer: q.correct, studentAnswer: w.answer ?? "none",
                                       verdict: w.answer == nil ? "unanswered" : right ? "correct" : "wrong", solutionJa: q.solutionJa, wordingJa: "",
                                       trapJa: q.trapJa, timeJa: "", vocab: q.vocab, coachLine: note?.isEmpty == false ? note : nil,
                                       keyPoint: q.keyPoint, desmos: q.desmos, desmosFocus: q.desmosFocus.isEmpty ? nil : q.desmosFocus)
                out.q[key] = st
            }
        }
        out.visits.sort { $0.start < $1.start }
        out.official = o
        out.section = s.sections.first ?? Sec.math
        out.end = out.visits.compactMap(\.end).max() ?? start
        return out
    }
}

// MARK: - Test screen

struct PracticeTest: View {
    enum Phase { case questions, review, over, rest, wait }
    let id: String
    @ObservedObject var practice = Practice.shared
    @State private var i: Int
    @State private var phase: Phase
    @State private var calc: Bool
    @State private var shownAt = Date()
    @State private var now = Date()
    @State private var crossing = false
    @State private var navigator = false
    @State private var hidden = false
    @State private var reference = false
    @State private var directions = false
    @State private var more = false
    @State private var toastGone = false
    @State private var breakAfter = false
    @State private var split: CGFloat = 0.5
    @State private var calcWidth: CGFloat = 440
    @State private var wide = false
    @State private var restEnds = Date() + 600
    @State private var highlighting: Bool
    @State private var hue = BB.marks[0].0
    @State private var restarting = false
    @State private var submitting = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// `at` and `phase` open a given screen (snapshots); otherwise the test resumes where it was left.
    init(id: String, phase: Phase = .questions, at i: Int? = nil, calc: Bool = false, highlight: Bool = false, more: Bool = false) {
        self.id = id; _more = State(initialValue: more)
        _phase = State(initialValue: phase); _i = State(initialValue: i ?? -1); _calc = State(initialValue: calc); _highlighting = State(initialValue: highlight)
    }

    var body: some View {
        if let s = practice.set(id) {
            VStack(spacing: 0) {
                if phase == .rest { rest } else {
                    top(s).zIndex(1)   // the More menu hangs over the page below
                    VStack(spacing: 0) {
                        Dashes()
                        switch phase {
                        case .questions:
                            if s.questions.indices.contains(i) {
                                content(s, s.questions[i]).overlay(alignment: .top) { banner(s.full) }
                                    .overlay(alignment: .bottomTrailing) {   // practice questions only: ask the tutor once a question is checked
                                        if !s.full, s.work[i].checked == true { chat(s.work[i]).id(i).padding(20) }
                                    }
                            }
                        case .review: review(s).overlay(alignment: .top) { banner(s.full) }
                        case .over: over
                        default: wait(s)
                        }
                        if phase == .questions || phase == .review { Dashes(); bottom(s) }
                    }
                    .overlay { if more { Color.clear.contentShape(Rectangle()).onTapGesture { more = false } } }   // a click elsewhere closes the menu
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BB.page)
            .foregroundStyle(BB.ink)
            .overlay {
                if let then = practice.leaving {
                    dialog("Leave This Test?", "Your answers and time are saved. You can resume it from Past sets.") {
                        Button("Discard Test") { practice.leaving = nil; practice.discard(id); then() }
                            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.red)
                        Spacer()
                        Button("Keep Testing") { practice.leaving = nil }.buttonStyle(BBOutline(size: 14)).fixedSize()
                        Button("Save and Exit") { practice.leaving = nil; leave(); practice.open = nil; then() }.buttonStyle(BBButton())
                    }
                } else if submitting {
                    dialog(s.full ? "Submit This Module?" : "Submit Your Answers?",
                           s.full ? "You can't come back to these questions after you move on." : "You'll see your score and the explanations. Answers can't be changed after that.") {
                        Spacer()
                        Button("Cancel") { submitting = false }.buttonStyle(BBOutline(size: 14)).fixedSize()
                        Button("Submit") {
                            submitting = false
                            if s.full { leave(); breakAfter = practice.lock(id); afterModule() } else { finish() }
                        }.buttonStyle(BBButton())
                    }
                } else if restarting {
                    dialog(s.full ? "Restart This Test?" : "Restart These Questions?", "Answers, marks, highlights, notes and time go back to zero.") {
                        Spacer()
                        Button("Cancel") { restarting = false }.buttonStyle(BBOutline(size: 14)).fixedSize()
                        Button("Restart") { restarting = false; restart() }.buttonStyle(BBButton())
                    }
                }
            }
            .environment(\.colorScheme, .light)
            .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
            .padding(L.gap)
            .onReceive(tick) { t in now = t; ticked() }
            .onAppear { resume(s) }
            .onDisappear { leave() }
        }
    }

    // MARK: Flow

    private func module(_ s: PracticeSet) -> PracticeSet.Module? {
        guard let m = s.stage, let mods = s.modules, mods.indices.contains(m) else { return nil }
        return mods[m]
    }
    /// The questions the navigator holds: the module's, or the whole set.
    private func range(_ s: PracticeSet) -> [Int] { module(s).map { Array($0.range) } ?? Array(s.questions.indices) }
    private func timed(_ s: PracticeSet) -> Bool { s.full || s.timer == true }
    private func remaining(_ s: PracticeSet) -> Double {
        let live = phase == .questions || phase == .review ? now.timeIntervalSince(shownAt) : 0
        if let mod = module(s) { return mod.limit - mod.used - live }
        return s.limit - s.work.map(\.seconds).reduce(0, +) - live
    }

    private func resume(_ s: PracticeSet) {
        if i >= 0 { show(); return }   // a given screen
        if s.full { begin() } else { i = s.work.firstIndex { $0.checked != true } ?? 0; show() }
    }

    /// Opens the module on screen at its first blank question, or waits while it is written.
    private func begin() {
        guard let s = practice.set(id), let m = s.stage, let mod = module(s) else { return }
        if mod.count == 0 { phase = .wait; practice.prepare(id, m, hard: mod.hard); return }
        i = mod.range.first { s.work[$0].answer == nil } ?? mod.first
        phase = .questions; crossing = false; toastGone = false
        show()
    }

    private func ticked() {
        guard let s = practice.set(id) else { return }
        switch phase {
        case .questions, .review: if timed(s), remaining(s) <= 0 { timeUp(s) }
        case .wait: if (module(s)?.count ?? 0) > 0 { begin() }
        case .rest: if restEnds <= now { begin() }
        case .over: break
        }
    }

    private func timeUp(_ s: PracticeSet) {
        leave()
        guard s.full else { practice.update(id) { $0.done = true }; return }
        breakAfter = practice.lock(id)
        phase = .over
    }

    /// Starts the clock on what is on screen; a full test records a visit, as the tracker does for Bluebook.
    private func show() {
        let t = Date(); shownAt = t; now = t
        guard phase == .questions, let s = practice.set(id), s.full, let mod = module(s), mod.range.contains(i) else { return }
        practice.update(id) { $0.visits = ($0.visits ?? []) + [Visit(section: mod.section, module: mod.number, number: i - mod.first + 1, start: t)] }
    }

    /// Adds the time on screen to the question and the module clock, and closes the visit.
    private func leave() {
        let t = Date(), e = t.timeIntervalSince(shownAt), ph = phase, k = i
        practice.update(id) { s in
            guard !s.done else { return }
            if ph == .questions, s.work.indices.contains(k) { s.work[k].seconds += e }
            if ph == .questions || ph == .review, let m = s.stage, s.modules?.indices.contains(m) == true { s.modules![m].used += e }
            if let v = s.visits?.indices.last, s.visits![v].end == nil { s.visits![v].end = t }
        }
        shownAt = t; now = t
    }

    private func go(_ k: Int) {
        guard let s = practice.set(id), s.questions.indices.contains(k) else { return }
        leave(); i = k; phase = .questions; show()
    }

    private func next(_ s: PracticeSet) {
        if phase == .review { submitting = true; return }   // asked first, as in Bluebook
        let r = range(s)
        guard let p = r.firstIndex(of: i) else { return }
        if p + 1 < r.count { go(r[p + 1]) }
        else { leave(); phase = .review; show() }   // the last Next opens Check Your Work for practice questions too
    }

    private func back(_ s: PracticeSet) {
        let r = range(s)
        if phase == .review { go(r.last ?? i) } else if let p = r.firstIndex(of: i), p > 0 { go(r[p - 1]) }
    }

    private func afterModule() {
        guard practice.set(id)?.done == false else { return }
        if breakAfter { restEnds = Date() + 600; now = Date(); phase = .rest } else { begin() }
    }

    private func finish() { leave(); practice.update(id) { $0.done = true } }

    /// Everything back to zero, on screen too: the first question (of Module 1), clock, tools and warnings.
    private func restart() {
        practice.restart(id)
        i = -1; phase = .questions; calc = false; highlighting = false; crossing = false; navigator = false
        hidden = false; toastGone = false; breakAfter = false
        if let s = practice.set(id) { resume(s) }
    }

    private func heading(_ s: PracticeSet, _ sec: String) -> String {
        guard let mod = module(s) else { return "Practice Questions: \(sec)" }
        return "Section \((s.sections.firstIndex(of: sec) ?? 0) + 1), Module \(mod.number): \(sec)"
    }

    private func section(_ s: PracticeSet) -> String {
        module(s)?.section ?? (s.questions.indices.contains(i) ? s.questions[i].section : Practice.rw)
    }

    // MARK: Bars

    private func top(_ s: PracticeSet) -> some View {
        let sec = section(s), left = remaining(s), warn = timed(s) && left < 300 && phase != .over
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading(s, sec)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Button { directions.toggle() } label: {
                    HStack(spacing: 4) { Text("Directions"); Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
                }
                .buttonStyle(.plain).font(.system(size: 14))
                .popover(isPresented: $directions, arrowEdge: .bottom) { directionsText(sec) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 5) {
                if timed(s), phase != .over, phase != .wait {
                    if hidden && !warn { Image(systemName: "clock").font(.system(size: 20)).frame(height: 26) }
                    else { Text(Fmt.clock(left)).font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(warn ? BB.red : BB.ink) }
                    if !warn { Button(hidden ? "Show" : "Hide") { hidden.toggle() }.buttonStyle(BBOutline()).fixedSize() }
                }
            }
            .overlay(alignment: .trailing) { if warn && !toastGone { toast.frame(width: 0, alignment: .leading).offset(x: 14) } }   // beside the timer, clear of the question
            HStack(spacing: 18) {
                if sec == Sec.math, phase == .questions {
                    tool("Calculator", "plus.forwardslash.minus", on: calc) { calc.toggle() }
                    tool("Reference", "textformat.superscript", on: reference) { reference.toggle() }
                        .popover(isPresented: $reference, arrowEdge: .bottom) { referenceSheet }
                }
                if sec != Sec.math, phase == .questions {
                    tool("Highlights & Notes", "pencil", "note.text", on: highlighting) { highlighting.toggle() }
                }
                tool("More", "ellipsis", on: more, turn: true) { more.toggle() }
                    .overlay(alignment: .topTrailing) {
                        if more {   // Bluebook's menu: a white card under the button, one row per action
                            VStack(alignment: .leading, spacing: 0) {
                                MenuRow(title: "Save and Exit", icon: "rectangle.portrait.and.arrow.right") { more = false; if practice.mayLeave({}) { leave(); practice.open = nil } }
                                if !s.full { MenuRow(title: "Finish and See Results", icon: "flag.checkered") { more = false; finish() } }
                                Divider().padding(.vertical, 4)
                                MenuRow(title: "Restart", icon: "arrow.counterclockwise") { more = false; restarting = true }
                            }
                            .padding(6).frame(width: 250)
                            .background(BB.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BB.ink.opacity(0.15)))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                            .offset(y: 58).fixedSize()
                            .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: more)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24).frame(height: 76)
        .background(BB.bar)
        .zIndex(1)
    }

    /// Bluebook's modal: a card over the dimmed test, buttons along the bottom.
    private func dialog<B: View>(_ title: String, _ text: String, @ViewBuilder _ buttons: () -> B) -> some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 22, weight: .semibold))
                Text(text).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) { buttons() }.padding(.top, 6)
            }
            .padding(24).frame(width: 560)
            .background(BB.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 3)
        }
    }

    private var toast: some View {
        HStack(spacing: 8) {
            Text("5 Minutes Left").font(.system(size: 13, weight: .semibold))
            Button { toastGone = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }.buttonStyle(.plain)
        }
        .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 30)
        .background(BB.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }

    private func tool(_ title: String, _ icons: String..., on: Bool, turn: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                HStack(spacing: 1) { ForEach(icons, id: \.self) { Image(systemName: $0) } }.font(.system(size: 17)).rotationEffect(.degrees(turn ? 90 : 0)).frame(height: 20)
                Text(title).font(.system(size: 12, weight: on ? .semibold : .regular)).underline(on)
            }
            .frame(minWidth: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func banner(_ full: Bool) -> some View {
        Text((full ? "This is a practice test" : "Practice questions").uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 24)
            .background(BB.navy, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    private func bottom(_ s: PracticeSet) -> some View {
        let r = range(s), p = r.firstIndex(of: i) ?? 0
        let grid = s.questions.indices.contains(i) && s.questions[i].choices.isEmpty   // arrows type in the entry box
        return ZStack {
            HStack {
                Text(PlanStore.shared.profile.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 10) {
                    Button("Back") { back(s) }.disabled(phase == .questions && p == 0)
                        .keyboardShortcut(grid ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
                    Button("Next") { next(s) }
                        .keyboardShortcut(grid ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
                }
                .buttonStyle(BBButton())
            }
            if phase == .questions {
                Button { navigator.toggle() } label: {
                    HStack(spacing: 6) { Text("Question \(p + 1) of \(r.count)"); Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)) }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 34).background(BB.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $navigator, arrowEdge: .top) { navigatorView(s) }
            }
        }
        .padding(.horizontal, 24).frame(height: 64)
        .background(BB.bar)
    }

    // MARK: Question

    @ViewBuilder private func content(_ s: PracticeSet, _ q: PracticeQuestion) -> some View {
        GeometryReader { g in
            if q.section == Sec.math {
                HStack(spacing: 0) {
                    if calc { calculatorPanel(g.size.width).padding(12).padding(.top, 32) }   // below the practice banner
                    ScrollView { questionPane(s, q).padding(.top, 20).frame(width: calc ? nil : max(520, g.size.width * 0.45)).frame(maxWidth: .infinity) }
                        .frame(maxWidth: .infinity)
                }
                .coordinateSpace(.named("math"))
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        passage(q.passage)
                            .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 32).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: g.size.width * split)
                    divider(g.size.width)
                    ScrollView { questionPane(s, q).padding(.top, 20) }
                }
                .coordinateSpace(.named("split"))
            }
        }
    }

    /// The R&W passage: text the student can highlight, and tables drawn as `PassageText` draws them.
    private func passage(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkedText.groups(text), id: \.base) { g in
                if g.table { PassageText(text: g.text, size: 17, ink: BB.ink).textSelection(.enabled) }
                else { MarkedText(text: g.text, base: g.base, marks: marks(i), on: highlighting, color: $hue) }
            }
        }
    }

    private func marks(_ k: Int) -> Binding<[PracticeSet.Mark]> {
        Binding(get: { practice.set(id)?.work[k].highlights ?? [] },
                set: { v in practice.update(id) { $0.work[k].highlights = v.isEmpty ? nil : v } })
    }

    /// The bar between passage and question; drag its handle to resize the panes.
    private func divider(_ w: CGFloat) -> some View {
        Rectangle().fill(BB.ink).frame(width: 2)
            .overlay {
                HStack(spacing: 3) { Image(systemName: "arrowtriangle.left.fill"); Image(systemName: "arrowtriangle.right.fill") }
                    .font(.system(size: 6)).foregroundStyle(.white)
                    .frame(width: 26, height: 18).background(BB.ink, in: Capsule())
            }
            .contentShape(Rectangle().inset(by: -8))
            .gesture(DragGesture(coordinateSpace: .named("split")).onChanged { split = min(0.75, max(0.25, $0.location.x / max(w, 1))) })
            .pointerStyle(.columnResize)
    }

    /// Desmos beside the question, as Bluebook opens it: a title bar, wider with the expand button, resizable by its right edge.
    private func calculatorPanel(_ w: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Graphing").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).frame(height: 26)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer()
                Image(systemName: "circle.grid.3x3.fill").font(.system(size: 10)).opacity(0.7)
                Spacer()
                Button { wide.toggle() } label: { Image(systemName: wide ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain)
                Button { calc = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 40).background(BB.hex(0x2B2B2B))
            Practice.calculator([])   // empty: the graph must not give the answer away
        }
        .frame(width: wide ? w * 0.62 : min(calcWidth, w * 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(BB.border))
        .overlay(alignment: .trailing) {
            Color.clear.frame(width: 10).contentShape(Rectangle())
                .gesture(DragGesture(coordinateSpace: .named("math")).onChanged { wide = false; calcWidth = max(300, min(w * 0.7, $0.location.x - 12)) })
                .pointerStyle(.columnResize)
        }
    }

    private func questionPane(_ s: PracticeSet, _ q: PracticeQuestion) -> some View {
        let w = s.work[i], r = range(s), n = (r.firstIndex(of: i) ?? 0) + 1
        return VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("\(n)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(BB.ink)
                    Button { practice.update(id) { $0.work[i].marked.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: w.marked ? "bookmark.fill" : "bookmark").foregroundStyle(w.marked ? BB.red : BB.ink)
                            Text("Mark for Review")
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 14))
                    Spacer()
                    if !q.choices.isEmpty {
                        Button { crossing.toggle() } label: {
                            Text("ABC").strikethrough().font(.system(size: 11, weight: .bold)).foregroundStyle(crossing ? .white : BB.blue)
                                .frame(width: 36, height: 24)
                                .background(crossing ? BB.blue : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(BB.blue, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain).help("Cross out choices")
                    }
                }
                .padding(.trailing, 8).background(BB.band)
                Dashes(width: 2.5)
            }
            if q.section == Sec.math, !q.passage.isEmpty { PassageText(text: q.passage, size: 16, ink: BB.ink) }
            if q.section == Sec.math { Practice.serif(q.question, size: 16, ink: BB.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
            else { MarkedText(text: q.question, base: MarkedText.stem, size: 16, spacing: 4, marks: marks(i), on: highlighting, color: $hue) }
            if q.choices.isEmpty { gridIn(w) }
            else { ForEach(Array(zip(Practice.letters, q.choices)), id: \.0) { letter, text in choice(q, letter, text, w) } }
            if !s.full { check(q, w) }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
    }

    /// A choice row as in Bluebook: circled letter and text in a rounded box; the cross-out control beside it while ABC is on.
    /// Checked practice questions show the key in green and a wrong pick in red.
    private func choice(_ q: PracticeQuestion, _ letter: String, _ text: String, _ w: PracticeSet.Work) -> some View {
        let on = w.answer == letter, out = w.crossed.contains(letter), locked = w.checked == true
        let result: Color? = locked ? (letter == q.correct ? Palette.right : on ? Palette.wrong : nil) : nil
        let tint = result ?? (on ? BB.blue : nil)
        return HStack(spacing: 10) {
            Button {
                guard !locked else { return }   // not disabled: a checked question keeps its full contrast
                practice.update(id) { $0.work[i].answer = letter; $0.work[i].crossed.removeAll { $0 == letter } }
                practice.speculate(id)
            } label: {
                HStack(spacing: 14) {
                    Text(letter).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint == nil ? BB.ink : .white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(tint ?? .clear))
                        .overlay(Circle().strokeBorder(tint ?? BB.ink, lineWidth: 1.5))
                    Practice.serif(text, size: 16, ink: BB.ink).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(BB.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint ?? BB.border, lineWidth: tint == nil ? 1 : 2.5))
                .overlay { if out { Rectangle().fill(BB.ink).frame(height: 1.5).padding(.horizontal, 4) } }
                .opacity(out ? 0.5 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if crossing, !locked {
                Button {
                    practice.update(id) { s in
                        if out { s.work[i].crossed.removeAll { $0 == letter } }
                        else { s.work[i].crossed.append(letter); if s.work[i].answer == letter { s.work[i].answer = nil } }
                    }
                } label: {
                    Group {
                        if out { Text("Undo").underline().font(.system(size: 13, weight: .semibold)) }
                        else { Text(letter).strikethrough().font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24).overlay(Circle().strokeBorder(BB.ink, lineWidth: 1)) }
                    }
                    .frame(width: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The entry box for a student-produced response: up to 5 characters (6 with a minus sign), with Bluebook's preview.
    private func gridIn(_ w: PracticeSet.Work) -> some View {
        let a = w.answer ?? ""
        let shown = a.contains("/") ? a.split(separator: "/", maxSplits: 1).map(String.init) : []
        return VStack(alignment: .leading, spacing: 12) {
            TextField("", text: Binding(get: { a }, set: { v in
                let t = String(v.filter { "0123456789./-".contains($0) }.prefix(v.hasPrefix("-") ? 6 : 5))
                practice.update(id) { $0.work[i].answer = t.isEmpty ? nil : t }
                practice.speculate(id)
            }))
            .textFieldStyle(.plain).font(.system(size: 22, weight: .semibold)).foregroundStyle(BB.ink)
            .padding(.horizontal, 12).frame(width: 180, height: 46)
            .background(BB.page)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(BB.ink, lineWidth: 1.5))
            .disabled(w.checked == true)
            HStack(spacing: 8) {
                Text("Answer Preview:").font(.system(size: 14))
                if !a.isEmpty { Practice.serif(shown.count == 2 ? "$\\frac{\(shown[0])}{\(shown[1])}$" : "$\(a)$", size: 18, ink: BB.ink) }
            }
        }
    }

    private func chat(_ w: PracticeSet.Work) -> some View {
        let n = i
        return ChatBubble(lines: w.chat ?? [], busy: practice.chatting.contains("\(id)/\(n)"), ready: true,
                          greeting: "Ask me anything about this question.", placeholder: "Ask anything") { q in
            Task { await practice.ask(id, n, q) }
        }
    }

    /// Practice questions: Check, then right or wrong and the explanation.
    @ViewBuilder private func check(_ q: PracticeQuestion, _ w: PracticeSet.Work) -> some View {
        if w.checked == true {
            let ok = Session.same(w.answer, q.correct)
            let key = q.correct.components(separatedBy: ",").first ?? q.correct
            HStack(spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? Palette.right : Palette.wrong)
                Text(ok ? "Correct" : w.answer == nil ? "No answer" : "Incorrect").font(.system(size: 16, weight: .bold))
                if !ok { Text("Answer: \(key)").font(.system(size: 15)) }
            }
            .padding(.top, 4)
            PracticeExplain(q: q, w: w, ink: BB.ink)
        } else {
            Button("Check") { practice.update(id) { $0.work[i].checked = true } }
                .buttonStyle(BBButton()).disabled(w.answer == nil)
        }
    }

    // MARK: Navigator and review page

    private var legend: some View {
        HStack(spacing: 20) {
            Label("Current", systemImage: "mappin")
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(BB.blue, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).frame(width: 16, height: 16)
                Text("Unanswered")
            }
            Label { Text("For Review") } icon: { Image(systemName: "bookmark.fill").foregroundStyle(BB.red) }
        }
        .font(.system(size: 13))
    }

    private func squares(_ s: PracticeSet, current: Int?, _ action: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 14), count: 10), alignment: .leading, spacing: 18) {
            ForEach(Array(range(s).enumerated()), id: \.element) { n, k in
                let answered = s.work[k].answer != nil
                Button { action(k) } label: {
                    Text("\(n + 1)").font(.system(size: 15, weight: .bold)).foregroundStyle(answered ? .white : BB.blue)
                        .frame(width: 40, height: 40)
                        .background(answered ? BB.blue : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(BB.blue, style: StrokeStyle(lineWidth: 1.2, dash: answered ? [] : [3, 2])))
                        .overlay(alignment: .topTrailing) {
                            if s.work[k].marked { Image(systemName: "bookmark.fill").font(.system(size: 12)).foregroundStyle(BB.red).offset(x: 5, y: -6) }
                        }
                        .overlay(alignment: .top) { if k == current { Image(systemName: "mappin").font(.system(size: 13)).foregroundStyle(BB.ink).offset(y: -16) } }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func navigatorView(_ s: PracticeSet) -> some View {
        VStack(spacing: 14) {
            Text("\(heading(s, section(s))) Questions").font(.system(size: 15, weight: .semibold))
            Dashes()
            legend
            Dashes()
            squares(s, current: i) { k in navigator = false; go(k) }.padding(.top, 8)
            if s.full {
                Button("Go to Review Page") { navigator = false; leave(); phase = .review; show() }.buttonStyle(BBOutline(size: 14))
            }
        }
        .foregroundStyle(BB.ink).padding(20).frame(width: 560)
        .background(BB.page).environment(\.colorScheme, .light)
    }

    private func review(_ s: PracticeSet) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Check Your Work").font(.system(size: 30, weight: .semibold))
                if s.full {   // module wording only fits a full test
                    VStack(spacing: 4) {
                        Text("On test day, you won't be able to move on to the next module until time expires.")
                        Text("For this practice test, you can select Next when you're ready to move on.")
                    }
                    .font(.system(size: 15))
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("\(heading(s, section(s))) Questions").font(.system(size: 17, weight: .semibold)); Spacer(); legend }
                    Dashes()
                    squares(s, current: nil) { k in go(k) }.padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24).frame(maxWidth: 760)
                .background(BB.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 2)
            }
            .padding(.top, 56).padding(.bottom, 32).frame(maxWidth: .infinity)
        }
    }

    // MARK: Between modules

    private var over: some View {
        VStack(spacing: 14) {
            Text("This Module Is Over").font(.system(size: 30, weight: .semibold))
            Text("All your work has been saved.\nYou'll move on automatically in just a moment.").font(.system(size: 15)).multilineTextAlignment(.center)
            ProgressView().controlSize(.small).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { try? await Task.sleep(for: .seconds(3)); afterModule() }
    }

    private var rest: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Remaining Break Time:").font(.system(size: 17))
                    Text(Fmt.clock(restEnds.timeIntervalSince(now))).font(.system(size: 56, weight: .bold)).monospacedDigit()
                }
                .padding(.horizontal, 36).padding(.vertical, 24)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.6)))
                Button { begin() } label: {
                    Text("Resume Testing").font(.system(size: 15, weight: .bold)).foregroundStyle(BB.ink)
                        .padding(.horizontal, 24).frame(height: 38).background(BB.hex(0xFEDB00), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Practice Test Break").font(.system(size: 26, weight: .semibold))
                Text("You can resume this practice test as soon as you're ready to move on. On test day, you'll wait until the clock counts down.")
                Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
                Text("Take a Break: Do Not Close Your Device").font(.system(size: 17, weight: .semibold))
                Text("After the break, a Resume Testing button will appear and you'll start the next section.")
                Text("Follow these rules during the break:").fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Do not disturb students who are still testing.")
                    Text("2. Do not exit the app or close your laptop.")
                    Text("3. Do not access phones, smartwatches, textbooks, notes, or the internet.")
                    Text("4. Do not eat or drink near any testing device.")
                }
            }
            .font(.system(size: 14)).frame(maxWidth: 440, alignment: .leading)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BB.ink)
    }

    private func wait(_ s: PracticeSet) -> some View {
        let row = practice.rows(id).first { $0.id == "\(s.stage ?? 0)" }
        return VStack(spacing: 14) {
            Text("Preparing \(heading(s, section(s)))").font(.system(size: 24, weight: .semibold))
            ProgressView(value: Double(row?.ready ?? 0), total: Double(max(1, row?.of ?? 1))).tint(BB.blue).frame(width: 340)
            Text("\(row?.ready ?? 0) of \(row?.of ?? 0) questions ready").font(.system(size: 14)).monospacedDigit()
            if let row, let e = row.error {
                Text(e).font(.system(size: 13)).foregroundStyle(BB.red).multilineTextAlignment(.center).frame(maxWidth: 420)
                Button("Retry") { practice.retry(id, row.parts) }.buttonStyle(BBButton())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Directions and reference

    private func directionsText(_ sec: String) -> some View {
        let text = sec == Sec.math ? [
            "The questions in this section address a number of important math skills. Use of a calculator is permitted for all questions. A reference sheet, calculator, and these directions can be accessed throughout the test.",
            "Unless otherwise indicated: all variables and expressions represent real numbers; figures provided are drawn to scale; all figures lie in a plane; the domain of a given function f is the set of all real numbers x for which f(x) is a real number.",
            "For multiple-choice questions, solve each problem and choose the correct answer from the choices provided. Each multiple-choice question has a single correct answer.",
            "For student-produced response questions: if you find more than one correct answer, enter only one answer. You can enter up to 5 characters for a positive answer and up to 6 characters (including the negative sign) for a negative answer. If your answer is a fraction that doesn't fit, enter the decimal equivalent; if a decimal doesn't fit, truncate or round at the fourth digit. Enter a mixed number as an improper fraction. Don't enter symbols such as a percent sign, comma, or dollar sign.",
        ] : [
            "The questions in this section address a number of important reading and writing skills. Each question includes one or more passages, which may include a table or graph. Read each passage and question carefully, and then choose the best answer to the question based on the passage(s).",
            "All questions in this section are multiple-choice with four answer choices. Each question has a single best answer.",
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) { ForEach(text, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) } }
                .font(.system(size: 14)).padding(20)
        }
        .frame(width: 520).frame(maxHeight: 420)
        .foregroundStyle(BB.ink).background(BB.page).environment(\.colorScheme, .light)
    }

    private var referenceSheet: some View {
        let facts = [
            "Circle: $A = \\pi r^2$, $C = 2\\pi r$", "Rectangle: $A = \\ell w$", "Triangle: $A = \\frac{1}{2}bh$",
            "Pythagorean theorem: $c^2 = a^2 + b^2$",
            "Special right triangles: $30°$-$60°$-$90°$ with sides $x$, $x\\sqrt{3}$, $2x$; $45°$-$45°$-$90°$ with sides $s$, $s$, $s\\sqrt{2}$",
            "Rectangular prism: $V = \\ell wh$", "Cylinder: $V = \\pi r^2 h$", "Sphere: $V = \\frac{4}{3}\\pi r^3$",
            "Cone: $V = \\frac{1}{3}\\pi r^2 h$", "Pyramid: $V = \\frac{1}{3}\\ell wh$",
            "The number of degrees of arc in a circle is 360.", "The number of radians of arc in a circle is $2\\pi$.",
            "The sum of the measures in degrees of the angles of a triangle is 180.",
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Reference").font(.system(size: 17, weight: .semibold))
            ForEach(facts, id: \.self) { Practice.serif($0, size: 15, ink: BB.ink).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(20).frame(width: 460)
        .foregroundStyle(BB.ink).background(BB.page).environment(\.colorScheme, .light)
    }
}

/// Closing the window with a full test on screen asks first, like leaving the page.
extension AppDelegate {
    @objc func windowShouldClose(_ w: NSWindow) -> Bool { MainActor.assumeIsolated { Store.shared.nav != .practice || Practice.shared.mayLeave { w.close() } } }
}

// MARK: - Highlights & Notes

extension PracticeSet.Mark {
    var end: Int { start + length }

    /// A new highlight takes in the ones it overlaps, in its color, keeping their notes; one inside a highlight changes nothing.
    static func add(_ m: Self, to marks: [Self]) -> [Self] {
        guard m.length > 0, !marks.contains(where: { $0.start <= m.start && m.end <= $0.end }) else { return marks }
        let hit = marks.filter { $0.start < m.end && m.start < $0.end }
        var out = m
        out.start = min(m.start, hit.map(\.start).min() ?? m.start)
        out.length = max(m.end, hit.map(\.end).max() ?? m.end) - out.start
        out.note = (hit.map(\.note) + [m.note]).filter { !$0.isEmpty }.joined(separator: "\n")
        return (marks.filter { !hit.contains($0) } + [out]).sorted { $0.start < $1.start }
    }
}

/// Passage or question text set like `Practice.serif` in a native text view the student can select and highlight.
/// Marks count characters across the whole question: this text covers `base` to `base` + its length.
struct MarkedText: NSViewRepresentable {
    static let stem = 100_000        // question marks sit past any passage
    let text: String
    var base = 0
    var size: CGFloat = 17
    var spacing: CGFloat = 6
    @Binding var marks: [PracticeSet.Mark]
    var on: Bool                     // highlight mode: a finished selection becomes a highlight
    @Binding var color: String

    /// Pieces with <u>…</u> on the odd ones. shortcut: $math$ shows as plain text; R&W passages rarely have any.
    static func pieces(_ s: String) -> [String] {
        s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "</u>", with: "<u>").components(separatedBy: "<u>")
    }
    static func length(_ s: String) -> Int { pieces(s).map { ($0 as NSString).length }.reduce(0, +) }

    /// The passage in `PassageText`'s groups of lines, each with where its marks start.
    static func groups(_ passage: String) -> [(table: Bool, text: String, base: Int)] {
        var base = 0
        return passage.components(separatedBy: "\n").reduce(into: [(table: Bool, lines: [String])]()) { g, l in
            let t = l.contains(" | ")
            if let last = g.last, last.table == t { g[g.count - 1].lines.append(l) } else { g.append((t, [l])) }
        }.map { g in
            let text = g.lines.joined(separator: "\n")
            defer { base += length(text) + 1 }
            return (g.table, text, base)
        }
    }

    func attributed() -> NSAttributedString {
        let p = NSMutableParagraphStyle(); p.lineSpacing = spacing
        let font = NSFont(name: "STIXTwoText", size: size) ?? .systemFont(ofSize: size)
        let a = NSMutableAttributedString()
        for (j, t) in Self.pieces(text).enumerated() {
            a.append(NSAttributedString(string: t, attributes: [.font: font, .foregroundColor: NSColor(BB.ink), .paragraphStyle: p,
                                                                 .underlineStyle: j % 2 == 1 ? NSUnderlineStyle.single.rawValue : 0]))
        }
        for m in marks {
            let lo = max(0, m.start - base), hi = min(a.length, m.end - base)
            guard hi > lo else { continue }
            let r = NSRange(location: lo, length: hi - lo)
            a.addAttribute(MarkView.fill, value: NSColor(BB.mark(m.color)), range: r)
            if !m.note.isEmpty {   // a dotted underline marks a note; hovering shows it
                a.addAttributes([.underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue, .underlineColor: NSColor(BB.ink), .toolTip: m.note], range: r)
            }
        }
        return a
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MarkView {
        let v = MarkView(usingTextLayoutManager: false)
        v.isEditable = false; v.isSelectable = true; v.drawsBackground = false
        v.isVerticallyResizable = false; v.isHorizontallyResizable = false
        v.textContainerInset = .zero; v.textContainer?.lineFragmentPadding = 0
        v.appearance = NSAppearance(named: .aqua)
        v.owner = context.coordinator
        v.gap = spacing
        return v
    }

    func updateNSView(_ v: MarkView, context: Context) {
        context.coordinator.parent = self
        let a = attributed()
        if v.textStorage?.isEqual(to: a) != true { let sel = v.selectedRanges; v.textStorage?.setAttributedString(a); v.selectedRanges = sel }
    }

    func sizeThatFits(_ p: ProposedViewSize, nsView v: MarkView, context: Context) -> CGSize? {
        let w = p.width.flatMap { $0.isFinite ? $0 : nil } ?? 600
        return CGSize(width: w, height: v.fit(w))
    }

    final class Coordinator {
        var parent: MarkedText
        let popover = NSPopover()
        init(_ p: MarkedText) { parent = p }

        /// After a click or drag: in highlight mode a selection becomes a highlight; a click on a highlight opens its editor.
        func ended(_ v: MarkView, at hit: Int?) {
            let p = parent, r = v.selectedRange()
            if r.length > 0 {
                guard p.on else { return }
                p.marks = PracticeSet.Mark.add(.init(start: p.base + r.location, length: r.length, color: p.color), to: p.marks)
                v.setSelectedRange(NSRange(location: r.location, length: 0))
            } else if let hit, let m = p.marks.first(where: { $0.start <= p.base + hit && p.base + hit < $0.end }) {
                edit(m, in: v)
            }
        }

        private func edit(_ m: PracticeSet.Mark, in v: MarkView) {
            let lo = max(0, m.start - parent.base), r = NSRange(location: lo, length: min(v.string.utf16.count, m.end - parent.base) - lo)
            let rect = v.anchor(r)
            guard !rect.isEmpty else { return }
            popover.behavior = .transient
            popover.appearance = NSAppearance(named: .aqua)
            popover.contentViewController = NSHostingController(rootView: MarkEditor(mark: m) { [weak self] in self?.set(m.start, $0) })
            popover.show(relativeTo: rect, of: v, preferredEdge: .maxY)   // the view is flipped: maxY is under the words
        }

        /// Saves an edited highlight, or deletes it (nil).
        private func set(_ start: Int, _ new: PracticeSet.Mark?) {
            var all = parent.marks
            guard let k = all.firstIndex(where: { $0.start == start }) else { return }
            if let new { all[k] = new; parent.color = new.color } else { all.remove(at: k); popover.close() }
            parent.marks = all
        }
    }
}

final class MarkView: NSTextView {
    static let fill = NSAttributedString.Key("markFill")
    weak var owner: MarkedText.Coordinator?
    var gap: CGFloat = 0             // the line spacing, left out of the highlight

    /// ← and → are Back and Next in the test, as in Bluebook: they go up the chain instead of moving a text cursor.
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 123 || e.keyCode == 124 { window?.makeFirstResponder(nil); nextResponder?.keyDown(with: e) } else { super.keyDown(with: e) }
    }

    /// The height the text needs at width `w`. SwiftUI may measure at several widths; the layout goes back to the view's own
    /// width after, or drawing and the note's popover would use the last measured one (the popover then landed far below).
    func fit(_ w: CGFloat) -> CGFloat {
        guard let tc = textContainer, let lm = layoutManager else { return 0 }
        tc.size = NSSize(width: w, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let h = ceil(lm.usedRect(for: tc).height)
        if bounds.width > 0, bounds.width != w { tc.size = NSSize(width: bounds.width, height: .greatestFiniteMagnitude) }
        return h
    }

    /// Each line of a character range as a highlight covers it, in view coordinates: around the words only, without the
    /// line spacing below.
    func boxes(_ r: NSRange) -> [NSRect] {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage else { return [] }
        let str = ts.string as NSString
        let marked = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        var out: [NSRect] = []
        lm.enumerateLineFragments(forGlyphRange: marked) { _, _, _, line, _ in
            var cr = lm.characterRange(forGlyphRange: NSIntersectionRange(line, marked), actualGlyphRange: nil)
            while cr.length > 0, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(str.character(at: NSMaxRange(cr) - 1)) ?? " ") { cr.length -= 1 }
            guard cr.length > 0 else { return }
            var box = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: cr, actualCharacterRange: nil), in: tc)
            box.size.height -= self.gap
            out.append(box.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
        }
        return out
    }

    /// Where a highlight's popover points: the highlighted words, laid out at the view's own width.
    func anchor(_ r: NSRange) -> NSRect {
        if bounds.width > 0, textContainer?.size.width != bounds.width { _ = fit(bounds.width) }
        return boxes(r).reduce(NSRect.null) { $0.union($1) }
    }

    /// Highlights drawn line by line around the words only; a background color attribute would run to the margin at a wrap.
    override func draw(_ dirty: NSRect) {
        if let ts = textStorage {
            ts.enumerateAttribute(Self.fill, in: NSRange(location: 0, length: ts.length)) { v, r, _ in
                guard let c = v as? NSColor else { return }
                c.setFill()
                boxes(r).forEach { $0.fill() }
            }
        }
        super.draw(dirty)
    }

    override func mouseDown(with e: NSEvent) {
        let hit = index(at: convert(e.locationInWindow, from: nil))
        super.mouseDown(with: e)   // tracks the drag until the mouse is up
        owner?.ended(self, at: hit)
    }

    /// The character under the point, if the point is on one.
    private func index(at p: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 else { return nil }
        let q = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let g = lm.glyphIndex(for: q, in: tc)
        guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).contains(q) else { return nil }
        return lm.characterIndexForGlyph(at: g)
    }
}

/// The toolbar on a highlight: its color, a note, Delete.
struct MarkEditor: View {
    @State var mark: PracticeSet.Mark
    let save: (PracticeSet.Mark?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(BB.marks, id: \.0) { name, color in
                    Button { mark.color = name; save(mark) } label: {
                        Circle().fill(color).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(mark.color == name ? BB.ink : BB.border.opacity(0.6), lineWidth: mark.color == name ? 2 : 1))
                    }
                    .buttonStyle(.plain).help(name.capitalized).accessibilityLabel(name.capitalized)
                }
                Spacer()
                Button { save(nil) } label: { Label("Delete", systemImage: "trash") }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
            }
            TextField("Add a note", text: $mark.note, axis: .vertical).lineLimit(1...5)
                .textFieldStyle(.plain).font(.system(size: 14))
                .padding(8).overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(BB.border))
                .onChange(of: mark.note) { save(mark) }
        }
        .padding(14).frame(width: 280)
        .foregroundStyle(BB.ink).background(BB.page).environment(\.colorScheme, .light)
    }
}


/// One row of the Bluebook More menu: icon, label, a soft highlight on hover.
private struct MenuRow: View {
    let title: String, icon: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14)).foregroundStyle(BB.ink)
            .padding(.horizontal, 10).frame(height: 34)
            .background(hover ? BB.blue.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}
