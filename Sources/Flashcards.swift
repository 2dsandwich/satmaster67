import SwiftUI

struct Card: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case word, mistake }
    var id: String             // "word:<lowercased term>" or "q:<sessionId>/<questionKey>"
    var kind: Kind
    var front: String
    var back: String
    var detail: String?
    var ease = 2.5
    var interval = 0           // days
    var reps = 0
    var lapses = 0
    var due = Date()
    var lastReviewed: Date?
    var added = Date()
    var introduced: Date?      // first review; caps new cards per day

    var isNew: Bool { lastReviewed == nil }
    var learning: Bool { !isNew && reps == 0 }
}

/// Spaced repetition (SM-2) over words and missed questions: cards.json next to the sessions.
@MainActor final class CardStore: ObservableObject {
    static let shared = CardStore()
    @Published var cards: [Card]
    private let file: String?
    static let newPerDay = 20, glossaryPerDay = 10

    init(file: String? = "cards.json") {
        self.file = file
        cards = file.flatMap { Files.load($0, as: [Card].self) } ?? []
    }

    private func save() { if let file { Files.save(cards, file) } }

    // MARK: SM-2

    /// Grade 1–4 (Again, Hard, Good, Easy) → SM-2 quality 1, 3, 4, 5.
    static func schedule(_ card: Card, _ grade: Int, now: Date = Date()) -> Card {
        var c = card
        let q = [1, 3, 4, 5][min(max(grade, 1), 4) - 1]
        c.introduced = c.introduced ?? now
        c.lastReviewed = now
        if q < 3 {
            if c.reps > 0 { c.lapses += 1 }
            c.reps = 0
            c.interval = 1
            c.due = now + 600
        } else {
            c.reps += 1
            c.interval = c.reps == 1 ? 1 : c.reps == 2 ? 6 : Int((Double(c.interval) * c.ease).rounded())
            let d = Double(5 - q)
            c.ease = max(1.3, c.ease + 0.1 - d * (0.08 + d * 0.02))
            let cal = Calendar.current   // due at the start of the day, so a morning review isn't blocked by last night's time
            c.due = cal.date(byAdding: .day, value: c.interval, to: cal.startOfDay(for: now)) ?? now + Double(c.interval) * 86400
        }
        return c
    }

    /// Next interval for a button: "10m", "1d", "6d", "2w", "3mo".
    static func preview(_ card: Card, _ grade: Int) -> String {
        guard grade > 1 else { return "10m" }
        let d = schedule(card, grade).interval
        return d < 7 ? "\(d)d" : d < 30 ? "\(d / 7)w" : d < 365 ? "\(d / 30)mo" : "\(d / 365)y"
    }

