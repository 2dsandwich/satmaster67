import Charts
import SwiftUI

// The review of one test. Overview (both sections) or one section; nothing scrolls the page.
// Hierarchy, from fitness apps: one hero number with a band word, contributors under it, then detail cards whose
// titles say the takeaway. A question opens by zooming out of the bar you clicked and closes back into it.

/// Names, icons and official timing per section.
enum Sec {
    static let math = "Math"
    static func name(_ s: String) -> String { s == math ? "Math" : "Reading & Writing" }
    static func short(_ s: String) -> String { s == math ? "Math" : "R&W" }
    static func icon(_ s: String) -> String { s == math ? "function" : "text.book.closed" }
    /// One color per section, used for its name and icon everywhere (and in the tutor's text).
    static func color(_ s: String) -> Color { s == math ? .cyan : .purple }
    static func limit(_ s: String) -> Double { (s == math ? 35 : 32) * 60 }   // one module, seconds
}

/// Why a question was missed: one name and icon each, everywhere.
enum Cause {
    static let all: [(id: String, name: String, icon: String)] = [
        ("misread", "Misread the question", "eye"),
        ("vocabulary", "Didn't know a word", "character.book.closed"),
        ("grammar", "Grammar rule", "textformat.abc"),
        ("calculation", "Calculation slip", "function"),
        ("concept", "Math idea", "brain"),
        ("time", "Rushed / out of time", "timer"),
        ("guess", "Guessed", "questionmark"),
    ]
    /// "concept" means a math idea in Math and the passage's logic in Reading and Writing.
    static func of(_ id: String?, section: String? = nil) -> (id: String, name: String, icon: String)? {
        guard let c = all.first(where: { $0.id == id }) else { return nil }
        return c.id == "concept" && section != nil && section != Sec.math ? (c.id, "Missed the logic", "point.topleft.down.to.point.bottomright.curvepath") : c
    }
}

/// The student's own reasons for their misses, most common first (top three), each with its Cause icon and count.
struct WhyYouMiss: View {
    let rows: [(id: String, section: String?, count: Int)]
    var compact = false   // one line, for a test's Overview

