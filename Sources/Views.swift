import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// One spacing value per surface; every inner corner = outer radius − inset (concentric).
/// Same values as MONEY! and Moneybag: inset 16, card radius 26 (the macOS 26 window corner), inner 10.
enum L {
    static let inset: CGFloat = 16
    static let radius: CGFloat = 26
    static let inner: CGFloat = radius - inset          // 10: anything drawn inside a card
    static let gap: CGFloat = 16                        // between cards
}

/// The type scale. Numbers use SF Pro Rounded (like Fitness); words use SF Pro.
enum T {
    static let hero = Font.system(size: 64, weight: .bold, design: .rounded)       // the one number a screen is about
    static let big = Font.system(size: 34, weight: .bold, design: .rounded)        // secondary numbers on a hero card
    static let value = Font.system(size: 28, weight: .bold, design: .rounded)      // stat tiles
    static let title = Font.system(size: 28, weight: .bold)                        // onboarding titles (setup-assistant style)
    static let section = Font.system(size: 20, weight: .semibold)                  // headline sentences, page sections
    static let card = Font.system(size: 13, weight: .semibold)                     // card titles
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
}

/// Floating timer metrics, scaled by the Size setting (Small 0.85, Medium 1, Large 1.25).
struct Bar {
    let scale: CGFloat
    var height: CGFloat { 36 * scale }
    var pad: CGFloat { height * 0.4 }                   // capsule ends look even with the text
    static let margin: CGFloat = 16
    /// Big enough for the hovered pill; transparent parts let clicks through.
    var window: CGSize { CGSize(width: 480 * scale + Bar.margin * 2, height: height + Bar.margin * 2) }
    static let sizes: [(name: String, scale: Double)] = [("Small", 0.85), ("Medium", 1), ("Large", 1.25)]
}

enum Palette {
    static let right = Color(red: 0x0c / 255, green: 0xa3 / 255, blue: 0x0c / 255)
    static let wrong = Color(red: 0xd0 / 255, green: 0x3b / 255, blue: 0x3b / 255)
    static let unknown = Color.gray.opacity(0.55)
}