    func grade(_ id: String, _ g: Int) {
        guard (1...4).contains(g), let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i] = Self.schedule(cards[i], g)
        save()
    }

    // MARK: Queue

    private var newLeft: Int {
        max(0, Self.newPerDay - cards.filter { $0.introduced.map(Calendar.current.isDateInToday) ?? false }.count)
    }

    private func deck(_ kind: Card.Kind?) -> [Card] { cards.filter { kind == nil || $0.kind == kind } }

    var counts: (new: Int, learning: Int, due: Int) { tally(nil) }

    func tally(_ kind: Card.Kind?) -> (new: Int, learning: Int, due: Int) {
        let c = deck(kind), now = Date()
        return (min(c.filter(\.isNew).count, newLeft),
                c.filter { $0.learning && $0.due <= now }.count,
                c.filter { $0.reps > 0 && $0.due <= now }.count)
    }

    func next(_ kind: Card.Kind? = nil) -> Card? {
        let c = deck(kind).sorted { $0.due < $1.due }, now = Date()
        return c.first { $0.learning && $0.due <= now }
            ?? c.first { $0.reps > 0 && $0.due <= now }
            ?? (newLeft > 0 ? c.first(where: \.isNew) : nil)
    }

    /// When the next already-studied card comes due.
    func nextDue(_ kind: Card.Kind? = nil) -> Date? { deck(kind).filter { !$0.isNew }.map(\.due).min() }

    // MARK: Sync

    /// Claude sometimes returns a sentence fragment ("out of every") as a word. Real terms are 1-4 words with a real word in them.
    private static let glossaryTerms = Set(Glossary.all.map { $0.en.lowercased() })
    static func isTerm(_ v: Vocab) -> Bool {
        let words = v.en.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if glossaryTerms.contains(words.joined(separator: " ")) { return true }
        let function: Set = ["of", "the", "a", "an", "to", "and", "or", "every", "each", "out", "in", "on", "at", "by", "for", "with", "from", "is", "are"]
        return (1...4).contains(words.count) && !v.note.trimmingCharacters(in: .whitespaces).isEmpty
            && words.contains { $0.count >= 3 && $0.allSatisfy(\.isLetter) }
            && !function.contains(words[0]) && !function.contains(words[words.count - 1])
    }

    /// Adds cards from the tests and the glossary. Existing cards keep their progress; only their text is refreshed.
    func sync(_ sessions: [Session]? = nil) {
        let before = cards
        cards.removeAll { $0.kind == .word && $0.isNew && !Self.isTerm(Vocab(en: $0.front, ja: $0.detail ?? "", note: $0.back)) }
        // New cards are studied in due order: a word from a question you got wrong is due first.
        func put(_ c: Card, missed: Bool = false) {
            if let i = cards.firstIndex(where: { $0.id == c.id }) {
                (cards[i].front, cards[i].back, cards[i].detail) = (c.front, c.back, c.detail)   // Claude's analysis may arrive later
                if missed && cards[i].isNew { cards[i].due = .distantPast }
            } else { var c = c; if missed { c.due = .distantPast }; cards.append(c) }
        }
        for s in sessions ?? Store.shared.sessions {
            let keys = Set(s.keys).union(s.q.keys).union(s.official.map { Array($0.answers.keys) } ?? [])
            for key in keys.sorted() {
                let a = s.q[key]?.analysis, off = s.official?.answers[key]
                for v in a?.vocab ?? [] where Self.isTerm(v) {
                    put(Card(id: "word:\(v.en.lowercased())", kind: .word, front: v.term, back: v.note, detail: v.ja), missed: s.correct(key) == false)
                }
                guard s.correct(key) == false else { continue }
                let place = "\(s.title) · \(s.label(key))"
                let text = [a?.keyPhrase, a?.questionEn, off?.question].compactMap { $0 }.first { !$0.isEmpty }
                let front = text.map { $0.count > 140 ? String($0.prefix(140)) + "…" : $0 } ?? place
                let back = [(a?.correctAnswer ?? off?.correct).flatMap { $0.isEmpty ? nil : "Answer: \($0)" }, a?.coachLine].compactMap { $0 }   // a result-only record has no letter
                put(Card(id: "q:\(s.id)/\(key)", kind: .mistake, front: front, back: back.joined(separator: "\n\n"), detail: place))
            }
        }
        let glossary = Set(Glossary.all.map { "word:\($0.en.lowercased())" })
        var room = Self.glossaryPerDay - cards.filter { glossary.contains($0.id) && Calendar.current.isDateInToday($0.added) }.count
        let have = Set(cards.map(\.id))
        for v in Glossary.all where room > 0 && !have.contains("word:\(v.en.lowercased())") {
            cards.append(Card(id: "word:\(v.en.lowercased())", kind: .word, front: v.term, back: v.note, detail: v.ja))
            room -= 1
        }
        if cards != before { save() }
    }

    // MARK: Self-check

    static func selfCheck() -> [String] {
        var fails: [String] = []
        var c = Card(id: "word:x", kind: .word, front: "x", back: "y")
        var iv: [Int] = []
        for _ in 0..<3 { c = schedule(c, 3); iv.append(c.interval) }
        if iv != [1, 6, 15] || c.ease != 2.5 { fails.append("Good ×3 should give 1, 6, 15 days at EF 2.5, got \(iv) EF \(c.ease)") }
        c = schedule(c, 1)
        if c.reps != 0 || c.interval != 1 || c.lapses != 1 || c.due.timeIntervalSinceNow > 601 || c.ease != 2.5 {
            fails.append("Again should reset reps, keep EF and return in 10m, got reps \(c.reps) EF \(c.ease)")
        }
        for _ in 0..<20 { c = schedule(c, 2) }
        if c.ease != 1.3 { fails.append("EF should floor at 1.3, got \(c.ease)") }
        if preview(Card(id: "", kind: .word, front: "", back: "", interval: 6, reps: 2), 3) != "2w" { fails.append("preview of 15 days should be 2w") }

        if CardStore.isTerm(Vocab(en: "out of every", ja: "", note: "x")) || !CardStore.isTerm(Vocab(en: "slope", ja: "", note: "x")) { fails.append("isTerm should reject fragments and keep terms") }
        let store = CardStore(file: nil)
        let s = Session(id: "t", start: Date(), test: "Test", visits: [Visit(module: 1, number: 1, start: Date(), end: Date())],
                        q: ["M1-1": QState(mark: false)])
        store.sync([s])
        let n = store.cards.count
        store.grade("q:t/M1-1", 3)
        store.sync([s])
        if n != 1 + glossaryPerDay || store.cards.count != n || Set(store.cards.map(\.id)).count != n {
            fails.append("sync should add 1 mistake + \(glossaryPerDay) words once, got \(n) then \(store.cards.count)")
        }
        if store.cards.first(where: { $0.id == "q:t/M1-1" })?.reps != 1 { fails.append("sync reset a card's progress") }
        // Words from a question you got wrong come up first among new cards.
        let words = CardStore(file: nil)
        func analysed(_ word: String, _ verdict: String) -> QState {
            var q = QState()
            q.analysis = Analysis(questionEn: "", questionJa: "", topic: "", skill: "", difficulty: "", correctAnswer: "", studentAnswer: "", verdict: verdict,
                                  solutionJa: "", wordingJa: "", trapJa: "", timeJa: "", vocab: [Vocab(en: word, ja: "", note: "x")])
            return q
        }
        var w = s; w.visits.append(Visit(module: 1, number: 2, start: Date(), end: Date()))
        w.q = ["M1-1": analysed("opaque", "correct"), "M1-2": analysed("lucid", "wrong")]
        words.sync([w])
        if words.next(.word)?.id != "word:lucid" { fails.append("a word from a missed question should come first, got \(words.next(.word)?.id ?? "none")") }
        return fails
    }
}