    var body: some View {
        let top = rows.prefix(3).compactMap { r in Cause.of(r.id, section: r.section).map { (c: $0, n: r.count, tint: r.section.map(Sec.color) ?? Color.secondary) } }
        if compact {
            HStack(spacing: 14) {
                Text("Why you miss").fontWeight(.semibold)
                ForEach(top, id: \.c.name) { r in
                    Label { Text("\(r.c.name) \(Text("\(r.n)").fontWeight(.bold))").monospacedDigit() } icon: { Image(systemName: r.c.icon).foregroundStyle(r.tint) }.lineLimit(1)
                }
            }
            .font(.system(size: 13))
        } else {
            VStack(spacing: 8) {
                ForEach(top, id: \.c.name) { r in
                    HStack(spacing: 10) {
                        Image(systemName: r.c.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(r.tint).frame(width: 20)
                        Text(r.c.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(r.n)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                }
            }
        }
    }
}

extension Palette {
    /// Fill for a question: wrong is solid, right is a calmer green, unknown is faint.
    static func fill(_ c: Bool?, dark: Bool = false) -> Color { c == true ? right.opacity(dark ? 0.75 : 0.55) : c == false ? wrong : Color.primary.opacity(0.18) }

    /// Oura-style band for a share right.
    static func band(_ rate: Double) -> (word: String, color: Color) {
        rate >= 0.9 ? ("Excellent", right) : rate >= 0.75 ? ("Good", right) : rate >= 0.6 ? ("Fair", .orange) : ("Needs work", wrong)
    }
}

// MARK: - One test

extension EnvironmentValues {
    /// Which tab a test review opens on (snapshots use it; the app starts on Overview).
    @Entry var reviewScope = "Overview"
    /// The timeline filter a review opens with (snapshots use it; the app starts unfiltered).
    @Entry var reviewFilter = QFilter()
}

/// Which questions the timeline shows. Non-matching bars fade, and the question view steps only through matches.
struct QFilter: Equatable {
    static let results = ["All", "Wrong", "Right", "Not graded"]
    var result = "All"
    var section: String?, module: Int?, difficulty: String?
    var topics: Set<String> = []   // any of these (empty = all topics)
    var flagged = false, guessed = false, overPace = false

    var isOn: Bool { self != QFilter() }
    /// A section tab already shows one section, so the Section filter only counts on Overview.
    func scoped(_ scope: String) -> QFilter { var f = self; if scope != "Overview" { f.section = nil }; return f }

    static func difficulty(_ s: Session, _ k: String) -> String? { s.official?.answers[k]?.difficulty ?? s.q[k]?.analysis?.difficulty }
    /// Difficulty as three bars: one filled for Easy, two for Medium, three for Hard; hovering says which.
    static func difficultyIcon(_ d: String) -> some View { DifficultyBars(level: d) }

    func match(_ s: Session, _ k: String) -> Bool {
        let c = s.correct(k), st = s.q[k]
        let res = switch result { case "Wrong": c == false; case "Right": c == true; case "Not graded": c == nil; default: true }
        return res && (section == nil || Session.section(of: k) == section) && (module == nil || Session.parts(k).1 == module)
            && (difficulty == nil || Self.difficulty(s, k) == difficulty) && (topics.isEmpty || topics.contains(s.topic(k) ?? ""))
            && (!flagged || st?.flagged == true) && (!guessed || st?.guessed == true) && (!overPace || s.seconds(k) > s.pace(k))
    }

    /// The questions a tab shows under this filter, in order; nil when nothing is filtered.
    func order(_ full: Session, _ scope: String) -> [String]? {
        let f = scoped(scope)
        guard f.isOn else { return nil }
        return (scope == "Overview" ? full : full.only(scope)).keys.filter { f.match(full, $0) }
    }
}

/// Where a test review opens: its tab, its filter and a question. nil keeps what the review already shows.
/// Set by Today, the plan and chat links through `Store.open`; SessionView takes it.
struct Opening: Equatable {
    var sid: String
    var scope: String? = nil
    var filter: QFilter? = nil
    var key: String? = nil

    /// The last finished test, on the section with the most misses, showing only the misses.
    static func review(_ sessions: [Session]) -> Opening? {
        guard let s = sessions.first(where: { $0.end != nil }) else { return nil }
        let sec = s.sections.max { a, b in s.only(a).keys.count(where: { s.correct($0) == false }) < s.only(b).keys.count(where: { s.correct($0) == false }) }
        return Opening(sid: s.id, scope: sec, filter: QFilter(result: "Wrong"))
    }

    /// The newest test with a miss in this topic (else any question in it), on its section, filtered to that topic.
    static func topic(_ name: String, _ sessions: [Session]) -> Opening? {
        let done = sessions.filter { $0.end != nil }
        let miss = done.lazy.compactMap { s in s.keys.first { s.topic($0) == name && s.correct($0) == false }.map { (s, $0, true) } }.first
        guard let (s, k, wrong) = miss ?? done.lazy.compactMap({ s in s.keys.first { s.topic($0) == name }.map { (s, $0, false) } }).first else { return nil }
        return Opening(sid: s.id, scope: Session.section(of: k), filter: QFilter(result: wrong ? "Wrong" : "All", topics: [name]))
    }

    /// A question named in a chat reply ("RW1 Q3", "M2 Q7", "Q5"): in this test, else the newest test that has it.
    static func question(_ label: String, _ sessions: [Session], in sid: String? = nil) -> Opening? {
        for s in sessions.filter({ $0.id == sid }) + sessions.filter({ $0.id != sid }) {
            if let k = s.keys.first(where: { s.label($0) == label }) { return Opening(sid: s.id, key: k) }   // the tab stays: changing it closes the question
        }
        return nil
    }
}

extension Store {
    func open(_ o: Opening) { opening = o; nav = .session(o.sid) }
}

/// Question labels in chat replies become links that open the question ("satq:RW1-Q3"); the page handles them with openURL.
@MainActor enum QLink {
    static let label = #/(?:(?:RW|M)[1-4] )?Q\d{1,2}\b/#

    /// The text cut around labels. A label inside **bold** stays bold: the bold is closed before it and opened again
    /// after it, so Rich never sees half a span.
    static func parts(_ s: String) -> [(text: String, label: Bool, bold: Bool)] {
        var out: [(text: String, label: Bool, bold: Bool)] = [], rest = Substring(s), bold = false
        func prose(_ p: Substring) {
            let opens = bold
            bold = bold != (p.ranges(of: "**").count % 2 == 1)
            let t = ((opens ? "**" : "") + p + (bold ? "**" : "")).replacingOccurrences(of: "****", with: "")   // no empty bold spans
            if !t.isEmpty { out.append((t, false, false)) }
        }
        while let m = rest.firstMatch(of: label) {
            if let c = rest[..<m.range.lowerBound].last, c.isLetter || c.isNumber { prose(rest[..<m.range.upperBound]) }   // "FAQ1" is a word
            else { prose(rest[..<m.range.lowerBound]); out.append((String(m.output), true, bold)) }
            rest = rest[m.range.upperBound...]
        }
        prose(rest)
        return out
    }

    /// Rich text with every label as a link in its section's color.
    static func text(_ s: String, size: CGFloat) -> Text {
        parts(s).reduce(Text(verbatim: "")) { out, p in
            guard p.label else { return Text("\(out)\(Rich.text(p.text, size: size, color: .primary))") }
            var a = AttributedString(p.text.replacingOccurrences(of: " ", with: "\u{00A0}"))
            a.link = URL(string: "satq:" + p.text.replacingOccurrences(of: " ", with: "-"))
            a.font = .system(size: size, weight: p.bold ? .bold : .semibold)
            a.foregroundColor = p.text.hasPrefix("M") ? Sec.color(Sec.math) : p.text.hasPrefix("RW") ? Sec.color("Reading and Writing") : .accentColor
            return Text("\(out)\(Text(a))")
        }
    }

    /// The label a link carries, or nil for any other URL.
    static func label(_ url: URL) -> String? { url.scheme == "satq" ? url.absoluteString.dropFirst(5).replacingOccurrences(of: "-", with: " ") : nil }

    /// The openURL action for a page with chat: question links open in the review, other links as usual.
    static func action(in sid: String? = nil) -> OpenURLAction {
        OpenURLAction { url in
            guard let l = label(url) else { return .systemAction }
            if let o = Opening.question(l, Store.shared.sessions, in: sid) { Store.shared.open(o) }
            return .handled
        }
    }
}

extension Session {
    /// The official pace for one question's section.
    func pace(_ key: String) -> Double { let sec = Session.section(of: key); return Sec.limit(sec) / (sec == Sec.math ? 22 : 27) }
    /// The question's domain: College Board's record first (a logged test has only that), else the tutor's.
    func topic(_ key: String) -> String? { official?.answers[key]?.domain ?? q[key]?.analysis?.topic }
    /// The official skill the question's recorded skill means (the tutor words skills its own way), else the recorded name.
    @MainActor func skill(_ key: String) -> String? {
        guard let raw = official?.answers[key]?.skill ?? q[key]?.analysis?.skill, let d = topic(key) else { return nil }
        return Practice.skill(named: raw, in: d)?.name ?? raw
    }
}

struct SessionView: View {
    let sid: String
    @ObservedObject var store = Store.shared
    @Environment(\.reviewScope) private var startScope
    @Environment(\.reviewFilter) private var startFilter
    @State private var scope: String?
    @State private var filterState: QFilter?
    @State private var focus: Focus?
    @State private var peek = false   // the student chose the dashboard over the loading screen
    @State private var shown = false
    @State private var redo = false
    @State private var importing = false
    @State private var scoring = false

    struct Focus: Equatable { var key: String; var origin: CGRect; var id = UUID() }   // origin .zero: grow from the middle

    var body: some View {
        if let full = store.session(sid) {
            let scopes = (full.sections.count > 1 ? ["Overview"] : []) + full.sections
            let want = scope ?? startScope
            let cur = scopes.contains(want) ? want : scopes.first ?? "Overview"
            let filter = Binding(get: { filterState ?? startFilter }, set: { filterState = $0 })
            let open = { (k: String, r: CGRect) in self.open(k, r) }
            Group {
                if let p = store.progress[sid], p.done < p.total, !peek {   // the review itself is written behind the dashboard
                    ExplainingView(title: full.title, p: p) { withAnimation(.smooth) { peek = true } }
                } else {
                    ZStack {
                        Group {
                            if cur == "Overview" { OverviewView(s: full, filter: filter, importing: $importing, scoring: $scoring, pick: { scope = $0 }, open: open) }
                            else { SectionView(sid: sid, section: cur, filter: filter, active: focus == nil, importing: $importing, scoring: $scoring, open: open).id(cur) }
                        }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                        .animation(.smooth(duration: 0.3), value: cur)
                        zoom(filter, cur)
                    }
                    .coordinateSpace(.named("review"))
                    .overlay(alignment: .bottom) {
                        if let p = store.progress[sid] {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text(p.done < p.total ? "Explaining question \(min(p.done + 1, p.total)) of \(p.total)" : "Writing your review")
                                    .font(.system(size: 13, weight: .medium)).monospacedDigit().contentTransition(.numericText())
                            }
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, L.gap).allowsHitTesting(false)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                        }
                    }
                    .animation(.smooth, value: store.progress[sid])
                }
            }
            .onChange(of: cur) { shown = false; focus = nil }
            .onAppear(perform: take)
            .onChange(of: store.opening) { take() }
            .onSwipe(enabled: focus == nil && store.progress[sid] == nil,   // the open question takes swipes for itself
                     left: { if let i = scopes.firstIndex(of: cur), i + 1 < scopes.count { scope = scopes[i + 1] } },
                     right: { if let i = scopes.firstIndex(of: cur), i > 0 { scope = scopes[i - 1] } })
            .task(id: sid) { await store.checkShots(sid) }   // once: find frames the navigator covers, and the Math question pane
            .navigationTitle(full.title)
            .navigationSubtitle(full.start.formatted(date: .abbreviated, time: .shortened))
            .toolbar {
                if scopes.count > 1 && store.progress[sid] == nil {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: Binding(get: { cur }, set: { scope = $0; close() })) {
                            ForEach(scopes, id: \.self) { Text($0 == "Overview" ? "Overview" : Sec.name($0)).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                }
                ToolbarItem {
                    Menu {
                        Button("Add Official Answers…", systemImage: "checkmark.seal") { importing = true }
                        Button(full.official?.total == nil ? "Enter SAT Score…" : "Edit SAT Score…", systemImage: "number") { scoring = true }
                        Menu("Test") {
                            ForEach(TestChoice.bluebook, id: \.self) { n in
                                Button { store.update(sid) { $0.test = n } } label: { if n == full.test { Label(n, systemImage: "checkmark") } else { Text(n) } }
                            }
                        }
                        Button("Rewrite All Explanations…", systemImage: "arrow.clockwise") { redo = true }.disabled(!Brain.ready)
                        Divider()
                        Button("Export CSV") { Export.csv(full) }
                        Button("Show Raw Data") { NSWorkspace.shared.open(store.dir(sid)) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { store.delete(sid) }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $importing) { ImportView(sid: sid) }
            .sheet(isPresented: $scoring) { ScoreSheet(sid: sid) }
            .confirmationDialog("Rewrite every explanation for this test?", isPresented: $redo) {
                Button("Rewrite") { Task { await Tutor.redo(sid) } }
            } message: { Text("Your tutor writes new explanations and reviews for every question. Your marks, notes and official answers stay.") }
        }
    }

    private func open(_ key: String, _ origin: CGRect) {
        focus = Focus(key: key, origin: origin)
        shown = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { shown = true }
    }

    /// What Today, the plan or a chat link asked for: a tab, a filter, a question (an open question just changes).
    private func take() {
        guard let o = store.opening, o.sid == sid else { return }
        store.opening = nil
        if let sc = o.scope { scope = sc }
        if let f = o.filter { filterState = f }
        guard let k = o.key else { return }
        if let f = focus { focus = Focus(key: k, origin: f.origin) } else { open(k, .zero) }
    }

    private func close() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { shown = false }
        Task { try? await Task.sleep(for: .milliseconds(330)); if !shown { focus = nil } }
    }

    /// The question grows out of where it was clicked: scale and position spring from that spot to the full panel.
    @ViewBuilder private func zoom(_ filter: Binding<QFilter>, _ scope: String) -> some View {
        if let f = focus {
            GeometryReader { g in
                let inset = CGSize(width: 40, height: 28)   // a margin of the page stays visible around the question
                let full = CGRect(x: inset.width, y: inset.height, width: g.size.width - inset.width * 2, height: g.size.height - inset.height * 2)
                let o = f.origin == .zero ? CGRect(x: full.midX - 30, y: full.midY - 30, width: 60, height: 60) : f.origin
                let s = shown ? 1 : max(0.04, min(o.width / full.width, o.height / full.height) * 2)
                let c = shown ? CGPoint(x: full.midX, y: full.midY) : CGPoint(x: o.midX, y: o.midY)
                ZStack {
                    Color.black.opacity(shown ? 0.4 : 0).onTapGesture { close() }
                    QuestionView(sid: sid, start: f.key, filter: filter, scope: scope, close: close).id(f.id)
                        .frame(width: full.width, height: full.height)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                        .scaleEffect(s)
                        .opacity(shown ? 1 : 0)
                        .position(c)
                }
            }
        }
    }
}

/// The whole test page while the tutor explains it: one determinate bar with a specific label.
struct ExplainingView: View {
    let title: String
    let p: Store.Progress
    var dashboard: () -> Void = {}

    var body: some View {
        let writing = p.done >= p.total
        VStack(spacing: 22) {
            CoachFace(size: 84)
            VStack(spacing: 8) {
                Text(writing ? "Writing your review" : "Explaining your test").font(T.title)
                Text(title).font(.system(size: 17)).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ProgressView(value: Double(min(p.done, p.total)), total: Double(max(p.total, 1))).progressViewStyle(.linear).controlSize(.large)
                Text(writing ? "Every question is explained" : "Question \(min(p.done + 1, p.total)) of \(p.total)")
                    .font(.system(size: 17, weight: .medium)).monospacedDigit().contentTransition(.numericText())
            }
            .frame(width: 420)
            Button("Open Dashboard", action: dashboard).controlSize(.large)
        }
        .padding(L.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: p)
    }
}

// MARK: - Filters

/// Result as segments, then chips for the rest. Toggles show their names when the row has room, icons otherwise.
struct FilterBar: View {
    @Binding var f: QFilter
    let s: Session        // the questions in view
    let scope: String
    var count = true      // false when the caller shows FilterCount elsewhere
    var timeline = false  // the Time / Grid / Order switch at the end of the row
    @Namespace private var ns

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
            VStack(alignment: .leading, spacing: 8) {   // a narrow column: results on top, the chips under them
                HStack(spacing: 8) { results; Spacer(minLength: 0); if count { FilterCount(f: $f, s: s, scope: scope) }; if timeline { TimelinePicker() } }
                chips(compact: true).frame(height: 30)
            }
        }
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: 8) {
            results
            chips(compact: compact)
            Spacer(minLength: 0)
            if count { FilterCount(f: $f, s: s, scope: scope) }
            if timeline { TimelinePicker() }
        }
        .frame(height: 30)
    }

    private func chips(compact: Bool) -> some View {
        let keys = s.keys
        let diffs = Set(keys.compactMap { QFilter.difficulty(s, $0) })
        let topics = Set(keys.compactMap { s.topic($0) }).sorted()
        return HStack(spacing: 8) {
            if scope == "Overview" { menu("Section", $f.section, s.sections, Sec.short) }
            menu("Module", $f.module, s.modules) { "Module \($0)" }
            menu("Difficulty", $f.difficulty, ["Easy", "Medium", "Hard"].filter(diffs.contains) + diffs.subtracting(["Easy", "Medium", "Hard"]).sorted(), { $0 }, icon: true)
            topicMenu($f.topics, topics, compact)
            toggle("Flagged", "flag.fill", $f.flagged, compact)
            toggle("Guessed", "questionmark.circle", $f.guessed, compact)
            if !s.logged { toggle("Over pace", "tortoise.fill", $f.overPace, compact) }   // a logged test has no times
        }
    }

    /// Like Segments, but each segment hugs its word, so the gaps between All / Wrong / Right / Not graded are even.
    private var results: some View {
        HStack(spacing: 0) {
            ForEach(QFilter.results, id: \.self) { r in
                Button { withAnimation(.smooth(duration: 0.25)) { f.result = r } } label: {
                    Text(r).font(.system(size: 13, weight: f.result == r ? .semibold : .regular)).lineLimit(1)
                        .padding(.horizontal, 11).frame(maxHeight: .infinity)
                        .background { if f.result == r { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "result", in: ns) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2).frame(height: 30).fixedSize()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static func plural(_ title: String) -> String {
        switch title { case "Difficulty": "difficulties"; default: title.lowercased() + "s" }
    }

    /// Topics can be combined: each is a checkmark, and "All topics" clears them.
    private func topicMenu(_ value: Binding<Set<String>>, _ options: [String], _ compact: Bool) -> some View {
        let picked = value.wrappedValue
        return Menu {
            Button { value.wrappedValue = [] } label: { if picked.isEmpty { Label("All topics", systemImage: "checkmark") } else { Text("All topics") } }
            Divider()
            ForEach(options, id: \.self) { t in
                Toggle(t, isOn: Binding(get: { picked.contains(t) },
                                                         set: { on in if on { value.wrappedValue.insert(t) } else { value.wrappedValue.remove(t) } }))
            }
        } label: {
            chip(picked.isEmpty ? "Topic" : picked.count == 1 ? picked.first! : "\(picked.count) topics",
                 icon: nil, on: !picked.isEmpty, menu: true, width: compact ? 90 : 260)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    /// `icon`: a picked difficulty shows as bars instead of its word.
    private func menu<V: Hashable>(_ title: String, _ value: Binding<V?>, _ options: [V], _ name: @escaping (V) -> String, compact: Bool = false, icon: Bool = false) -> some View {
        Menu {
            Picker(title, selection: value) {
                Text("All \(Self.plural(title))").tag(V?.none)
                ForEach(options, id: \.self) { Text(name($0)).tag(V?.some($0)) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            if icon, let v = value.wrappedValue {
                chip(nil, icon: nil, on: true, menu: true) { QFilter.difficultyIcon(name(v)).font(.system(size: 13, weight: .semibold)) }
            } else {
                chip(value.wrappedValue.map(name) ?? title, icon: nil, on: value.wrappedValue != nil, menu: true, width: compact ? 90 : 150)
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(options.isEmpty)
    }

    private func toggle(_ title: String, _ icon: String, _ on: Binding<Bool>, _ compact: Bool) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { on.wrappedValue.toggle() } } label: { chip(compact ? nil : title, icon: icon, on: on.wrappedValue) }
            .buttonStyle(.plain).fixedSize()
            .help(title).accessibilityLabel(title).accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    private func chip(_ text: String?, icon: String?, on: Bool, menu: Bool = false, width: CGFloat = 150, @ViewBuilder glyph: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            glyph()
            if let text { Text(text).lineLimit(1).frame(maxWidth: width) }
            if menu { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6) }
        }
        .font(.system(size: 12, weight: on ? .semibold : .medium))
        .foregroundStyle(on ? Color.white : Color.primary)
        .padding(.horizontal, 11).frame(height: 30)
        .background(on ? Color.accentColor : Palette.well, in: Capsule())
        .contentShape(Capsule())
    }
}

/// How many questions the filter leaves, and a way to clear it. Empty when nothing is filtered.
struct FilterCount: View {
    @Binding var f: QFilter
    let s: Session, scope: String

    var body: some View {
        let shown = f.scoped(scope)
        if shown.isOn {
            HStack(spacing: 10) {
                Text("\(s.keys.filter { shown.match(s, $0) }.count) of \(s.keys.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                Button("Clear") { withAnimation(.smooth(duration: 0.25)) { f = QFilter() } }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
            }
            .fixedSize()
        }
    }
}

// MARK: - Overview (both sections)

/// Score and contributors on top, every question as a filterable strip, then topics, slowest questions and what to do next.
struct OverviewView: View {
    let s: Session
    @Binding var filter: QFilter
    @Binding var importing: Bool
    var scoring: Binding<Bool> = .constant(false)
    let pick: (String) -> Void
    let open: (String, CGRect) -> Void
    @ObservedObject var plan = PlanStore.shared
    @State private var hover: String?   // the strip question under the pointer, described in the Questions header
    @AppStorage("timelineStyle") private var style = "time"

    var body: some View {
        let parts = s.sections.map { s.only($0) }
        let st = Stats(parts), per = parts.map(Stats.init)
        let weakest = zip(parts, per).min { Double($0.1.right) / Double(max($0.1.marked, 1)) < Double($1.1.right) / Double(max($1.1.marked, 1)) }?.0.section
        // The same frame as the section tabs: score, sections and feedback on the left; the timelines on the right.
        HStack(alignment: .top, spacing: L.gap) {
            VStack(spacing: L.gap) {
                    Panel {
                        ScoreRing(official: s.official?.total, outOf: 1600, right: st.right, marked: st.marked) {
                            if s.official?.total == nil { ScoreButtons(official: s.official != nil, score: false, importing: $importing, scoring: scoring) }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Panel {
                        ForEach(Array(parts.enumerated()), id: \.element.section) { i, p in
                            if i > 0 { Divider() }
                            SectionScore(s: p, st: per[i], official: s.official) { pick(p.section) }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    OverviewFeedback(s: s, open: open, pick: pick)
            }
            .frame(width: 330)
            VStack(spacing: L.gap) {
                Panel("Questions", icon: "chart.bar.xaxis") {
                    if let k = hover { QuestionLine(s: s, key: k) }
                    else if filter.isOn { FilterCount(f: $filter, s: s, scope: "Overview") }
                    else if !s.logged {
                        Text("\(Text(Fmt.clock(st.time)).foregroundStyle(st.time > st.limit ? Palette.wrong : .primary)) of \(Fmt.clock(st.limit))  ·  \(Image(systemName: "tortoise.fill")) \(st.over.count)")
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                            .help("\(st.over.count) questions over pace")
                        if style == "time" { PaceKey(text: "Pace") }
                    }
                    if !s.logged { TimelinePicker() }
                } content: {
                    FilterBar(f: $filter, s: s, scope: "Overview", count: false)
                    let slots = parts.flatMap { p in p.modules.map { p.keys($0).count } }.max() ?? 1
                    let span = parts.flatMap { p in p.modules.map { QuestionStrip.span(p, $0) } }.max() ?? 1   // one clock for every order strip
                    VStack(spacing: 8) {
                        ForEach(parts, id: \.section) { p in
                            ForEach(p.modules, id: \.self) { m in
                                QuestionStrip(s: p, module: m, slots: slots, span: span, match: { filter.match(s, $0) }, hover: $hover, open: open)
                            }
                        }
                        if style == "order" && !s.logged { MinuteAxis(total: span).padding(.leading, 54) }
                    }
                    let why = Student.reasons([s])
                    if !why.isEmpty { WhyYouMiss(rows: why, compact: true) }
                }
                TopicBars(parts: parts, stats: per).frame(height: 236)
            }
        }
        .padding(L.gap)
    }
}

/// Feedback on the whole test: per section its verdict and what went well, in the section's color. What to do next
/// lives on the section tabs. Fits its space: what went well drops first on a short window.
private struct OverviewFeedback: View {
    let s: Session
    let open: (String, CGRect) -> Void
    let pick: (String) -> Void

    var body: some View {
        let reviewed = s.sections.compactMap { sec in s.debriefs[sec].map { (sec, $0) } }
        if !reviewed.isEmpty {
            Panel {
                ViewThatFits(in: .vertical) {
                    list(reviewed, went: true)
                    list(reviewed, went: false)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func list(_ reviewed: [(String, Debrief)], went: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(reviewed, id: \.0) { sec, d in
                Button { pick(sec) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(Sec.name(sec), systemImage: Sec.icon(sec)).font(T.card).foregroundStyle(Sec.color(sec))
                        Text(d.headlineJa).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.leading)
                        if went, !d.praiseJa.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.right)
                                Rich.text(d.praiseJa, size: 13).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}



/// Minutes into the module under an order timeline: "0", "5", … "35 min"; the last label ends at the edge.
private struct MinuteAxis: View {
    let total: Double   // seconds the width spans
    var body: some View {
        GeometryReader { g in
            ForEach(Array(stride(from: 0, through: Int(total / 60), by: 5)), id: \.self) { m in
                let x = g.size.width * CGFloat(Double(m * 60) / total), edge = x + 20 > g.size.width
                Text(m + 5 > Int(total / 60) ? "\(m) min" : "\(m)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize()   // the unit once, on the last
                    .frame(width: 40, alignment: m == 0 ? .leading : edge ? .trailing : .center)
                    .offset(x: m == 0 ? x : edge ? g.size.width - 40 : x - 20)
            }
        }
        .frame(height: 12)
    }
}

/// The dashed pace line's key.
private struct PaceKey: View {
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Path { $0.move(to: CGPoint(x: 0, y: 0.5)); $0.addLine(to: CGPoint(x: 14, y: 0.5)) }
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 14, height: 1)
            Text(text)
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
    }
}

/// One question's number, result, time and topic: the line a hovered strip question shows.
private struct QuestionLine: View {
    let s: Session, key: String
    var body: some View {
        HStack(spacing: 10) {
            Text(s.label(key)).fontWeight(.bold).foregroundStyle(Sec.color(Session.section(of: key)))
            ResultBadge(c: s.correct(key), mine: s.q[key]?.mark != nil)
            if !s.logged { Label(Fmt.clock(s.seconds(key)), systemImage: "clock").foregroundStyle(s.seconds(key) > s.pace(key) ? Palette.wrong : .secondary) }
            if let d = QFilter.difficulty(s, key) { QFilter.difficultyIcon(d).foregroundStyle(.secondary) }
            if let t = s.q[key]?.analysis?.topic { Text(t).foregroundStyle(.secondary).lineLimit(1) }
        }
        .font(.system(size: 12)).monospacedDigit()
    }
}

/// One module as a strip of bars, height by time, against a dashed pace line. Bars outside the filter fade;
/// hovering one dims the rest and the Questions header describes it.
private struct QuestionStrip: View {
    let s: Session, module: Int, slots: Int
    var span: Double = 0   // seconds the order view spans; shared by the strips so one minute axis fits all
    let match: (String) -> Bool
    @Binding var hover: String?
    let open: (String, CGRect) -> Void
    @Environment(\.colorScheme) private var scheme
    @AppStorage("timelineStyle") private var style = "time"

    /// The question under the pointer; cleared a moment later, and only if no neighbour took over (no flash between rows).
    private func hovering(_ k: String?) {
        if let k { if hover != k { hover = k }; return }
        let was = hover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { if hover == was { hover = nil } }
    }

    /// A module's clock: its official time, or longer if the visits ran past it.
    static func span(_ s: Session, _ module: Int) -> Double {
        let vs = s.visits.filter { $0.module == module }
        guard let t0 = vs.map(\.start).min() else { return Sec.limit(s.section) }
        return max(Sec.limit(s.section), vs.map { ($0.end ?? $0.start).timeIntervalSince(t0) }.max() ?? 0)
    }

    private func alpha(_ k: String) -> Double { !match(k) ? 0.15 : hover == nil || hover == k ? 1 : 0.4 }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(Sec.short(s.section)) \(module)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Sec.color(s.section)).frame(width: 44, alignment: .leading)
            switch s.logged ? "grid" : style {   // a logged test has no times: tiles only
            case "grid": tiles
            case "order": sequence
            default: bars
            }
        }
        .frame(minHeight: 20)
    }

    /// Numbered tiles in result colors, one slot per question (Bluebook's navigator, as a row).
    private var tiles: some View {
        let ks = s.keys(module)
        return GeometryReader { g in
            let slot = g.size.width / CGFloat(max(slots, 1))
            HStack(spacing: 0) {
                ForEach(Array(ks.enumerated()), id: \.element) { i, k in
                    let c = s.correct(k), on = match(k)
                    Button {
                        let f = g.frame(in: .named("review"))
                        open(k, CGRect(x: f.minX + slot * CGFloat(i), y: f.minY, width: slot, height: g.size.height))
                    } label: {
                        Text("\(Session.parts(k).2)").font(.system(size: min(13, slot * 0.4), weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(c == false ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Palette.fill(c, dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .padding(.horizontal, min(2, slot * 0.08))
                            .frame(width: slot, height: g.size.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(alpha(k)).allowsHitTesting(on)
                }
            }
            .onContinuousHover { phase in
                guard case .active(let p) = phase, ks.indices.contains(Int(p.x / slot)), match(ks[Int(p.x / slot)]) else { hovering(nil); return }
                hovering(ks[Int(p.x / slot)])
            }
        }
    }

    /// The order the questions were worked, as blocks on the module's clock; returns to a question are lighter.
    private var sequence: some View {
        let vs = s.visits.filter { $0.module == module }.sorted { $0.start < $1.start }
        let t0 = vs.first?.start ?? s.start
        let total = max(span, Self.span(s, module))
        var seen = Set<String>()
        let rows: [(v: Visit, back: Bool)] = vs.map { v in defer { seen.insert(v.key) }; return (v, seen.contains(v.key)) }
        return GeometryReader { g in
            let w = g.size.width
            let blocks: [(v: Visit, back: Bool, x: CGFloat, bw: CGFloat)] = rows.map { r in
                let a = r.v.start.timeIntervalSince(t0), b = (r.v.end ?? r.v.start).timeIntervalSince(t0)
                return (r.v, r.back, w * CGFloat(a / total), max(2, w * CGFloat((b - a) / total) - 1.5))
            }
            // nearest shown block within 4 pt, so thin blocks are easy to hit and hover never drops between them
            let pick = { (x: CGFloat) in
                blocks.filter { match($0.v.key) }.min { abs($0.x + $0.bw / 2 - x) - $0.bw / 2 < abs($1.x + $1.bw / 2 - x) - $1.bw / 2 }
                    .flatMap { x >= $0.x - 4 && x <= $0.x + $0.bw + 4 ? $0 : nil }
            }
            ZStack(alignment: .topLeading) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, bl in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Palette.fill(s.correct(bl.v.key), dark: scheme == .dark))
                        .opacity(alpha(bl.v.key) * (bl.back ? 0.55 : 1))
                        .overlay {
                            if bl.bw >= 16 { Text("\(bl.v.number)").font(.system(size: 9, weight: .bold)).lineLimit(1).fixedSize()
                                .foregroundStyle(s.correct(bl.v.key) == false ? Color.white : Color.primary) }
                        }
                        .frame(width: bl.bw, height: g.size.height)
                        .offset(x: bl.x)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: g.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard case .active(let p) = phase, let b = pick(p.x) else { hovering(nil); return }
                hovering(b.v.key)
            }
            .onTapGesture { p in
                guard let b = pick(p.x) else { return }
                let f = g.frame(in: .named("review"))
                open(b.v.key, CGRect(x: f.minX + b.x, y: f.minY, width: max(b.bw, 20), height: g.size.height))
            }
        }
    }

    private var bars: some View {
        let ks = s.keys(module)
        let cap = max(1, min(3 * s.pace, ks.map { s.seconds($0) }.max() ?? 0))
        return GeometryReader { g in
                let slot = g.size.width / CGFloat(max(slots, 1))
                ZStack(alignment: .bottomLeading) {
                    Path { $0.move(to: CGPoint(x: 0, y: 0)); $0.addLine(to: CGPoint(x: slot * CGFloat(ks.count), y: 0)) }
                        .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1).offset(y: -g.size.height * min(1, s.pace / cap))
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(ks.enumerated()), id: \.element) { i, k in
                            let on = match(k), h = max(4, g.size.height * min(1, s.seconds(k) / cap))
                            Button {
                                let f = g.frame(in: .named("review"))
                                open(k, CGRect(x: f.minX + slot * CGFloat(i), y: f.maxY - h, width: slot, height: h))
                            } label: {
                                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                                    .fill(Palette.fill(s.correct(k), dark: scheme == .dark))
                                    .overlay(alignment: .top) { if s.seconds(k) > cap { BreakMark().frame(maxWidth: slot).clipped().padding(.top, 4) } }
                                    .frame(height: h).padding(.horizontal, min(2, slot * 0.14))
                                    .frame(width: slot, height: g.size.height, alignment: .bottom)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(alpha(k))
                            .allowsHitTesting(on)
                        }
                    }
                }
                .onContinuousHover { phase in
                    guard case .active(let p) = phase, ks.indices.contains(Int(p.x / slot)), match(ks[Int(p.x / slot)]) else { hovering(nil); return }
                    hovering(ks[Int(p.x / slot)])
                }
            }
    }
}

/// The five questions that took longest; click to open.
private struct Slowest: View {
    let s: Session
    let open: (String, CGRect) -> Void
    @State private var frame: CGRect = .zero
    @State private var rows: [String: CGRect] = [:]   // each row's frame, so the question grows out of the row clicked

    var body: some View {
        let top = s.keys.sorted { s.seconds($0) > s.seconds($1) }.prefix(5)
        Panel("Slowest", icon: "tortoise") {
            VStack(spacing: 4) {
                ForEach(Array(top), id: \.self) { k in
                    let c = s.correct(k)
                    Button { open(k, rows[k] ?? CGRect(x: frame.midX - 22, y: frame.midY - 22, width: 44, height: 44)) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: c == true ? "checkmark.circle.fill" : c == false ? "xmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(c == true ? Palette.right : c == false ? Palette.wrong : .secondary)
                            Text(s.label(k)).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 4)
                            Text(Fmt.clock(s.seconds(k))).font(.system(size: 14, weight: .bold, design: .rounded)).frame(width: 40, alignment: .trailing)
                        }
                        .monospacedDigit().frame(height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).hoverLift(1.02)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("review")) } action: { rows[k] = $0 }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("review")) } action: { frame = $0 }
    }
}

/// What to do next: the coach's first fix, the weakest topics (your misses here, then the Question Bank), then flashcards.
private struct NextActions: View {
    let topics: [Stats.Topic]
    var next: (fix: Debrief.Fix, section: String)? = nil   // the weaker section's first fix; opens that section's feedback
    var pick: (String) -> Void = { _ in }
    var drill: (String) -> Void = { _ in }                 // shows a topic's misses in this test
    @ObservedObject var cards = CardStore.shared

    var body: some View {
        let weak = TopicBars.order(topics).filter { $0.name != "Other" && $0.right < $0.count }.prefix(next == nil ? 2 : 1)
        let c = cards.counts, due = c.new + c.learning + c.due
        Panel("Practice next", icon: "arrow.forward.circle") {
            VStack(spacing: 6) {
                if let n = next {
                    row(Cause.of(n.fix.cause, section: n.section)?.icon ?? "lightbulb", n.fix.titleJa, nil, tint: Sec.color(n.section)) { pick(n.section) }.help(n.fix.drillJa)
                }
                ForEach(Array(weak), id: \.name) { t in
                    row("target", t.name, nil, bank: true) { drill(t.name) }
                }
                row("rectangle.on.rectangle.angled", "Flashcards", due > 0 ? "\(due) to study" : "All caught up") { Store.shared.nav = .cards }
            }
        }
    }

    /// `bank` rows end in a second button, the Question Bank in the browser, instead of the chevron.
    private func row(_ icon: String, _ title: String, _ detail: String?, bank: Bool = false, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    if !bank { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
                }
                .padding(.leading, 10).padding(.trailing, bank ? 0 : 10).frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if bank { BankButton().padding(.trailing, 4) }
        }
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        .hoverLift(1.02)
    }
}

/// The score, the same on every tab: the number large on the left, the band and count on the right, and a scale
/// across the card showing where the score sits (400–1,600 for the test, 200–800 for a section; else the share right).
struct ScoreRing<Extra: View>: View {
    let official: Int?, outOf: Int   // 1600 for the whole test, 800 for a section
    let right: Int, marked: Int
    var section: String? = nil
    @ViewBuilder var extra: Extra

    var body: some View {
        let rate = marked > 0 ? Double(right) / Double(marked) : 0
        let band = Palette.band(rate)
        let low = outOf / 4   // 400 of 1600, 200 of 800
        let fill = official.map { Double($0 - low) / Double(outOf - low) } ?? rate
        VStack(alignment: .leading, spacing: 12) {
            if let section { Label(Sec.name(section), systemImage: Sec.icon(section)).font(T.card).foregroundStyle(Sec.color(section)) }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(official.map { $0.formatted() } ?? (marked > 0 ? "\(right)" : "–"))
                    .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(official != nil ? "of \(outOf.formatted())" : "of \(marked)").font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if marked > 0 { Text(band.word).font(.system(size: 17, weight: .bold)).foregroundStyle(band.color) }
                    HStack(spacing: 5) {
                        if official != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.accentColor).help("Official score").accessibilityLabel("Official score") }
                        Text(marked == 0 ? "not graded yet" : official != nil ? "\(right)/\(marked)" : "\(Int((rate * 100).rounded()))%")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .fixedSize()
            }
            if marked > 0 || official != nil {
                VStack(spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.well)
                            Capsule().fill(band.color.gradient).frame(width: max(8, g.size.width * min(1, max(0, fill))))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        ForEach(Array(scale.enumerated()), id: \.offset) { i, t in
                            Text(t).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                            if i < scale.count - 1 { Spacer() }
                        }
                    }
                }
            }
            extra
        }
    }

    private var scale: [String] {
        guard official != nil else { return ["0%", "50%", "100%"] }
        let low = outOf / 4
        return (0...3).map { (low + ($0 * (outOf - low)) / 3).formatted() }
    }
}

/// Add official answers / Enter SAT score, for a score card that has neither.
private struct ScoreButtons: View {
    let official: Bool, score: Bool   // what the test already has
    @Binding var importing: Bool
    @Binding var scoring: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !official { Button { importing = true } label: { Label("Add official answers", systemImage: "checkmark.seal") } }
            if !score { Button { scoring = true } label: { Label("Enter SAT score", systemImage: "number") } }
        }
        .padding(.top, 2)
    }
}

/// A section's score inside the hero, with its time and modules; click to open the section.
private struct SectionScore: View {
    let s: Session, st: Stats, official: Official?
    let action: () -> Void

    var body: some View {
        let score = s.section == Sec.math ? official?.math : official?.readingWriting
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: Sec.icon(s.section)).foregroundStyle(Sec.color(s.section))
                    Text(Sec.name(s.section)).foregroundStyle(Sec.color(s.section))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .font(T.card)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(score.map(String.init) ?? "\(st.right)").font(T.section).monospacedDigit()
                    Text(score != nil ? "of 800" : "/ \(st.marked) right").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                if score != nil { Text("\(st.right)/\(st.marked) right").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary) }   // module rows carry the times
                Spacer(minLength: 0)
                ForEach(s.modules, id: \.self) { m in
                    let ks = s.keys(m), r = ks.filter { s.correct($0) == true }.count, used = s.used(m)
                    HStack(spacing: 8) {
                        Text("Module \(m)").font(.system(size: 12, weight: .medium)).frame(width: 60, alignment: .leading)
                        Meter(value: ks.isEmpty ? 0 : Double(r) / Double(ks.count), tint: Palette.right)
                        Text("\(r)/\(ks.count)").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).fixedSize()
                        if !s.logged { Text(Fmt.clock(used)).font(.system(size: 12)).foregroundStyle(used > Sec.limit(s.section) ? Palette.wrong : .secondary).frame(width: 38, alignment: .trailing) }
                    }
                    .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift(1.01)
    }
}

/// Accuracy per topic, one column per section, weakest first.
struct TopicBars: View {
    let parts: [Session], stats: [Stats]   // stats[i] is Stats(parts[i])
    var body: some View {
        Panel("Topic accuracy", icon: "square.grid.2x2") {
            let cols = zip(parts, stats).map { (section: $0.section, topics: Self.order($1.topics)) }
            if cols.allSatisfy(\.topics.isEmpty) { Text("Topics appear once questions are explained.").font(T.body).foregroundStyle(.secondary) }
            else {
                let n = cols.map { min($0.topics.count, 5) }.max() ?? 0
                HStack(alignment: .top, spacing: 20) {
                    ForEach(cols, id: \.section) { col in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Sec.name(col.section)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Sec.color(col.section))
                            ForEach(0..<n, id: \.self) { i in
                                // Equal slots, bottom-aligned, keep the bars level across the two columns.
                                Group { if i < col.topics.count { Self.row(col.topics[i]) } else { Color.clear } }
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// Name, x/y, and a bar tinted by how well the topic went (same bands as the score).
    static func row(_ t: Stats.Topic) -> some View {
        let rate = Double(t.right) / Double(t.count)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(t.name).font(.system(size: 12)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(t.right)/\(t.count)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().fixedSize()
            }
            Meter(value: rate, tint: Palette.band(rate).color)
        }
    }

    /// Weakest first; ties by more questions, then by name, so the order never changes between renders. Other goes last.
    static func order(_ topics: [Stats.Topic]) -> [Stats.Topic] {
        topics.sorted { a, b in
            let ra = Double(a.right) / Double(a.count), rb = Double(b.right) / Double(b.count)
            return (a.name == "Other" ? 1 : 0, ra, -a.count, a.name) < (b.name == "Other" ? 1 : 0, rb, -b.count, b.name)
        }
    }
}

// MARK: - One section

/// Score and coach on the left; the filters, then Module 1 and Module 2, on the right. ← → pick a question, ↑ ↓ switch module,
/// Return opens it.
struct SectionView: View {
    let sid: String, section: String
    @Binding var filter: QFilter
    let active: Bool
    @Binding var importing: Bool
    @Binding var scoring: Bool
    let open: (String, CGRect) -> Void
    @ObservedObject var store = Store.shared
    @AppStorage("timelineStyle") private var style = "time"
    @State private var sel: String?
    @State private var frames: [Int: CGRect] = [:]
    @FocusState private var focused: Bool

    var body: some View {
        if let s = store.session(sid)?.only(section) {
            let st = Stats(s)
            let f = filter.scoped(section), match = { (k: String) in f.match(s, k) }
            VStack(spacing: L.gap) {
                HStack(alignment: .top, spacing: L.gap) {
                    // One scroll for the whole column, so a long coach review is never cut inside its card.
                        VStack(spacing: L.gap) {
                            Panel {
                                let score = section == Sec.math ? s.official?.math : s.official?.readingWriting
                                ScoreRing(official: score, outOf: 800, right: st.right, marked: st.marked, section: section) {
                                    if s.official == nil || score == nil { ScoreButtons(official: s.official != nil, score: score != nil, importing: $importing, scoring: $scoring) }
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            if !s.logged { Contributors(s: s, st: st).fixedSize(horizontal: false, vertical: true) }   // every contributor is about time
                            // No times, or no review yet: where the points went, taking the room the review would.
                            if s.debrief == nil { SkillBars(s: s, st: st) }
                            else if s.logged { SkillBars(s: s, st: st).frame(height: 236) }
                            CoachCard(sid: sid, section: section, s: s) { k, r in open(k, r) }
                        }
                    .frame(width: 330)
                    VStack(spacing: L.gap) {
                        FilterBar(f: $filter, s: s, scope: section, timeline: !s.logged)   // the filters belong to the timelines
                        ForEach(s.modules, id: \.self) { m in
                            ModuleCard(s: s, module: m, sel: $sel, match: match, legend: m == s.modules.last && style == "time" && !s.logged) { k, r in open(k, r) }
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("review")) } action: { frames[m] = $0 }
                        }
                    }
                }
            }
            .padding(L.gap)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onChange(of: active) { _, a in if a { focused = true } }
            .onKeyPress(.leftArrow) { step(s, match, -1) }
            .onKeyPress(.rightArrow) { step(s, match, 1) }
            .onKeyPress(.upArrow) { jump(s, match, -1) }
            .onKeyPress(.downArrow) { jump(s, match, 1) }
            .onKeyPress(.return) {
                guard let k = sel else { return .ignored }
                open(k, frames[Session.parts(k).1].map { CGRect(x: $0.midX - 30, y: $0.midY - 30, width: 60, height: 60) } ?? .zero)
                return .handled
            }
        }
    }

    private func step(_ s: Session, _ match: (String) -> Bool, _ d: Int) -> KeyPress.Result {
        let ks = s.keys.filter(match)
        guard !ks.isEmpty else { return .ignored }
        if let k = sel, let i = ks.firstIndex(of: k) { sel = ks[max(0, min(ks.count - 1, i + d))] } else { sel = d > 0 ? ks.first : ks.last }
        return .handled
    }

    private func jump(_ s: Session, _ match: (String) -> Bool, _ d: Int) -> KeyPress.Result {
        let cur = sel.map { Session.parts($0) } ?? (0, d > 0 ? 0 : 3, 1)
        let mods = s.modules.filter { s.keys($0).contains(where: match) }
        guard let m = d > 0 ? mods.first(where: { $0 > cur.1 }) : mods.last(where: { $0 < cur.1 }) else { return .ignored }
        let ks = s.keys(m).filter(match)
        sel = ks.first { Session.parts($0).2 == cur.2 } ?? ks.first
        return .handled
    }
}

/// Like Oura's contributors: each factor behind the score, its value colored green (fine), orange or red. Accuracy is the hero's.
private struct Contributors: View {
    let s: Session, st: Stats

    var body: some View {
        let quick = s.keys.filter { s.correct($0) == false && s.seconds($0) < s.pace / 2 }.count
        let avg = s.keys.isEmpty ? 0 : st.time / Double(s.keys.count)
        let over = s.keys.isEmpty ? 0 : Double(st.over.count) / Double(s.keys.count)
        Panel {
            row("speedometer", "Average per question", "\(Fmt.clock(avg)) / \(Fmt.clock(s.pace))", avg > s.pace ? .orange : .primary)
            row("bolt.fill", "Quick misses", "\(quick)", quick == 0 ? Palette.right : quick > 2 ? Palette.wrong : .orange)
            row("tortoise.fill", "Over pace", "\(st.over.count)", over == 0 ? Palette.right : over > 1.0 / 3 ? Palette.wrong : .orange)
        }
    }

    private func row(_ icon: String, _ name: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20, height: 20)
            Text(name).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }
    }
}

/// One section's topic accuracy with each topic's official skills under it, weakest first. On a short card the skills
/// with no misses drop first, then all but each topic's weakest, then all skills.
private struct SkillBars: View {
    let s: Session, st: Stats

    var body: some View {
        let groups = TopicBars.order(st.topics).map { d in
            let ks = s.keys.filter { s.topic($0) == d.name && s.correct($0) != nil }
            let skills = Dictionary(grouping: ks) { s.skill($0) ?? "" }.filter { !$0.key.isEmpty }
                .map { Stats.Topic(name: $0.key, count: $0.value.count, right: $0.value.filter { s.correct($0) == true }.count, avg: 0) }
            return (domain: d, skills: TopicBars.order(skills))
        }
        Panel("Topic accuracy", icon: "square.grid.2x2") {
            if groups.isEmpty { Text("Topics appear once questions are explained.").font(T.body).foregroundStyle(.secondary) }
            else {
                ViewThatFits(in: .vertical) {
                    list(groups) { $0 }
                    list(groups) { $0.filter { $0.right < $0.count } }
                    list(groups) { Array($0.filter { $0.right < $0.count }.prefix(2)) }
                    list(groups) { Array($0.filter { $0.right < $0.count }.prefix(1)) }
                    list(groups) { _ in [] }
                }
            }
        }
    }

    private func list(_ groups: [(domain: Stats.Topic, skills: [Stats.Topic])], _ shown: @escaping ([Stats.Topic]) -> [Stats.Topic]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                if i > 0 { Spacer(minLength: 14) }   // the slack goes between topics
                VStack(alignment: .leading, spacing: 6) {
                    TopicBars.row(g.domain)
                    ForEach(shown(g.skills), id: \.name) { t in
                        HStack(spacing: 6) {
                            Text(t.name).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(t.right)/\(t.count)").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(t.right < t.count ? Palette.band(Double(t.right) / Double(t.count)).color : .secondary)
                        }
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.leading, 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Feedback on the section, calm and at a glance: the verdict, then what went well, what cost points (by cause, with
/// the questions), pacing, what to do next and a goal. It fits its column: on a short window the least important
/// parts drop first (never a scroll). The full drill is on each "Do next" row's hover.
private struct CoachCard: View {
    let sid: String, section: String, s: Session
    let open: (String, CGRect) -> Void
    @ObservedObject var store = Store.shared

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(Sec.color(section).gradient)).accessibilityHidden(true)
                    coach
                }
                if let d = s.debrief {
                    ViewThatFits(in: .vertical) {
                        parts(d, went: true, pacing: true, goal: true)
                        parts(d, went: true, pacing: false, goal: true)
                        parts(d, went: true, pacing: false, goal: false)
                        parts(d, went: false, pacing: false, goal: false)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: s.debrief == nil)   // no review yet: the card hugs its button
    }

    private func parts(_ d: Debrief, went: Bool, pacing: Bool, goal: Bool) -> some View {
        let byLabel = Dictionary(s.keys.map { (s.label($0), $0) }, uniquingKeysWith: { a, _ in a })
        let fixes = Array(d.fixes.prefix(3))
        let causes = fixes.map(\.cause).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 18) {
            if went, !d.praiseJa.isEmpty {
                line("checkmark.circle.fill", Palette.right) { Rich.text(d.praiseJa, size: 13).fixedSize(horizontal: false, vertical: true) }
            }
            if !fixes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(causes, id: \.self) { c in
                        let cause = Cause.of(c, section: section)
                        let qs = fixes.filter { $0.cause == c }.flatMap(\.questions).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                        VStack(alignment: .leading, spacing: 6) {
                            Label(cause?.name ?? c.capitalized, systemImage: cause?.icon ?? "lightbulb")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.wrong)
                            Chips(labels: qs.compactMap { l in byLabel[l].map { (l, $0) } }, open: open)
                        }
                    }
                }
            }
            if pacing, !s.logged, let p = d.pacing, !p.isEmpty {
                line("clock.fill", .secondary) { Rich.text(p, size: 13).fixedSize(horizontal: false, vertical: true) }
            }
            if !fixes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(fixes.enumerated()), id: \.offset) { i, f in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "\(i + 1).circle.fill").foregroundStyle(Sec.color(section))
                            Text(f.titleJa).font(.system(size: 14, weight: .medium))
                        }
                        .help(f.drillJa)
                    }
                }
            }
            if goal, let g = d.goal, !g.isEmpty {
                line("target", Sec.color(section)) { Rich.text(g, size: 13, color: .primary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ icon: String, _ tint: Color, @ViewBuilder _ text: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
            text()
        }
    }

    @ViewBuilder private var coach: some View {
        let writing = store.busy.contains("\(sid)/debrief-\(section)"), explaining = store.busy.contains { $0.hasPrefix(sid + "/") && !$0.hasSuffix("/chat") }
        if let d = s.debrief {
            Text(d.headlineJa).font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        } else if writing || explaining {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reviewing your answers…").foregroundStyle(.secondary) }.font(.system(size: 14))
        } else if !Brain.ready {
            Button("Set up a tutor") { Store.shared.nav = .settings }
        } else if s.keys.contains(where: { s.q[$0]?.analysis != nil }) {
            Button { Task { await Tutor.debrief(sid, section) } } label: { Label("Write the review", systemImage: "sparkles") }
        } else {
            Button { Tutor.analyzeAll(sid) } label: { Label("Explain my answers", systemImage: "sparkles") }
        }
    }
}

/// One module: time per question as bars (green right, red wrong) against a dashed pace line. Click a bar to open
/// that question.
private struct ModuleCard: View {
    let s: Session, module: Int
    @Binding var sel: String?
    let match: (String) -> Bool
    var legend = false   // one card per page shows the legend
    let open: (String, CGRect) -> Void
    @State private var hover: Int?
    @State private var frame: CGRect = .zero
    @AppStorage("timelineStyle") private var style = "time"
    @Environment(\.colorScheme) private var scheme

    /// One question's numbers, read once per render; the views below and every hover reuse them.
    struct Row { let key: String, n: Int, seconds: Double, c: Bool?, on: Bool }

    var body: some View {
        let rows = s.keys(module).map { k in Row(key: k, n: Session.parts(k).2, seconds: s.seconds(k), c: s.correct(k), on: match(k)) }
        let dark = scheme == .dark
        let right = rows.filter { $0.c == true }.count, wrong = rows.filter { $0.c == false }.count
        // One long question shouldn't flatten the rest: cap the scale and label the bars that go past it.
        let cap = max(1, min(3 * s.pace, rows.map(\.seconds).max() ?? 0))
        let ungraded = rows.contains { $0.c == nil }
        let focusN = hover ?? sel.flatMap { k in Session.parts(k).1 == module ? Session.parts(k).2 : nil }
        Panel("Module \(module)", icon: "\(module).circle.fill") {
            dot(Palette.right, "\(right)"); dot(Palette.wrong, "\(wrong)")
            if !s.logged { Label("\(Fmt.clock(s.used(module))) / \(Fmt.clock(Sec.limit(s.section)))", systemImage: "clock")
                .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit() }
        } content: {
            switch s.logged ? "grid" : style {   // a logged test has no times: tiles only
            case "grid": grid(rows, focusN)
            case "order": order(rows, focusN).frame(maxHeight: .infinity)
            default: bars(rows, cap: cap, dark: dark, focusN: focusN)
            }
            detail(focusN.flatMap { n in rows.first { $0.n == n } }, ungraded: ungraded)
        }
    }

    /// Bluebook-style tiles: number, time, result color. Easy to scan for red.
    /// Rows of nine; the tiles grow to fill the card.
    private func grid(_ rows: [Row], _ focusN: Int?) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: rows.count, by: 9)), id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(rows[i..<min(i + 9, rows.count)], id: \.key) { tile($0, focusN) }
                    ForEach(0..<(9 - min(9, rows.count - i)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }   // a short last row keeps the columns
                }
            }
        }
    }

    private func tile(_ row: Row, _ focusN: Int?) -> some View {
        let k = row.key, n = row.n, c = row.c, slow = row.seconds > s.pace
        return VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 17, weight: .bold, design: .rounded))
            if !s.logged { Text(Fmt.clock(row.seconds)).font(.system(size: 10, weight: slow ? .bold : .regular).monospacedDigit()).opacity(0.85) }
        }
        .foregroundStyle(c == false ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: .infinity)
        .background(Palette.fill(c, dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if s.q[k]?.flagged == true { Image(systemName: "flag.fill").font(.system(size: 8)).foregroundStyle(.orange).padding(4) }
        }
        .overlay { if focusN == n { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary, lineWidth: 2) } }
        .opacity(row.on ? 1 : 0.15)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hover = n; return }
            // clear a moment later, and only if no other tile took over (no flash between tiles)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { if hover == n { hover = nil } }
        }
        .onTapGesture(coordinateSpace: .named("review")) { p in
            guard row.on else { return }
            sel = k
            open(k, CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44))
        }
        .pointerStyle(row.on ? .link : .default)
    }

    /// The order the student actually worked: each visit as a block on the clock (width = time), 2 pt apart.
    /// First passes on the top row, returns to a question on the bottom row. Hovering a question lights up all its visits.
    private func order(_ qs: [Row], _ focusN: Int?) -> some View {
        let byKey = Dictionary(qs.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let vs = s.visits.filter { $0.module == module }.sorted { $0.start < $1.start }
        let t0 = vs.first?.start ?? s.start
        let total = max(Sec.limit(s.section), vs.last.map { ($0.end ?? $0.start).timeIntervalSince(t0) } ?? 1)
        var seen = Set<String>()
        let rows: [(v: Visit, back: Bool)] = vs.map { v in defer { seen.insert(v.key) }; return (v, seen.contains(v.key)) }
        let label: CGFloat = 78, tag: CGFloat = 24, gap: CGFloat = 6   // tag: room under each row for numbers of narrow blocks
        return GeometryReader { g in
            let lay = OrderLayout(rows: rows, t0: t0, total: total, size: g.size, label: label, tag: tag, gap: gap)
            let lane = lay.lane, rowY = lay.rowY, blocks = lay.blocks, w = g.size.width - label
            ZStack(alignment: .topLeading) {
                ForEach(0..<2, id: \.self) { i in
                    Text(i == 0 ? "First pass" : "Back again").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: label - 8, height: lane, alignment: .leading)
                        .offset(y: rowY[i])
                }
                ForEach(Array(stride(from: 0, through: Int(total / 60), by: 5)), id: \.self) { m in
                    let x: CGFloat = label + w * CGFloat(Double(m * 60) / total)
                    Rectangle().fill(.quaternary).frame(width: 1, height: rowY[1] + lane).offset(x: x)
                    let edge = x + 20 > g.size.width   // the last label ends at the card's edge instead of past it
                    Text(m + 5 > Int(total / 60) ? "\(m) min" : "\(m)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize()   // the unit once, on the last
                        .frame(width: 40, alignment: edge ? .trailing : .center).offset(x: edge ? g.size.width - 40 : x - 20, y: rowY[1] + lane + tag + 2)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, bl in
                    let n = bl.v.number, k = bl.v.key, c = byKey[k]?.c, on = byKey[k]?.on == true   // every visit in the module has a row
                    let dim = !on ? 0.15 : hover == nil || hover == n ? 1.0 : 0.3   // only hovering dims; a selection is outlined
                    let y = rowY[bl.back ? 1 : 0]
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Palette.fill(c, dark: scheme == .dark))
                        .overlay {
                            if bl.bw >= 16 {
                                Text("\(n)").font(.system(size: bl.bw >= 24 ? 11 : 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundStyle(c == false ? Color.white : Color.primary)
                            }
                        }
                        .overlay { if focusN == n { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.primary, lineWidth: 2) } }
                        .frame(width: bl.bw, height: lane)
                        .opacity(dim)
                        .offset(x: bl.x, y: y)
                        .allowsHitTesting(false)   // the whole chart takes hover and clicks (below), so nothing is missed between blocks
                        .help("\(s.label(k)) · \(Fmt.clock(bl.v.seconds))\(bl.back ? " · back again" : "")")
                    if bl.bw < 16, let level = bl.level {   // too narrow for its number: print it just under the block
                        Text("\(n)").font(.system(size: 9, weight: focusN == n ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(focusN == n ? Color.primary : Color.secondary)
                            .fixedSize()
                            .frame(width: 20)
                            .offset(x: bl.x + bl.bw / 2 - 10, y: y + lane + (level == 1 ? 12 : 2))
                            .opacity(dim)
                            .allowsHitTesting(false)
                    }
                }
            }
            // Fill the whole chart: offset blocks don't size the stack, so without this only its top-left corner took the pointer.
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            // One rule for hover and click: the block under the pointer, or the nearest one in that row within 4 pt,
            // so the 2 pt gaps between blocks never drop or flash.
            .onContinuousHover { phase in
                guard case .active(let p) = phase, let b = lay.pick(p) else { if hover != nil { hover = nil }; return }
                if hover != b.v.number { hover = b.v.number }
            }
            .onTapGesture { p in
                guard let b = lay.pick(p), byKey[b.v.key]?.on == true else { return }
                let o = g.frame(in: .named("review")).origin
                sel = b.v.key
                open(b.v.key, CGRect(x: o.x + b.x + b.bw / 2 - 22, y: o.y + rowY[b.back ? 1 : 0] + lane / 2 - 22, width: 44, height: 44))
            }
        }
    }

    @ViewBuilder private func bars(_ rows: [Row], cap: Double, dark: Bool, focusN: Int?) -> some View {
            Chart {
                ForEach(rows, id: \.key) { row in
                    let n = row.n
                    // categorical x: ratio widths only work on a band scale
                    BarMark(x: .value("Question", "\(n)"), y: .value("Minutes", min(row.seconds, cap) / 60), width: .ratio(0.72))
                        .foregroundStyle(Palette.fill(row.c, dark: dark))
                        .cornerRadius(4)
                        .opacity(!row.on ? 0.15 : hover == nil || hover == n ? 1 : 0.35)   // only hovering dims; the selection's number is bold
                        .annotation(position: .top) {
                            if row.seconds > cap { Text(Fmt.clock(row.seconds)).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary) }
                        }
                        .annotation(position: .overlay, alignment: .top) {   // taller than the scale: cut, not squashed
                            if row.seconds > cap { BreakMark().padding(.top, 6) }
                        }
                }
                RuleMark(y: .value("Pace", s.pace / 60))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3])).foregroundStyle(Color.primary.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {   // the line names itself
                        Text("Pace \(Fmt.clock(s.pace))").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: rows.map { "\($0.n)" })
            .chartYScale(domain: 0...cap / 60 * 1.08)
            .chartXAxisLabel(position: .bottom, alignment: .trailing) { Text("Question").font(.system(size: 10)) }   // a little headroom for the cut-off bars' labels
            .chartXAxis {
                AxisMarks { v in
                    let n = v.as(String.self) ?? ""
                    AxisValueLabel { Text(n).font(.system(size: 10, weight: n == focusN.map(String.init) ? .heavy : .medium)).foregroundStyle(n == focusN.map(String.init) ? Color.primary : Color.secondary) }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0)) min").font(.system(size: 10)) }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let p) = phase { hover = row(rows, number(proxy, g, p))?.n } else { hover = nil }
                        }
                        .onTapGesture { p in
                            guard let k = row(rows, number(proxy, g, p))?.key else { return }
                            sel = k
                            open(k, CGRect(x: frame.minX + p.x - 22, y: frame.minY + p.y - 22, width: 44, height: 44))
                        }
                        .pointerStyle(hover == nil ? .default : .link)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("review")) } action: { frame = $0 }
            .frame(maxHeight: .infinity)
    }

    /// The question at a bar, if the filter shows it.
    private func row(_ rows: [Row], _ n: Int?) -> Row? { rows.first { $0.n == n && $0.on } }

    private func number(_ proxy: ChartProxy, _ g: GeometryProxy, _ p: CGPoint) -> Int? {
        guard let plot = proxy.plotFrame, let x: String = proxy.value(atX: p.x - g[plot].minX) else { return nil }
        return Int(x)
    }

    private func dot(_ c: Color, _ n: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(n).monospacedDigit() }.font(.system(size: 12, weight: .semibold))
    }

    /// The hovered or selected question; otherwise the legend, if this card carries it.
    @ViewBuilder private func detail(_ row: Row?, ungraded: Bool) -> some View {
        HStack(spacing: 12) {
            if let row {
                let k = row.key, visits = s.visitCount(k)
                Text(s.label(k)).font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
                ResultBadge(c: row.c, mine: s.q[k]?.mark != nil)
                if row.c == false, let a = answers(k) { Text("\(a.yours.map { "You \($0)" } ?? "Omitted") · Answer \(a.correct)").lineLimit(1).fixedSize() }
                if !s.logged { Label(Fmt.clock(row.seconds), systemImage: "clock").foregroundStyle(row.seconds > s.pace ? Palette.wrong : .secondary) }
                if visits > 1 { Label("\(visits)", systemImage: "arrow.uturn.backward").help("\(visits) visits") }
                if let d = QFilter.difficulty(s, k) { QFilter.difficultyIcon(d) }
                if let skill = s.official?.answers[k]?.skill ?? s.q[k]?.analysis?.skill { Text(skill).lineLimit(1) }
            } else if legend {
                swatch(Palette.fill(true, dark: scheme == .dark), "Right"); swatch(Palette.fill(false), "Wrong")
                if ungraded { swatch(Palette.fill(nil), "Not graded") }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 18)
    }

    /// The student's pick (first word: the tutor may add notes after it) and the right answer, the same sources as the question header.
    private func answers(_ k: String) -> (yours: String?, correct: String)? {
        if let a = s.q[k]?.analysis, !a.correctAnswer.isEmpty {
            let y = a.studentAnswer.split(separator: " ").first.map(String.init)
            return (y == "none" ? nil : y, a.correctAnswer)
        }
        guard let o = s.official?.answers[k], !o.correct.isEmpty else { return nil }
        return (o.yours, o.correct)
    }

    private func swatch(_ c: Color, _ name: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(name) }
    }
}