/// Segmented control on Liquid Glass: equal widths, concentric corners, the selection slides.
struct Segments<T: Hashable>: View {
    let items: [(String, T)]
    @Binding var value: T
    var height: CGFloat = 32
    var radius: CGFloat = 10
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.1) { item in
                Button { withAnimation(.smooth(duration: 0.25)) { value = item.1 } } label: {
                    Text(item.0)
                        .font(.system(size: 13, weight: value == item.1 ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if value == item.1 {
                                RoundedRectangle(cornerRadius: radius - 2, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "selection", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(height: height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Gentle grow + highlight on hover, used by every clickable row, tile and card.
struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.02
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hover ? scale : 1)
            .brightness(hover ? 0.02 : 0)
            .onHover { h in withAnimation(.smooth(duration: 0.2)) { hover = h } }
    }
}

extension View {
    func hoverLift(_ scale: CGFloat = 1.02) -> some View { modifier(HoverLift(scale: scale)) }

    func card() -> some View {
        padding(L.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }
}

// MARK: - Floating timer

/// Display only: where you are and for how long. Hover grows it to show the test; click opens the
/// menu bar controls; drag to move. The window is a fixed size so the pill can animate inside it.
struct BarView: View {
    @ObservedObject var t = Tracker.shared
    @AppStorage("barSize") private var size = 1.0
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    var body: some View {
        let bar = Bar(scale: size)
        HStack(spacing: 0) {
            pill(bar)
            Spacer(minLength: 0)
        }
        .frame(width: bar.window.width, height: bar.window.height, alignment: .leading)
    }

    private func pill(_ bar: Bar) -> some View {
        HStack(spacing: 8 * bar.scale) {
            Image(systemName: Tracker.stateIcon)
                .font(.system(size: 12 * bar.scale, weight: .semibold))
                .foregroundStyle(t.paused ? Color.secondary : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
            Text(t.number.map { "Q\($0)" } ?? (t.paused ? "Paused" : "Review"))
                .font(.system(size: 14 * bar.scale, weight: .semibold))
                .contentTransition(.numericText())
            if t.number != nil {
                Text(Fmt.clock(t.questionTime))
                    .font(.system(size: 14 * bar.scale, weight: .medium))
                    .foregroundStyle(t.questionTime > (t.session?.pace ?? .infinity) ? Palette.wrong : Color.primary)
                    .contentTransition(.numericText(countsDown: false))
            }
            if hover {
                Divider().frame(height: 14 * bar.scale)
                    .transition(.opacity)
                Text("\(t.session?.test ?? TestChoice.current.name) · M\(t.module) · \(Fmt.clock(t.elapsed))")
                    .font(.system(size: 12 * bar.scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: false))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            if t.guessed || t.flagged {
                Image(systemName: t.flagged ? "flag.fill" : "questionmark")
                    .font(.system(size: 11 * bar.scale, weight: .bold)).foregroundStyle(Color.accentColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .monospacedDigit()
        .padding(.horizontal, bar.pad)
        .frame(height: bar.height)
        .background(WindowDragArea { MenuBar.shared.show() })
        .glassEffect(.regular.tint(scheme == .dark ? .black.opacity(0.25) : .white.opacity(0.45)).interactive(), in: Capsule())
        .scaleEffect(hover ? 1.04 : 1, anchor: .leading)
        .shadow(color: .black.opacity(hover ? 0.24 : 0.16), radius: hover ? 14 : 10, y: hover ? 5 : 3)
        .padding(Bar.margin)                // room for the shadow inside the transparent window
        .fixedSize()
        .onHover { h in withAnimation(.smooth(duration: 0.28)) { hover = h } }
        .animation(.smooth(duration: 0.3), value: t.number)
        .animation(.smooth(duration: 0.3), value: t.paused)
        .animation(.smooth(duration: 0.3), value: t.guessed || t.flagged)
        .animation(.smooth(duration: 0.3), value: Int(t.elapsed))
    }
}

/// Drag the window from anywhere; a click that doesn't move it calls `onClick`.
struct WindowDragArea: NSViewRepresentable {
    var onClick: () -> Void = {}
    final class V: NSView {
        var onClick: () -> Void = {}
        override func mouseDown(with e: NSEvent) {
            let before = window?.frame.origin
            window?.performDrag(with: e)
            if window?.frame.origin == before { onClick() }
        }
        override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onClick = onClick; return v }
    func updateNSView(_ v: V, context: Context) { v.onClick = onClick }
}

/// Which practice test this is. Remembered between launches.
struct TestChoice {
    static let bluebook = (4...11).map { "SAT Practice \($0)" }   // the full-length tests in Bluebook (essays left out)

    @MainActor static var current: (name: String, short: String) {
        let name = PlanStore.shared.trackChoice(UserDefaults.standard.string(forKey: "test") ?? bluebook[0])
        return (name, name.replacingOccurrences(of: "SAT ", with: ""))
    }
}

/// Test picker used by the bar and the menu bar.
struct TestMenu<Content: View>: View {
    let onOther: () -> Void
    @ViewBuilder let label: Content
    @AppStorage("test") private var test = TestChoice.bluebook[0]

    var body: some View {
        Menu {
            ForEach(TestChoice.bluebook, id: \.self) { n in
                Button { test = n } label: { if n == test { Label(n, systemImage: "checkmark") } else { Text(n) } }
            }
            Divider()
            Button("Other practice…", action: onOther)
        } label: { label }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

struct SessionRow: View {
    let s: Session
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(s.start.formatted(date: .abbreviated, time: .omitted))\(s.sections.count == 1 ? " · " + Sec.short(s.sections[0]) : "")\(s.logged ? " · logged" : "")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let n = s.scoreNote { Text(n).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }
}

func resultName(_ c: Bool?) -> String { c == true ? "Right" : c == false ? "Wrong" : "Not marked" }

/// Where a result comes from: College Board, the student, or an AI estimate.
struct GradeTag: View {
    let grade: Grade
    var body: some View {
        Label(grade.rawValue, systemImage: grade == .official ? "checkmark.seal.fill" : grade == .mine ? "person.fill" : "sparkles")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).frame(height: 22)
            .background(Palette.well, in: Capsule())
            .foregroundStyle(grade == .official ? Color.accentColor : .secondary)
    }
}

struct ResultBadge: View {
    let c: Bool?
    var mine = false   // the student marked it; shown so they know their mark is the one counting
    var body: some View {
        HStack(spacing: 4) {
            Label(resultName(c), systemImage: c == true ? "checkmark.circle.fill" : c == false ? "xmark.circle.fill" : "circle.dashed")
            if mine { Image(systemName: "person.fill").font(.system(size: 9)).help("Your mark") }
        }
        .foregroundStyle(c == true ? Palette.right : c == false ? Palette.wrong : .secondary)
        .font(.system(size: 12, weight: .medium))
    }
}

// MARK: - One question

/// The student's note on a question. Saved a moment after typing stops, so each key press doesn't rewrite the test file.
struct MemoField: View {
    let sid: String, key: String
    @ObservedObject var store = Store.shared
    @State private var text = ""
    @State private var save: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "note.text").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Notes", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13.5)).lineLimit(2...8)
        }
        .padding(L.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        .onAppear { text = store.session(sid)?.q[key]?.memo ?? "" }
        .onChange(of: text) { _, t in
            save?.cancel()
            save = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { write(t) } }
        }
        .onDisappear { save?.cancel(); write(text) }
    }

    private func write(_ t: String) {
        let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (store.session(sid)?.q[key]?.memo ?? "") != v else { return }
        store.update(sid) { $0.q[key, default: QState()].memo = v.isEmpty ? nil : v }
    }
}

/// One question: the screen as you left it, then the answer, what went wrong and how to solve it.
/// ‹ › or ← → move between questions; the chat button in the corner opens a conversation about this one.
struct QuestionView: View {
    let sid: String
    let close: () -> Void
    @State private var key: String
    @ObservedObject var store = Store.shared
    @FocusState private var focused: Bool
    @State private var allSteps = false
    @State private var bigShot: NSImage?
    @AppStorage("showDesmos") private var showDesmos = true   // the Desmos panel beside Math questions   // the screenshot shown full size

    @Binding var filter: QFilter   // the test page's filter, shared: arrows and swipes step through what it shows
    let scope: String

    init(sid: String, start: String, filter: Binding<QFilter> = .constant(QFilter()), scope: String = "Overview", close: @escaping () -> Void) {
        self.sid = sid; self.close = close; _filter = filter; self.scope = scope; _key = State(initialValue: start)
    }

    var body: some View {
        // A logged test has no visits: its questions open from the key alone (no screenshot or time, but the result,
        // a picture the student adds, notes and reasons all work).
        if let full = store.session(sid), let v = full.visits.last(where: { $0.key == key })
            ?? (full.keys.contains(key) ? Visit(section: Session.section(of: key), module: Session.parts(key).1, number: Session.parts(key).2, start: full.start, end: full.start) : nil) {
            let s = full.only(v.section)
            let all = full.keys   // sorts every visit: once per render, not per question
            let shown = filter.order(full, scope)
            let order = shown.flatMap { $0.contains(key) ? $0 : nil } ?? all   // a question outside the filter steps through all
            let st = s.q[key] ?? QState()
            VStack(spacing: L.inset) {
                header(s, st, v, order)
                HStack(alignment: .top, spacing: L.gap) {
                    VStack(spacing: L.gap) {
                        // Bluebook's layout: Desmos on the left of the question when it helps (Math only).
                        if showDesmos, let ex = st.analysis?.desmos, !ex.isEmpty, Session.section(of: key) == Sec.math {
                            HStack(spacing: L.gap) {
                                DesmosView(expressions: ex, focus: st.analysis?.desmosFocus)
                                    .clipShape(RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                screenshot(s).frame(maxWidth: .infinity)
                            }
                        } else {
                            screenshot(s)
                        }
                        strip(full, all, order)   // always at the bottom, whatever the screenshot's height
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    ScrollView {
                        VStack(alignment: .leading, spacing: L.gap) {
                            if let a = st.analysis, let k = a.keyPoint, !k.isEmpty {   // new format: key point, then why it failed
                                keyPoint(k)
                                if s.correct(key) == false { whyWrong(a) }
                            } else if let a = st.analysis, s.correct(key) == false { wentWrong(a) }   // older explanations
                            else if st.analysis == nil, s.correct(key) == false { whyMissed }   // not explained yet: the reasons still count
                            explanation(s, st).frame(maxWidth: .infinity, alignment: .leading).padding(L.inset)
                                .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                            MemoField(sid: sid, key: key).id(key)
                        }
                    }
                    .scrollIndicators(.never)
                    .padding(.bottom, 40 + L.gap)   // the chat button sits in the corner: nothing scrolls under it
                    .frame(width: 380)
                }
            }
            .padding(L.inset)
            .overlay(alignment: .bottomTrailing) { QuestionChat(sid: sid, key: key).padding(L.inset).environment(\.openURL, QLink.action(in: sid)) }
            .overlay {
                if let img = bigShot {
                    Image(nsImage: img).resizable().scaledToFit().allowedDynamicRange(.standard)
                        .clipShape(RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                        .padding(L.inset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Palette.surface)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.smooth(duration: 0.2)) { bigShot = nil } }
                        .transition(.opacity)
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onSwipe(left: { _ = move(order, 1) }, right: { _ = move(order, -1) })
            .onKeyPress(.leftArrow) { move(order, -1) }
            .onKeyPress(.rightArrow) { move(order, 1) }
            .onChange(of: key) { allSteps = false; bigShot = nil }
            .onChange(of: filter) {   // the open question left the filter: go to the first one it shows
                if let o = store.session(sid).flatMap({ filter.order($0, scope) }), !o.contains(key), let k = o.first { withAnimation(.smooth(duration: 0.2)) { key = k } }
            }
        }
    }

    private func move(_ order: [String], _ d: Int) -> KeyPress.Result {
        guard let i = order.firstIndex(of: key), order.indices.contains(i + d) else { return .ignored }
        withAnimation(.smooth(duration: 0.2)) { key = order[i + d] }
        return .handled
    }

    /// Question number and result first and largest; position, section and topic under them; tools on the right.
    private func header(_ s: Session, _ st: QState, _ v: Visit, _ order: [String]) -> some View {
        let i = order.firstIndex(of: key) ?? 0
        let t = s.seconds(key)
        let c = s.correct(key)
        let o = s.official?.answers[key]
        // A result-only record has no letters: show Right/Wrong, and no "You chose" when the student's pick isn't known.
        let answers: (String, String?)? = st.analysis.map { ($0.correctAnswer, $0.studentAnswer) }
            ?? o.flatMap { $0.correct.isEmpty ? nil : ($0.correct, $0.yours ?? ($0.right == nil ? "none" : nil)) }
        let level = st.analysis?.difficulty ?? o?.difficulty ?? ""
        let skill = st.analysis?.skill ?? o?.skill ?? "", domain = st.analysis?.topic ?? o?.domain ?? ""
        let tint = Sec.color(v.section)
        return HStack(spacing: L.gap) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    round("chevron.left") { _ = move(order, -1) }.disabled(i == 0)
                    round("chevron.right") { _ = move(order, 1) }.disabled(i == order.count - 1)
                }
                Text("\(i + 1) of \(order.count)").font(T.caption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: L.gap * 2, verticalSpacing: 2) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("Question \(v.number)").font(T.title).lineLimit(1)
                    result(answers, c)
                }
                GridRow(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Label { Text("\(Text(Sec.name(v.section)).foregroundStyle(tint)) · Module \(v.module)") } icon: { Image(systemName: Sec.icon(v.section)).foregroundStyle(tint) }.lineLimit(1)
                        if !level.isEmpty { DifficultyBars(level: level) }
                    }
                    Text("\(Text(skill))\(Text(!skill.isEmpty && !domain.isEmpty ? " · " : ""))\(Text(domain).foregroundStyle(tint))").lineLimit(1)
                }
                .font(T.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if st.analysis?.desmos?.isEmpty == false, Session.section(of: key) == Sec.math {
                        Toggle(isOn: $showDesmos) { Label("Desmos", systemImage: "chart.xyaxis.line").labelStyle(.titleAndIcon) }
                            .toggleStyle(.button).help(showDesmos ? "Hide Desmos" : "Show Desmos")
                    }
                    Menu {
                        Button("Paste Image", systemImage: "doc.on.clipboard") { pasteImage() }
                            .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSImage.self]))
                        Button("Choose Image…", systemImage: "photo.on.rectangle") { chooseImage() }
                    } label: { Label("Image", systemImage: "photo.badge.arrow.down").labelStyle(.iconOnly) }
                        .menuStyle(.button).fixedSize()
                        .help("Replace the screenshot with your own picture of this question")
                    Menu {
                        ForEach([("Auto", Bool?.none), ("Right", true), ("Wrong", false)], id: \.0) { name, m in
                            Button { Tutor.mark(sid, key, m) } label: { if st.mark == m { Label(name, systemImage: "checkmark") } else { Text(name) } }
                        }
                    } label: { Label("Mark", systemImage: "checkmark.circle").labelStyle(.iconOnly) }
                        .menuStyle(.button).fixedSize()
                        .help("Mark right or wrong yourself")
                    round("xmark") { close() }.keyboardShortcut(.cancelAction)
                }
                HStack(spacing: 10) {
                    if let g = s.grade(key) { GradeTag(grade: g) }
                    if !s.logged {   // a logged test has no times
                        Label { Text("\(Text(Fmt.clock(t)).foregroundStyle(t > s.pace ? Palette.wrong : .primary).fontWeight(.semibold)) of \(Fmt.clock(s.pace))") } icon: { Image(systemName: "clock") }
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
            }
        }
        .font(.system(size: 13)).monospacedDigit()
    }

    /// "Correct C  You chose A (C and D crossed out)": the letters in large type and in their colors.
    @ViewBuilder private func result(_ answers: (String, String?)?, _ c: Bool?) -> some View {
        if let answers {
            let right = Self.choice(answers.0), mine = answers.1.map(Self.choice)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if c == true {   // a right answer needs only a check and the one letter
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.right)
                        .help("Correct").accessibilityLabel("Correct")
                } else {
                    Text("Correct").foregroundStyle(.secondary)
                }
                Text(right.0).font(T.big).foregroundStyle(Palette.right)
                if let n = right.1 { Text(n).font(T.caption).foregroundStyle(.secondary) }
                if c != true, let mine {
                    Text("You chose").foregroundStyle(.secondary).padding(.leading, L.inner)
                    Text(mine.0).font(T.big).foregroundStyle(c == false ? Palette.wrong : .secondary)
                    if let n = mine.1 { Text(n).font(T.caption).foregroundStyle(.secondary).layoutPriority(-1) }
                }
            }
            .font(.system(size: 15, weight: .medium)).lineLimit(1)
        } else {
            Text(c == nil ? "Not graded" : resultName(c)).font(T.value)
                .foregroundStyle(c == true ? Palette.right : c == false ? Palette.wrong : .secondary)
        }
    }

    /// "A (C and D crossed out)" → ("A", "C and D crossed out"); "none", "unanswered" and blanks → "—".
    static func choice(_ answer: String) -> (String, String?) {
        let t = answer.trimmingCharacters(in: .whitespaces)
        let r = t.range(of: " (")
        let main = r.map { String(t[..<$0.lowerBound]) } ?? t
        let note = r.map { String(t[$0.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ")")) }
        return (["", "none", "unanswered", "unclear", "omitted"].contains(main.lowercased()) ? "—" : main, note)
    }

    private func round(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// This module as a row of bars (height = time, color = result, dashed line = pace); the open question is lifted.
    /// Questions outside the timeline filter fade. Click a bar to jump.
    private func strip(_ full: Session, _ all: [String], _ order: [String]) -> some View {
        let mod = String(key.split(separator: "-").first ?? "")
        let ks = all.filter { $0.hasPrefix(mod + "-") }
        let sec = full.only(Session.section(of: key))
        let secs = Dictionary(uniqueKeysWithValues: ks.map { ($0, full.seconds($0)) })
        let shown = Set(order)
        let top = max(secs.values.max() ?? 1, sec.pace * 1.2, 1)
        let h: CGFloat = full.logged ? 28 : 72   // a logged test has no times: equal blocks in result colors
        return VStack(alignment: .leading, spacing: 10) {
            FilterBar(f: $filter, s: scope == "Overview" ? full : full.only(scope), scope: scope)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(ks, id: \.self) { k in
                    let on = shown.contains(k), cur = k == key, t = secs[k] ?? 0
                    Button { withAnimation(.smooth(duration: 0.2)) { key = k } } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Palette.fill(full.correct(k)))
                                .frame(height: full.logged ? h : max(4, h * CGFloat(t / top)))
                                .frame(height: h, alignment: .bottom)
                            Text(k.split(separator: "-").last.map(String.init) ?? "")
                                .font(.system(size: 10, weight: cur ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(cur ? Color.primary : Color.secondary)
                        }
                        .padding(.horizontal, 2).padding(.vertical, 4)
                        .background(cur ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(on ? 1 : 0.18).disabled(!on)
                    .help("Q\(k.split(separator: "-").last ?? "")\(full.logged ? "" : " · " + Fmt.clock(t))")
                }
            }
            .overlay(alignment: .bottom) {   // pace line, measured from the bars' baseline (number row is ~19 pt)
                if !full.logged { Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 4000, y: 0)) }
                    .stroke(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 1).clipped()
                    .padding(.bottom, 19 + 4 + h * CGFloat(sec.pace / top))
                    .allowsHitTesting(false) }
            }
        }
        .padding(L.inset)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    /// Cropped to the printed question and as wide as the column, so the text is as large as it can be.
    /// A wrong or missing picture can be replaced (pasted, chosen, or dropped), e.g. with the same question from Khan Academy.
    @ViewBuilder private func screenshot(_ s: Session) -> some View {
        let shape = RoundedRectangle(cornerRadius: L.inner, style: .continuous)
        Group {
            if let p = s.shot(key), !p.contains("_figure_") {   // a pasted graph goes inside the official card instead
                let url = store.dir(sid).appendingPathComponent(p)
                // a well the width of the column, as tall as the picture's aspect allows
                let pane = s.pane(p)
                ZoomedShot(url: url, box: s.q[key]?.highlight, radius: 4, pane: pane)
                    .aspectRatio(ZoomedShot.aspect(url, pane: pane), contentMode: .fit)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)   // the well fills the column down to the timeline; the picture sits centred in it
                    .background(Palette.well, in: shape)
                    .contentShape(shape)
                    .onTapGesture { withAnimation(.smooth(duration: 0.2)) { bigShot = ZoomedShot.image(url) } }
                    .pointerStyle(.zoomIn)
            } else if let a = s.official?.answers[key], a.question != nil {   // a logged test: College Board's text, set like Bluebook
                // Result-only record: the tutor's solved answer (and the student's pick) fill in the letters.
                let ai = s.q[key]?.analysis
                let filled = { () -> Official.Answer in
                    var b = a
                    if b.correct.isEmpty { b.correct = ai?.correctAnswer ?? "" }
                    if b.yours == nil, let y = ai?.studentAnswer, y.lowercased() != "none" { b.yours = y }   // the wrong pick shows in red too
                    return b
                }()
                OfficialCard(a: .constant(filled), key: key, right: s.correct(key),
                             picture: s.q[key]?.image.flatMap { $0.contains("_figure_") ? ZoomedShot.image(store.dir(sid).appendingPathComponent($0)) : nil })
            } else {
                ContentUnavailableView("No screenshot", systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.well, in: shape)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let img = urls.lazy.compactMap(NSImage.init(contentsOf:)).first else { return false }
            Tutor.replaceImage(sid, key, img); return true
        }
    }

    private func pasteImage() {
        if let img = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage { Tutor.replaceImage(sid, key, img) }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let u = panel.url, let img = NSImage(contentsOf: u) { Tutor.replaceImage(sid, key, img) }
    }

    /// The one idea to remember, first and largest, for every question.
    private func keyPoint(_ k: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "key.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.yellow)
            Rich.text(k, size: 17, weight: .semibold, color: .primary).textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    /// Wrong answers (new format): why the choice fails, the cause, and one habit for next time.
    private func whyWrong(_ a: Analysis) -> some View {
        let mine = a.studentAnswer.split(separator: " ").first.map(String.init) ?? ""
        let title = mine.isEmpty || ["none", "unanswered", "unclear"].contains(mine.lowercased()) ? "Why you missed it" : "Why \(mine) doesn't work"
        return VStack(alignment: .leading, spacing: 8) {
            header(title, "xmark.octagon.fill", Palette.wrong)
            if !a.trapJa.isEmpty { Rich.text(a.trapJa, color: .primary) }
            causePicker(a.mistakeCause)
            if let c = a.coachLine, !c.isEmpty {
                Text("\(Text("Next time").fontWeight(.semibold).foregroundStyle(.primary)) \(Rich.text(c, color: .primary))").padding(.top, 2)
            }
        }
        .font(.system(size: 13.5)).textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wrong.opacity(0.1), in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    /// Why it was missed, one tap: the student's pick is solid; the tutor's guess is dashed with the AI sparkle until then.
    private func causePicker(_ guess: String?) -> some View {
        let st = store.session(sid)?.q[key] ?? QState()
        let sec = Session.section(of: key)
        let picked = st.reasons
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Cause.all.map(\.id).filter { sec == Sec.math ? $0 != "grammar" : $0 != "calculation" }, id: \.self) { id in
                if let c = Cause.of(id, section: sec) {
                    let on = picked.contains(id), hint = picked.isEmpty && guess == id
                    Button {   // several reasons can be true at once: each tap adds or removes one
                        store.update(sid) { s in
                            var r = s.q[key, default: QState()].reasons
                            if on { r.removeAll { $0 == id } } else { r.append(id) }
                            s.q[key]!.causes = r.isEmpty ? nil : r
                            s.q[key]!.cause = nil
                        }
                    } label: {
                        Label(c.name, systemImage: hint ? "sparkles" : c.icon).font(.system(size: 11.5, weight: on ? .semibold : .regular)).lineLimit(1)
                            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                            .foregroundStyle(on ? Color.white : hint ? Palette.wrong : Color.secondary)
                            .background(on ? Palette.wrong : hint ? Color.clear : Color.primary.opacity(0.06), in: Capsule())
                            .overlay { if hint { Capsule().strokeBorder(Palette.wrong.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) } }
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Your reason" : hint ? "Your tutor's guess. Tap to confirm or pick another." : "")
                }
            }
        }
    }

    /// A wrong question with no explanation yet: the student's reasons only.
    private var whyMissed: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Why you missed it", "xmark.octagon.fill", Palette.wrong)
            causePicker(nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wrong.opacity(0.1), in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    @ViewBuilder private func wentWrong(_ a: Analysis) -> some View {
        if let line = a.coachLine ?? (a.trapJa.isEmpty ? nil : a.trapJa) {
            VStack(alignment: .leading, spacing: 8) {
                header("What went wrong", "exclamationmark.triangle.fill", Palette.wrong)
                if let cause = Cause.of(a.mistakeCause, section: Session.section(of: key)) { Label(cause.name, systemImage: cause.icon).font(.system(size: 13, weight: .semibold)) }
                Rich.text(line, color: .primary)
                if a.coachLine != nil, !a.trapJa.isEmpty { Rich.text(a.trapJa).lineLimit(4) }
            }
            .font(.system(size: 13.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.wrong.opacity(0.1), in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    @ViewBuilder private func explanation(_ s: Session, _ st: QState) -> some View {
        let busy = store.busy.contains("\(sid)/\(key)")
        let c = s.correct(key)
        VStack(alignment: .leading, spacing: 24) {
            if let a = st.analysis {
                if busy { HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Explaining again…") }.font(.system(size: 12)).foregroundStyle(.secondary) }
                part("Solution", "lightbulb.fill", .orange) {
                    let steps = Self.steps(a.solutionJa)
                    VStack(alignment: .leading, spacing: 10) {
                        lines((allSteps ? steps : Array(steps.prefix(3))).joined(separator: "\n"))
                        if steps.count > 3 {
                            Button(allSteps ? "Show fewer steps" : "Show all steps") { withAnimation(.smooth(duration: 0.25)) { allSteps.toggle() } }
                                .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
                        }
                    }
                }
                if !a.wordingJa.isEmpty { part("Reading the question", "text.magnifyingglass", .blue) { lines(a.wordingJa) } }
                if c != false || a.keyPoint != nil && c != false, !a.trapJa.isEmpty { part("Watch out", "exclamationmark.triangle.fill", .orange) { lines(a.trapJa) } }
                // The AI's "Time" note is left out: its numbers can disagree with the tracker's time in the header.
                let words = a.vocab.filter { $0.en.trimmingCharacters(in: .whitespaces).count > 1 }
                if !words.isEmpty {
                    part("Words", "character.book.closed.fill", .purple) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                            ForEach(words, id: \.self) { w in
                                GridRow {
                                    Text(w.term).fontWeight(.semibold).foregroundStyle(.primary)
                                    Text(w.note).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if busy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Explaining…") }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let e = st.error { Text(e).foregroundStyle(Palette.wrong).font(.system(size: 12)) }
                    Button { Task { await Tutor.analyze(sid, key) } } label: { Label("Explain", systemImage: "sparkles") }
                        .disabled(!Brain.ready || !s.explainable(key))
                }
            }
        }
    }

    /// One row per line; "1. …" lines become numbered steps.
    /// Steps, one per line, even when the tutor ran them together ("1. … 2. … 3. …").
    static func steps(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.!?][\"”’']?)\s+(?=\d{1,2}[.)]\s)"#, with: "\n", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func lines(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.steps(text).joined(separator: "\n").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, l in
                let n = l.prefix(while: \.isNumber)
                let rest = l.dropFirst(n.count)
                if !n.isEmpty, let mark = rest.first, ".)".contains(mark) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(n).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
                        Rich.text(rest.dropFirst().trimmingCharacters(in: .whitespaces))
                    }
                } else {
                    Rich.text(l)
                }
            }
        }
    }

    private func header(_ title: String, _ icon: String, _ tint: Color) -> some View {
        Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(tint) }
            .font(.system(size: 15, weight: .semibold))
    }

    private func part<C: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title, icon, tint)
            content().font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct VocabView: View {
    @ObservedObject var store = Store.shared
    @State private var search = ""
    @State private var mine = false

    struct Row: Identifiable { let id: String; let v: Vocab; let count: Int }

    /// Words from your tests (with how often they came up) plus the built-in SAT math glossary.
    var rows: [Row] {
        var seen: [String: (Vocab, Int)] = [:]
        for s in store.sessions { for st in s.q.values { for v in st.analysis?.vocab ?? [] {
            let k = v.en.lowercased()
            seen[k] = (seen[k]?.0 ?? v, (seen[k]?.1 ?? 0) + 1)
        } } }
        if !mine { for v in Glossary.all where seen[v.en.lowercased()] == nil { seen[v.en.lowercased()] = (v, 0) } }
        return seen.map { Row(id: $0.key, v: $0.value.0, count: $0.value.1) }
            .filter { CardStore.isTerm($0.v) }
            .filter { search.isEmpty || "\($0.v.en) \($0.v.ja) \($0.v.note)".localizedCaseInsensitiveContains(search) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    var body: some View {
        let rows = self.rows   // scans every explanation: build once per render
        VStack(alignment: .leading, spacing: L.gap) {
            PageTitle(title: "Words", subtitle: "\(rows.count)")
            HStack(spacing: L.gap) {
                Segments(items: [("All", false), ("From my tests", true)], value: $mine).frame(width: 280)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).frame(width: 260, height: 32)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            }
            Panel {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(r.v.term).font(.system(size: 14, weight: .semibold))
                                    if !r.v.ja.isEmpty {
                                        Text(r.v.ja).font(T.caption).foregroundStyle(.secondary).lineLimit(1)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Palette.well, in: Capsule())
                                    }
                                }
                                Text(r.v.note.sentenceCase).font(T.body).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(L.inset)
    }
}

/// Two-finger trackpad swipes (left/right), like paging in Safari. Ignores mice and mostly-vertical scrolls.
struct Swipe: ViewModifier {
    var enabled = true
    let left: () -> Void, right: () -> Void   // left = fingers move left (next), right = fingers move right (back)
    @State private var box = Box()

    /// The event monitor outlives renders, so it reads the latest settings from here.
    final class Box {
        var enabled = true, left: () -> Void = {}, right: () -> Void = {}
        var monitor: Any?, dx: CGFloat = 0, dy: CGFloat = 0, fired = false
    }

    func body(content: Content) -> some View {
        box.enabled = enabled; box.left = left; box.right = right
        return content
            .onAppear { install(box) }
            .onDisappear { if let m = box.monitor { NSEvent.removeMonitor(m); box.monitor = nil } }
    }

    private func install(_ b: Box) {
        guard b.monitor == nil else { return }
        b.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak b] e in
            guard let b, b.enabled, e.hasPreciseScrollingDeltas, e.window?.isKeyWindow == true else { return e }
            if e.phase == .began { b.dx = 0; b.dy = 0; b.fired = false }
            // Finger direction, whatever the natural-scrolling setting.
            let sign: CGFloat = e.isDirectionInvertedFromDevice ? 1 : -1
            if e.phase == .changed || e.phase == .began { b.dx += e.scrollingDeltaX * sign; b.dy += e.scrollingDeltaY }
            if !b.fired, abs(b.dx) > 70, abs(b.dx) > abs(b.dy) * 2 {
                b.fired = true   // one page per gesture
                if b.dx < 0 { b.left() } else { b.right() }
            }
            return e
        }
    }
}

extension View {
    func onSwipe(enabled: Bool = true, left: @escaping () -> Void, right: @escaping () -> Void) -> some View {
        modifier(Swipe(enabled: enabled, left: left, right: right))
    }
}