// MARK: - Study screen

struct FlashcardsView: View {
    @ObservedObject private var store = CardStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cardsDeck") private var deck: Card.Kind?   // a plan task opens the Mistakes deck
    @State private var card: Card?
    @State private var flipped = false
    @FocusState private var focused: Bool

    private static let cardHeight: CGFloat = 360
    private var studiedToday: Int { store.cards.filter { $0.lastReviewed.map(Calendar.current.isDateInToday) ?? false }.count }
    private static let grades: [(String, Color)] = [("Again", Palette.wrong), ("Hard", .primary), ("Good", .accentColor), ("Easy", Palette.right)]
    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.8) }

    var body: some View {
        let n = store.tally(deck), studiedToday = self.studiedToday   // one pass over the cards, not two
        VStack(alignment: .leading, spacing: L.gap) {
            PageTitle(title: "Flashcards")
            HStack(alignment: .top, spacing: L.gap * 2) {   // deck picker where the Words page has its own
                Segments(items: [("All", nil), ("Vocabulary", .word), ("Mistakes", .mistake)], value: $deck)
                    .frame(width: 280)
                Spacer()
                count(n.new, "New")
                count(n.learning, "Learning")
                count(n.due, "Due")
            }
            .animation(.smooth(duration: 0.3), value: n.new + n.learning * 1000 + n.due * 1_000_000)
            VStack(spacing: L.gap) {
                ZStack {
                    if let card {
                        face(card, "\(studiedToday + 1) of \(studiedToday + n.new + n.learning + n.due)")
                            .id(card.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .scale(scale: 0.94)).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        done.transition(.opacity)
                    }
                }
                .frame(height: Self.cardHeight)
                ZStack {
                    reveal.opacity(flipped || card == nil ? 0 : 1).allowsHitTesting(!flipped && card != nil)
                    buttons.opacity(flipped ? 1 : 0).allowsHitTesting(flipped)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(L.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { store.sync(); card = store.next(deck); focused = true }
        .onChange(of: deck) { show(store.next(deck)) }
        .onKeyPress(.space) { guard card != nil else { return .ignored }; flip(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "1234")) { k in
            guard flipped, let g = Int(k.characters) else { return .ignored }
            grade(g)
            return .handled
        }
        .task(id: card?.id) {
            // Caught up: bring the next card in when it comes due.
            guard card == nil, let at = store.nextDue(deck) else { return }
            try? await Task.sleep(for: .seconds(max(1, at.timeIntervalSinceNow)))
            if !Task.isCancelled { show(store.next(deck)) }
        }
    }

    private func count(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(T.value).monospacedDigit().contentTransition(.numericText())
            Text(label).font(T.caption).foregroundStyle(.secondary)
        }
    }

    private func face(_ c: Card, _ place: String) -> some View {
        sheet(place) {
            (c.kind == .mistake ? Rich.text(c.front, size: 34, weight: .semibold, color: .primary) : Text(c.front))   // a logged question's math
                .font(.system(size: 34, weight: .semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
        }
        .modifier(Flip(angle: flipped ? 180 : 0, flat: reduceMotion, back: sheet(place) {
            VStack(spacing: L.inset) {
                Text(c.front).font(T.card).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                Text(c.back.sentenceCase).font(T.section).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                if let d = c.detail, !d.isEmpty {
                    if c.kind == .word {
                        Text(d).font(T.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 3).background(Palette.well, in: Capsule())
                    } else { Text(d).font(T.body).foregroundStyle(.secondary) }
                }
            }
        }))
        .contentShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .onTapGesture { flip() }
    }

    /// A card face, with its place in today's queue in the corner.
    private func sheet(_ place: String, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(L.inset * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { Text(place).font(T.caption).foregroundStyle(.secondary).monospacedDigit().padding(L.inset) }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }

    private var buttons: some View {
        HStack(spacing: L.inset / 2) {
            ForEach(1...4, id: \.self) { g in
                let tint = Self.grades[g - 1].1
                Button { grade(g) } label: {
                    VStack(spacing: 1) {
                        Text(Self.grades[g - 1].0).font(T.card).foregroundStyle(tint)
                        Text(card.map { CardStore.preview($0, g) } ?? "").font(T.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                }
                .buttonStyle(.plain)
                .hoverLift()
            }
        }
    }

    private var reveal: some View {
        Button { flip() } label: {
            Text("Show answer").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverLift()
    }

    private var done: some View {
        ContentUnavailableView {
            Label { Text("All caught up") } icon: { Image(systemName: "checkmark.seal").foregroundStyle(Palette.right) }
        } description: {
            if let at = store.nextDue(deck) { Text("Next card \(at.formatted(.relative(presentation: .named)))") }
        }
    }

    private func flip() { withAnimation(motion) { flipped.toggle() } }

    private func grade(_ g: Int) {
        guard flipped, let c = card else { return }
        store.grade(c.id, g)
        show(store.next(deck))
    }

    private func show(_ c: Card?) { withAnimation(motion) { flipped = false; card = c } }
}

/// Shows the front until the card turns edge-on, then the back, counter-rotated so it isn't mirrored.
private struct Flip<Back: View>: ViewModifier, Animatable {
    var angle: Double
    let flat: Bool             // Reduce Motion: cross-fade instead of turning
    let back: Back
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let p = angle / 180
        ZStack {
            content.opacity(flat ? 1 - p : angle < 90 ? 1 : 0)
            back.opacity(flat ? p : angle < 90 ? 0 : 1)
                .rotation3DEffect(.degrees(flat ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flat ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

extension String {
    var sentenceCase: String { prefix(1).uppercased() + dropFirst() }
}