/// Where each visit sits in the order timeline, and which block a point belongs to (shared by hover and click).
private struct OrderLayout {
    typealias Block = (v: Visit, back: Bool, x: CGFloat, bw: CGFloat, level: Int?)
    let lane: CGFloat, rowY: [CGFloat], blocks: [Block], tag: CGFloat, gap: CGFloat

    init(rows: [(v: Visit, back: Bool)], t0: Date, total: Double, size: CGSize, label: CGFloat, tag: CGFloat, gap: CGFloat) {
        let w = size.width - label
        lane = max(24, min(120, (size.height - 22 - tag * 2 - gap) / 2))
        rowY = [0, lane + tag + gap]
        self.tag = tag; self.gap = gap
        // A narrow block's number goes under it on the first of two heights with 15 pt of room; otherwise none (hover shows it).
        var out: [Block] = [], last: [[CGFloat]] = [[-99, -99], [-99, -99]]
        for r in rows {
            let a = r.v.start.timeIntervalSince(t0), b = (r.v.end ?? r.v.start).timeIntervalSince(t0)
            let x = label + w * CGFloat(a / total), bw = max(3, w * CGFloat((b - a) / total) - 2), i = r.back ? 1 : 0
            var level: Int?
            if bw < 16, let l = [0, 1].first(where: { x + bw / 2 - last[i][$0] >= 15 }) { level = l; last[i][l] = x + bw / 2 }
            out.append((r.v, r.back, x, bw, level))
        }
        blocks = out
    }

    /// The block under the point, or the nearest one in that row within 4 pt.
    func pick(_ p: CGPoint) -> Block? {
        let back = p.y >= rowY[1] - gap / 2
        guard p.y >= 0, p.y <= rowY[back ? 1 : 0] + lane + tag else { return nil }
        let near = blocks.filter { $0.back == back }.min { abs(($0.x + $0.bw / 2) - p.x) - $0.bw / 2 < abs(($1.x + $1.bw / 2) - p.x) - $1.bw / 2 }
        guard let b = near, p.x >= b.x - 4, p.x <= b.x + b.bw + 4 else { return nil }
        return b
    }
}


/// Time / Grid / Order, shared by every timeline (one setting for the whole app).
struct TimelinePicker: View {
    @AppStorage("timelineStyle") private var style = "time"
    var body: some View {
        Picker("Timeline", selection: $style.animation(.smooth(duration: 0.3))) {
            Image(systemName: "chart.bar.fill").help("Time per question").tag("time")
            Image(systemName: "square.grid.3x3.fill").help("Grid").tag("grid")
            Image(systemName: "point.forward.to.point.capsulepath.fill").help("Order you worked in").tag("order")
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
    }
}


/// Three rising bars, filled up to the difficulty (Easy 1, Medium 2, Hard 3). The word shows on hover.
struct DifficultyBars: View {
    let level: String
    var body: some View {
        let n = ["easy": 1, "medium": 2, "hard": 3][level.lowercased()] ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.2).fill(i <= n ? Color.primary.opacity(0.75) : Color.primary.opacity(0.18))
                    .frame(width: 3.5, height: 4 + CGFloat(i) * 3)
            }
        }
        .frame(height: 13, alignment: .bottom)
        .contentShape(Rectangle())
        .help(level.isEmpty ? "Difficulty unknown" : "\(level.capitalized) question")
        .accessibilityElement().accessibilityLabel("\(level) difficulty")
    }
}

/// The "axis break" sign: two wavy lines cutting across a bar that is taller than the chart shows.
struct BreakMark: View {
    var color: Color = Palette.surface
    var body: some View {
        Canvas { ctx, size in
            for row in 0..<2 {
                var p = Path(), y = size.height * (row == 0 ? 0.3 : 0.7)
                p.move(to: CGPoint(x: -2, y: y))
                var x: CGFloat = -2, up = true
                while x < size.width + 2 { x += 5; y += up ? -2.5 : 2.5; up.toggle(); p.addLine(to: CGPoint(x: x, y: y)) }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 48, height: 12)   // wider than any bar: the background-colored waves cut it edge to edge
        .allowsHitTesting(false)
    }
}
