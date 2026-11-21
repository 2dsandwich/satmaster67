import SwiftUI

/// A practice test taken without the tracker, logged afterwards in steps: College Board's Score Details page gives every
/// question's result (and the test name and date), then Khan Academy's copy of each module gives the questions
/// themselves, then a Bluebook-like review fixes what the reading got wrong. Only the results are required.
struct LogTestSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int
    @State private var forward = true   // which way the steps slide
    @State private var record: Official?
    @State private var test = ""
    @State private var date = Date()
    @State private var rw = ""
    @State private var math = ""
    @State private var failed: String?                    // why the Score Details paste gave no test
    @State private var found: [String: Official.Answer]   // question text by key, from Khan Academy
    @State private var missed: Set<String> = []          // modules whose paste had no questions
    @State private var reading: String?                  // the module the AI is reading
    @State private var open: String?                     // the question on the review step
    @State private var pictures: [String: NSImage] = [:] // pasted pictures of graphs the text can't rebuild, by key

    private static let titles = ["Results", "R&W 1", "R&W 2", "Math 1", "Math 2", "Review"]

    /// The arguments are for snapshots: a Score Details page, Khan Academy pages by module ("R1" …), the step to show.
    init(page: String? = nil, modules: [String: String] = [:], step: Int = 0, open: String? = nil) {
        var f: [String: Official.Answer] = [:]
        for (m, text) in modules { for (n, a) in Khan.parse(text, max: Khan.expected(m)) { f["\(m)-\(n)"] = a } }
        _found = State(initialValue: f)
        _step = State(initialValue: step)
        _open = State(initialValue: open)
        if let page, let r = Self.results(page) {
            _record = State(initialValue: r.o); _test = State(initialValue: r.test); _date = State(initialValue: r.date)
            _rw = State(initialValue: r.o.readingWriting.map(String.init) ?? ""); _math = State(initialValue: r.o.math.map(String.init) ?? "")
        }
    }

    /// "SAT Practice 10 - November 5, 2026" at the top of the Score Details page.
    static func heading(_ page: String) -> (test: String, date: Date?)? {
        guard let m = page.firstMatch(of: #/(SAT Practice \d{1,2})\s*[-–]\s*([A-Z][a-z]+ \d{1,2}, \d{4})/#) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM d, yyyy"
        return (String(m.1), f.date(from: String(m.2)))
    }

    static func results(_ page: String) -> (o: Official, test: String, date: Date)? {
        let o = Importer.parse(page)
        guard o.answers.count >= 20, let h = heading(page) else { return nil }
        return (o, h.test, h.date ?? Date())
    }

    /// A test already in the app for the same practice test and day: the record is added to it instead of a duplicate.
    private var existing: Session? {
        store.sessions.first { $0.test == test && Calendar.current.isDate($0.start, inSameDayAs: date) }
    }

    /// Questions that can be saved: read from Khan Academy and graded on the Score Details page.
    private var keys: [String] {
        found.keys.filter { record?.answers[$0] != nil }.sorted { Session.parts($0) < Session.parts($1) }
    }

    private func count(_ m: String) -> Int { keys.count(where: { $0.hasPrefix(m + "-") }) }

    var body: some View {
        let a = ScoreSheet.section(rw), b = ScoreSheet.section(math)
        let scoresOK = a.problem == nil && b.problem == nil && (a.value == nil) == (b.value == nil)
        VStack(alignment: .leading, spacing: L.gap) {
            indicator
            ZStack {
                Group {
                    switch step {
                    case 0: results(a.problem ?? b.problem)
                    case 1...4: module(Khan.modules[step - 1])
                    default: review
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.push(from: forward ? .trailing : .leading))
            }
            .clipped()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if step > 0 { Button("Back") { go(-1) } }
                if step < 5 {
                    Button((1...4).contains(step) && count(Khan.modules[step - 1]) == 0 ? "Skip" : "Next") { go(1) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(step == 0 && (record == nil || test.isEmpty || !scoresOK) || reading != nil)
                } else {
                    Button(existing == nil ? "Add Test" : "Add to Existing Test") { save(a.value, b.value) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(L.inset)
        .frame(width: 940, height: 680)
    }

    private func go(_ d: Int) {
        forward = d > 0
        withAnimation(.smooth(duration: 0.3)) { step += d }
    }

    /// Six numbered steps; a done step shows a check.
    private var indicator: some View {
        HStack(spacing: 0) {
            ForEach(Self.titles.indices, id: \.self) { i in
                let done = i == 0 ? record != nil : (1...4).contains(i) && count(Khan.modules[i - 1]) > 0
                let tint = (1...4).contains(i) ? Sec.color(Session.section(of: Khan.modules[i - 1])) : Color.primary
                HStack(spacing: 8) {
                    Group {
                        if done && i != step { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                        else { Text("\(i + 1)").font(.system(size: 12, weight: .bold, design: .rounded)) }
                    }
                    .foregroundStyle(i == step || done ? Color.white : .secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(i == step ? Color.accentColor : done ? Palette.right : Palette.well))
                    Text(Self.titles[i]).font(.system(size: 12, weight: i == step ? .semibold : .regular))
                        .foregroundStyle(i == step ? tint : .secondary).lineLimit(1).fixedSize()
                }
                if i < Self.titles.count - 1 { Rectangle().fill(.quaternary).frame(height: 1).frame(maxWidth: .infinity).padding(.horizontal, 8) }
            }
        }
    }

    // MARK: Every paste step

    /// What to do and a picture of where, side by side; under them, what the paste gave.
    private func layout(_ title: some View, _ steps: [String], tint: Color, @ViewBuilder picture: () -> some View,
                        @ViewBuilder preview: () -> some View) -> some View {
        VStack(spacing: L.gap) {
            HStack(alignment: .top, spacing: L.gap) {
                VStack(alignment: .leading, spacing: 12) {
                    title.font(T.section)
                    ForEach(steps.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Circle().fill(tint))
                            Text(.init(steps[i])).font(T.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Open My Practice") { NSWorkspace.shared.open(URL(string: "https://mypractice.collegeboard.org/")!) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                picture()
                    .frame(width: 500).frame(maxHeight: .infinity)
                    .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
            }
            .frame(height: 270)
            VStack(alignment: .leading, spacing: 12) { preview() }
                .padding(L.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    private func pasteButton(_ again: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(again ? "Paste Again" : "Paste", systemImage: "doc.on.clipboard") }
            .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut("v").disabled(reading != nil)
    }

    /// "12 of 27 questions", gray until something was read.
    private func tally(_ have: Int, _ total: Int, _ unit: String = "questions") -> some View {
        Text("\(have) of \(total) \(unit)").font(T.section).monospacedDigit().foregroundStyle(have == 0 ? .secondary : .primary)
    }

    /// Numbered cells, one row per module: filled where `fill` gives a color, a blank well where the paste had nothing.
    /// With `current`, a filled cell opens its question.
    /// With `missing`, a blank cell takes the one question the student copied for it.
    private func grid(_ ms: [String], cell: CGFloat = 24, current: String? = nil, trailing: @escaping (String) -> String? = { _ in nil },
                      missing: ((String) -> Void)? = nil, fill: @escaping (String) -> Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ms, id: \.self) { m in
                HStack(spacing: cell > 20 ? 4 : 2) {
                    Text("\(Sec.short(Session.section(of: m))) \(m.suffix(1))").font(T.caption.weight(.semibold))
                        .foregroundStyle(Sec.color(Session.section(of: m))).frame(width: 52, alignment: .leading)
                    ForEach(1...Khan.expected(m), id: \.self) { n in
                        let k = "\(m)-\(n)", c = fill(k)
                        Button { if c == nil, let missing { missing(k) } else { open = k } } label: {
                            Text("\(n)").font(.system(size: cell > 20 ? 11 : 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(c == nil ? Color.secondary : .white)
                                .frame(width: cell, height: cell)
                                .background(c ?? Palette.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay { if k == current { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary, lineWidth: 2) } }
                        }
                        .buttonStyle(.plain).allowsHitTesting(current != nil && c != nil || missing != nil && c == nil)
                        .help(missing != nil && c == nil ? "Copy question \(n) on Khan Academy, then click here" : "")
                    }
                    if let t = trailing(m) { Spacer(minLength: 8); Text(t).font(T.caption).foregroundStyle(.secondary).monospacedDigit() }
                }
            }
        }
    }

    // MARK: Step 1: results

    @ViewBuilder private func results(_ problem: String?) -> some View {
        let steps = ["Open the test's **Score Details** in My Practice", "Pick **All Questions** and set **View:** to **All**",
                     "Turn on **Show Correct Answers**", "Press **⌘A**, then **⌘C**, then **Paste**"]
        layout(Label("Score Details", systemImage: "list.bullet.rectangle.portrait"), steps, tint: .accentColor) {
            ScoreDetailsSketch(test: test.isEmpty ? "SAT Practice" : test, width: 330)
        } preview: {
            HStack(spacing: L.gap) {
                if let o = record {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(test).font(T.section)
                        Text(date.formatted(date: .long, time: .omitted)).font(T.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    score(Sec.name("Reading and Writing"), Sec.color("Reading and Writing"), $rw)
                    score("Math", Sec.color(Sec.math), $math)
                    tally(o.answers.values.filter { Importer.isRight($0) == true }.count, o.answers.count, "right")
                        .padding(.leading, 8)
                } else if let failed {
                    Label(failed, systemImage: "exclamationmark.triangle.fill").font(T.body).foregroundStyle(Palette.wrong)
                    Spacer()
                } else {
                    tally(0, Importer.expected)
                    Spacer()
                }
                pasteButton(record != nil) { readResults() }
            }
            if let p = problem { Label(p, systemImage: "exclamationmark.triangle.fill").font(T.body).foregroundStyle(Palette.wrong) }
            if existing != nil {
                Label("Already in your tests: its answers will be added there", systemImage: "arrow.triangle.merge")
                    .font(T.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            grid(Khan.modules, trailing: { m in
                record.map { o in "\(o.answers.filter { $0.key.hasPrefix(m + "-") && Importer.isRight($0.value) == true }.count) right" }
            }) { k in record?.answers[k].map { Palette.fill(Importer.isRight($0)) } }
            Spacer(minLength: 0)
        }
    }

    private func score(_ title: String, _ color: Color, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(T.caption).foregroundStyle(color).lineLimit(1).fixedSize()
            TextField("", text: text, prompt: Text("–"))
                .textFieldStyle(.plain).font(T.value).monospacedDigit()
                .frame(width: 90, height: 34).padding(.horizontal, 10)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
        }
    }

    private func readResults() {
        let page = NSPasteboard.general.string(forType: .string) ?? ""
        guard let r = Self.results(page) else {
            let n = Self.heading(page) == nil ? 0 : Importer.parse(page).answers.count   // View: shows 10 rows unless set to All
            failed = n > 0 ? "Only \(n) questions found. Set View: to All and copy again." : "No test found in what you pasted"
            return
        }
        failed = nil
        test = r.test
        date = r.date
        if let t = r.o.readingWriting { rw = String(t) }
        if let t = r.o.math { math = String(t) }
        record = r.o
    }

    // MARK: Steps 2–5: one module each

    private func module(_ m: String) -> some View {
        let sec = Session.section(of: m), n = Session.parts(m + "-0").1, total = Khan.expected(m), have = count(m), ks = Set(keys)
        let steps = ["On **Score Details**, click **Practice on Khan Academy**",
                     "Open **\(KhanSketch.parts[Khan.modules.firstIndex(of: m)! + 1])** from the list on the left or with **Up\u{00A0}next:\u{00A0}article**",
                     "Press **⌘A**, then **⌘C**, then **Paste**"]
        return layout(Label { Text("\(Sec.name(sec)) · Module \(n)") } icon: { Image(systemName: Sec.icon(sec)) }.foregroundStyle(Sec.color(sec)),
                      steps, tint: Sec.color(sec)) {
            HStack(spacing: 10) {
                ScoreDetailsSketch(test: test.isEmpty ? "SAT Practice" : test, width: 224, khan: true)
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                KhanSketch(test: test.isEmpty ? "SAT Practice" : test, part: Khan.modules.firstIndex(of: m)! + 1, width: 222)
            }
        } preview: {
            HStack(spacing: 12) {
                if reading == m {
                    ProgressView().controlSize(.small)
                    Text("Reading the questions with \(Brain.name)…").font(T.body).foregroundStyle(.secondary)
                } else if missed.contains(m) {
                    Label("No questions found in what you pasted", systemImage: "exclamationmark.triangle.fill").font(T.body).foregroundStyle(Palette.wrong)
                } else {
                    if have > 0 {
                        Image(systemName: have == total ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(have == total ? Palette.right : .orange)
                    }
                    tally(have, total)
                }
                Spacer()
                figures((1...total).map { "\(m)-\($0)" }.filter { ks.contains($0) && found[$0].map(Khan.pictured) == true })
                pasteButton(have > 0) { readModule(m) }
            }
            grid([m], trailing: { _ in have > 0 && have < total && reading == nil ? "Missing one? Copy it alone, click its number" : nil },
                 missing: readOne) { ks.contains($0) ? Sec.color(sec) : nil }
            Divider().padding(.vertical, 4)
            if let q = (1...total).lazy.map({ "\(m)-\($0)" }).first(where: { ks.contains($0) }), let a = found[q] {
                firstQuestion(Session.parts(q).2, a)
            } else {
                firstQuestion(1, nil)
            }
            Spacer(minLength: 0)
        }
    }

    /// The first question read, as the review will show it: enough to see the paste worked. Without one, its outline.
    private func firstQuestion(_ n: Int, _ a: Official.Answer?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(a == nil ? Color.secondary : Palette.surface)
                .frame(width: 26, height: 26).background(a == nil ? Palette.well : Color.primary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            if let a = a.map(Khan.tidy) { VStack(alignment: .leading, spacing: 8) {
                if let s = a.skill { Text(s).font(T.caption).foregroundStyle(.secondary) }
                if let p = a.passage.map({ Figure.split($0).text }), !p.isEmpty { Practice.serif(p, size: 13, ink: .secondary).foregroundStyle(.secondary).lineLimit(2) }
                Practice.serif(a.question ?? "", size: 15).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let cs = a.choices {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: L.gap, alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 8) {
                        ForEach(cs.indices, id: \.self) { i in
                            HStack(spacing: 8) {
                                Text(Practice.letters.indices.contains(i) ? Practice.letters[i] : "\(i + 1)").font(.system(size: 11, weight: .semibold))
                                    .frame(width: 20, height: 20).overlay(Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1))
                                Practice.serif(cs[i], size: 14).lineLimit(1)
                            }
                        }
                    }
                }
            } } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([0.18, 0.5, 0.42], id: \.self) { w in Capsule().fill(Palette.well).frame(width: 760 * w, height: 9) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: L.gap, alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            HStack(spacing: 8) { Circle().strokeBorder(Palette.well, lineWidth: 1.5).frame(width: 20, height: 20); Capsule().fill(Palette.well).frame(width: 150, height: 9) }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// The questions on the page; when the page reading finds too few, the AI reads the rest.
    private func readModule(_ m: String) {
        guard let page = NSPasteboard.general.string(forType: .string), !page.isEmpty else { missed.insert(m); return }
        let total = Khan.expected(m)
        var qs = Khan.parse(page, max: total)
        put(m, qs)
        guard qs.count < total, Brain.ready else { return }
        reading = m
        Task {
            for (n, a) in await Khan.extract(page, max: total) where qs[n] == nil { qs[n] = a }
            put(m, qs)
            reading = nil
        }
    }

    /// One question copied on its own, read into the number the student clicked.
    private func readOne(_ k: String) {
        let m = String(k.prefix(2))
        guard let t = NSPasteboard.general.string(forType: .string), let a = Khan.one(t) else { missed.insert(m); return }
        found[k] = a
        missed.remove(m)
    }

    /// Questions whose graph is a picture: a tile each to paste a screenshot of it onto (the text has only its labels).
    @ViewBuilder private func figures(_ ks: [String]) -> some View {
        if !ks.isEmpty {
            HStack(spacing: 8) {
                Label("Graphs", systemImage: "chart.xyaxis.line").font(T.card).foregroundStyle(.secondary)
                ForEach(ks, id: \.self) { k in
                    Button { pastePicture(k) } label: {
                        HStack(spacing: 6) {
                            Text("\(Session.parts(k).2)").font(.system(size: 11, weight: .semibold, design: .rounded))
                            if let img = pictures[k] { Image(nsImage: img).resizable().scaledToFit().frame(height: 22).clipShape(RoundedRectangle(cornerRadius: 3)) }
                            else { Image(systemName: "photo.badge.plus") }
                        }
                        .padding(.horizontal, 8).frame(height: 30)
                        .background(Palette.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Copy a screenshot of question \(Session.parts(k).2)'s graph, then click here")
                }
            }
        }
    }

    private func pastePicture(_ k: String) {
        if let img = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage { pictures[k] = img }
    }

    /// A pasted picture of a question's graph, written like `Tutor.replaceImage`'s but named `_figure_`: the question
    /// keeps its official text and the card shows the picture above it.
    static func saveFigure(_ img: NSImage, _ sid: String, _ key: String) -> String? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = Capture.jpeg(cg) else { return nil }
        let name = "shots/\(key)_figure_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = Store.shared.dir(sid).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil ? name : nil
    }

    /// A new paste replaces what the module had.
    private func put(_ m: String, _ qs: [Int: Official.Answer]) {
        found = found.filter { !$0.key.hasPrefix(m + "-") }
        for (n, a) in qs { found["\(m)-\(n)"] = a }
        if qs.isEmpty { missed.insert(m) } else { missed.remove(m) }
    }

    // MARK: Step 6: review

    /// The result from Score Details with the question text from Khan Academy (`keys` has both).
    private func merged(_ k: String) -> Official.Answer {
        Khan.merge([k: found[k]!], into: Official(answers: [k: record!.answers[k]!])).answers[k]!
    }

    @ViewBuilder private var review: some View {
        let ks = keys, have = Set(ks)
        if let k = open.flatMap({ ks.contains($0) ? $0 : nil }) ?? ks.first {
            let a = merged(k)
            VStack(spacing: L.gap) {
                OfficialCard(a: Binding(get: { merged(k) }, set: { found[k] = $0 }), key: k, right: Importer.isRight(a), editable: true,
                             picture: pictures[k], pastePicture: { pastePicture(k) }).id(k)
                HStack(alignment: .top, spacing: L.gap) {
                    yours(k, a)
                    grid(Khan.modules.filter { m in ks.contains { $0.hasPrefix(m + "-") } }, cell: 20, current: k) {
                        have.contains($0) ? Palette.fill(record?.answers[$0].flatMap(Importer.isRight)) : nil
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ContentUnavailableView("No questions added", systemImage: "doc.text")
        }
    }

    /// What the student answered, kept on College Board's record (`yours`); filled already when Score Details showed it.
    private func yours(_ k: String, _ a: Official.Answer) -> some View {
        let pick = Binding(get: { record?.answers[k]?.yours ?? "" }, set: { record?.answers[k]?.yours = $0.isEmpty ? nil : $0 })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your answer").font(T.card)
            if a.choices?.isEmpty == false || Practice.letters.contains(a.correct) {
                HStack(spacing: 8) {
                    ForEach(Practice.letters, id: \.self) { l in
                        let on = pick.wrappedValue.uppercased() == l
                        Button { pick.wrappedValue = on ? "" : l } label: {
                            Text(l).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? Color.white : .primary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(on ? Color.accentColor : .clear))
                                .overlay(Circle().strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.6), lineWidth: 1.5))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                TextField("", text: pick, prompt: Text("Answer"))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(width: 120, height: 28).padding(.horizontal, 8)
                    .background(Palette.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    private func save(_ rw: Int?, _ math: Int?) {
        guard var o = record else { return }
        o = Khan.merge(found, into: o)
        if let rw, let math { o.readingWriting = rw; o.math = math; o.total = rw + math }
        let pics = { (sid: String) -> [String: String] in
            var out: [String: String] = [:]
            for (k, img) in pictures where o.answers[k] != nil { out[k] = Self.saveFigure(img, sid, k) }
            return out
        }
        if let s = existing {
            // question text logged before stays unless this log brought new text for it
            o = Khan.merge((s.official?.answers ?? [:]).filter { $0.value.question != nil && o.answers[$0.key]?.question == nil }, into: o)
            Importer.apply(o, to: s.id)
            let names = pics(s.id)
            store.update(s.id) { for (k, n) in names { $0.q[k, default: QState()].image = n } }
            if Brain.ready { for k in names.keys { Task { await Tutor.analyze(s.id, k) } } }
            store.nav = .session(s.id)
        } else {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HHmmss"
            let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())   // a unique id even for two logs on one day
            let start = Calendar.current.date(bySettingHour: now.hour ?? 12, minute: now.minute ?? 0, second: now.second ?? 0, of: date) ?? date
            var s = Session(id: f.string(from: start), start: start)
            s.end = start
            s.test = test
            s.official = o
            for (k, n) in pics(s.id) { s.q[k, default: QState()].image = n }
            store.save(s)
            store.nav = .session(s.id)
            if Settings.autoAnalyze, Brain.ready { Tutor.analyzeAll(s.id) }   // explain it straight away, like a tracked test
        }
        dismiss()
    }
}

// MARK: - Khan Academy questions

/// Reads the text of Khan Academy's page for one practice test module, copied with ⌘A ⌘C. Each question looks like
///   "Question 7 | Graphs of linear systems and inequalities", passage and question lines, "Choose 1 answer:",
///   then choices A to D, as "(Choice A)" / "A" / text lines or as "A (−14,0)". Grid-ins have no choices.
/// Page words (Check, Hint, Report a problem…) are dropped. The result holds question fields only.
enum Khan {
    static let modules = ["R1", "R2", "M1", "M2"]
    static func expected(_ module: String) -> Int { module.hasPrefix("R") ? 27 : 22 }

    private static let chrome: Set<String> = ["explain", "check", "hint", "get help", "report a problem", "show calculator", "hide calculator",
        "calculator", "reference", "skip", "try again", "show solution", "hide solution", "mark for review", "next question", "up next",
        "up next: article", "do 4 problems", "choose all answers that apply:", "stuck? review related articles/videos or use a hint."]

    static func parse(_ text: String, max: Int = 27) -> [Int: Official.Answer] {
        struct Block { var n: Int; var skill: String?; var body: [String] = []; var choices: [String] = []; var pending: Int?; var mc = false; var closed = false }
        let header = #/Question\s+(\d{1,2})(?:\s+of\s+\d{1,2})?(?:(?:\s*[|·:–—-]\s*|\t+)(.*))?/#.ignoresCase()
        let marker = #/\(?(?:Choice\s+)?([A-D])\)?[.:)]?/#           // a letter on its own line
        let inline = #/\(?(?:Choice\s+)?([A-D])\)?[.:)]?\s+(.+)/#    // "A (−14,0)", "B) 12"
        // the whole line: "a mixed number, like 1 3/4"; a passage's "A growing number, like the count of…" goes on
        let gridHelp = #/^an? (?:[a-z]+ )*(?:integer|fraction|decimal|number|pi), like [\d\s\/.π]*(?:pi)?(?: or [\d\s\/.]*pi)?$/#
        var out: [Int: Official.Answer] = [:]
        var b: Block?
        func flush() {
            guard let x = b, out[x.n] == nil else { return }
            // The question is the last line that isn't a graph's tick label; the labels stay in the passage for the tutor.
            let body = flow(Figure.clean(x.body)).map(\.text), labels = Figure.ticks(body)
            guard let qi = body.indices.last(where: { !labels.contains($0) }) else { return }
            let q = body[qi], passage = body.indices.filter { $0 != qi }.map { body[$0] }.joined(separator: "\n")
            out[x.n] = .init(correct: "", question: q, passage: passage.isEmpty ? nil : passage, choices: x.choices.isEmpty ? nil : x.choices,
                             skill: x.skill.flatMap { $0.isEmpty ? nil : $0 })
        }
        for raw in text.replacingOccurrences(of: "\u{00A0}", with: " ").components(separatedBy: .newlines) {
            // MathJax's \( \) and \[ \] delimiters become the $ $ the app sets as math; the LaTeX inside is kept as is.
            let line = ["\\(", "\\)", "\\[", "\\]"].reduce(raw.trimmingCharacters(in: .whitespaces)) { $0.replacingOccurrences(of: $1, with: "$") }
            let low = line.lowercased()
            if line.isEmpty { continue }
            if let m = line.wholeMatch(of: header) {
                flush()
                let n = Int(m.1)!
                b = (1...max).contains(n) ? Block(n: n, skill: m.2.map { $0.trimmingCharacters(in: .whitespaces) }) : nil
                continue
            }
            guard let x = b, !x.closed else { continue }
            if low.hasPrefix("choose 1 answer") || low.hasPrefix("choose an answer") { b?.mc = true; continue }
            // A grid-in's answer-format help ("an integer, like 6") or its Check button ends it; after the choices, so does any
            // page word. A passage's own ", like " is text.
            if low.hasPrefix("your answer should be") || !x.mc && low.contains(gridHelp) { if !x.body.isEmpty { b?.closed = true }; continue }
            if chrome.contains(low) { if x.mc && !x.choices.isEmpty || !x.mc && low == "check" && !x.body.isEmpty { b?.closed = true }; continue }
            if x.mc {
                let i: (Substring) -> Int = { Int($0.unicodeScalars.first!.value) - 65 }
                if let m = line.wholeMatch(of: marker) { if i(m.1) <= x.choices.count { b?.pending = i(m.1) }; continue }
                if let p = x.pending {   // the text after a letter; a repeat of a letter already read is the page's duplicate
                    if p == x.choices.count { b?.choices.append(line) }
                    b?.pending = nil
                } else if let m = line.wholeMatch(of: inline), i(m.1) == x.choices.count {
                    b?.choices.append(String(m.2))
                }
                if b!.choices.count == 4 && b!.pending == nil { b?.closed = true }
                continue
            }
            b?.body.append(line)
        }
        flush()
        return out
    }

    /// Khan's copy puts each inline math token on a line of its own ("A wire with a length of" / "$106$" / "inches is cut…").
    /// This flows them back into sentences: a math-only line joins the line before unless that line ends a sentence and the
    /// next doesn't go on from it (then it is a display equation); a line starting with punctuation or a lowercase word joins
    /// the line before. Text without such a math line is left alone, as are tick labels, table rows and \[…\] / $$…$$ lines.
    /// `end` is the last input line in each output line.
    static func flow(_ lines: [String]) -> [(text: String, end: Int)] {
        let t = lines.map { $0.trimmingCharacters(in: .whitespaces) }, labels = Figure.ticks(lines)
        let fixed = t.indices.map { labels.contains($0) || t[$0].contains("\t") || t[$0].contains(" | ") || t[$0].contains(#/\\\[|\$\$/#) }
        let token = t.indices.map { !fixed[$0] && t[$0].wholeMatch(of: #/\$[^$]+\$|\\\(.+\\\)/#) != nil }
        guard token.contains(true) else { return lines.indices.map { (lines[$0], $0) } }
        let goesOn = { (i: Int) in !fixed[i] && t[i].contains(#/^(?:[.,;:?!)\]}%'’]|[a-z]+\b(?!\s*[=<>≤≥+\-−(]))/#) }
        var out: [(text: String, end: Int)] = [], open = false   // open: the last line can take the next
        for i in t.indices {
            if t[i].isEmpty { out.append((lines[i], i)); continue }
            let next = (i + 1..<t.count).first { !t[$0].isEmpty }.map(goesOn) == true
            let last = out.last { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }?.text ?? ""
            let joins = open && (goesOn(i) || token[i] && (next || !".:?!".contains(last.trimmingCharacters(in: .whitespaces).last ?? ".")))
            if joins {
                while out.last?.text.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
                let tight = ".,;:?!)]}%'’".contains(t[i].first!) || last.hasSuffix("(")
                out[out.count - 1] = (last + (tight ? "" : " ") + t[i], i)
            } else { out.append((lines[i], i)) }
            open = !fixed[i] && (!token[i] || joins || next)
        }
        return out
    }

    /// A stored question as the card shows it, for text saved before `flow`: the math flowed back into sentences across the
    /// passage and the question, and a graph's tick labels moved out of the question into the passage (where they're hidden).
    static func tidy(_ a: Official.Answer) -> Official.Answer {
        let p = a.passage?.components(separatedBy: .newlines) ?? [], all = a.question?.components(separatedBy: .newlines) ?? []
        let labels = Figure.ticks(all), q = all.indices.filter { !labels.contains($0) }.map { all[$0] }
        guard q.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return a }
        let f = flow(p + q), cut = f.firstIndex { $0.end >= p.count } ?? f.count
        var b = a
        let passage = f[..<cut].map(\.text) + labels.map { all[$0] }
        b.passage = passage.isEmpty ? nil : passage.joined(separator: "\n")
        b.question = f[cut...].map(\.text).joined(separator: "\n")
        return b
    }

    /// A question with a graph the text can't draw exactly, so the student can paste a picture of it.
    static func pictured(_ a: Official.Answer) -> Bool {
        let t = tidy(a)
        return Figure.pictured(t.passage) || Figure.pictured(t.question)
    }

    /// One question copied on its own (for a number the page reading missed): its "Question N |" header is optional and its
    /// number is ignored, since the student pasted it onto the number they clicked.
    static func one(_ text: String) -> Official.Answer? {
        let q = parse(text, max: 99).sorted { $0.key < $1.key }.first?.value ?? parse("Question 1\n" + text, max: 1)[1]
        return q.flatMap { $0.choices != nil || $0.question?.contains("?") == true ? $0 : nil }   // page words alone are no question
    }

    /// Question text into College Board's record, by key. Only questions the record has are kept: an entry without
    /// a result would count as wrong.
    static func merge(_ qs: [String: Official.Answer], into o: Official) -> Official {
        var o = o
        for (k, q) in qs where q.question != nil && o.answers[k] != nil {
            o.answers[k]!.passage = q.passage
            o.answers[k]!.question = q.question
            o.answers[k]!.choices = q.choices
            if o.answers[k]!.skill == nil { o.answers[k]!.skill = q.skill }
        }
        return o
    }

    static var schema: [String: Any] {
        func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        func obj(_ p: [String: Any]) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "required": Array(p.keys).sorted(), "properties": p]
        }
        let q = obj(["number": s("question number"), "passage": s("the passage, table or notes the question is about, empty if none"),
                     "question": s("the question itself"), "skill": s("the skill named after the question number, empty if none"),
                     "choices": ["type": "array", "items": ["type": "string"], "description": "answer choices A to D without their letters; empty for a grid-in"]])
        return obj(["questions": ["type": "array", "items": q]])
    }

    private static let system = """
    You read text copied from a Khan Academy page that shows one module of an SAT practice test. Return every question \
    in it: its number, the passage it is about, the question, the four answer choices in order (none for a question the \
    student answers by typing a number), and the skill named next to the number. Copy the words and math exactly as \
    written; keep math as it appears, and use $…$ for any LaTeX. Leave out page words like Check, Hint or Report a problem. \
    Never invent a question that isn't in the text.
    """

    /// Used when `parse` finds fewer questions than the module has. Empty when the model gave back nothing usable.
    @MainActor static func extract(_ text: String, max: Int) async -> [Int: Official.Answer] {
        var out: [Int: Official.Answer] = [:]
        // shortcut: on-device chunks are cut at line breaks, not at questions; one cut in half comes back partial or not at all.
        for c in Brain.provider(for: .extract) != .apple ? [text] : Importer.chunk(text, 2500) {
            guard let reply = try? await Brain.send(task: .extract, system: system, messages: [["role": "user", "content": [["type": "text", "text": c]]]],
                                                    schema: schema, base: Store.shared.root, effort: "low"),
                  let j = (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any] else { continue }
            for q in j["questions"] as? [[String: Any]] ?? [] {
                func str(_ k: String) -> String? { (q[k] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
                guard let n = (q["number"] as? Int) ?? str("number").flatMap({ Int($0) }), (1...max).contains(n), out[n] == nil,
                      let stem = str("question") else { continue }
                let choices = (q["choices"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                out[n] = .init(correct: "", question: stem, passage: str("passage").map(Figure.clean), choices: choices.isEmpty ? nil : choices, skill: str("skill"))
            }
        }
        return out
    }
}

// MARK: - Khan Academy page sketch

/// A small drawing of Khan Academy's review of a practice test: the parts listed on the left with the one to copy
/// ringed, and the Up next button that moves to the next part.
struct KhanSketch: View {
    static let parts = ["Reviewing your SAT practice test", "Reading and Writing - Part 1", "Reading and Writing - Part 2",
                        "Math - Part 1", "Math - Part 2"]
    var test = "SAT Practice"
    var part = 1
    var width: CGFloat = 240
    private let blue = Color(red: 0x18 / 255, green: 0x65 / 255, blue: 0xf2 / 255)
    private var k: CGFloat { width / 240 }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2 * k) {
                Text(test).font(.system(size: 8 * k, weight: .bold)).padding(.horizontal, 6 * k).padding(.bottom, 4 * k)
                ForEach(Self.parts.indices, id: \.self) { i in
                    Text(Self.parts[i]).font(.system(size: 6.5 * k, weight: i == part ? .semibold : .regular)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6 * k).padding(.vertical, 4 * k)
                        .background(i == part ? blue.opacity(0.12) : .clear)
                        .overlay(alignment: .leading) { if i == part { Rectangle().fill(blue).frame(width: 2 * k) } }
                        .ring(i == part, k, around: -1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8 * k).frame(width: 96 * k)
            Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 5 * k) {
                Text("Question 1").font(.system(size: 7 * k, weight: .semibold))
                ForEach([1, 0.92, 0.97, 0.6], id: \.self) { w in
                    Capsule().fill(Color.gray.opacity(0.25)).frame(width: 110 * k * w, height: 3 * k)
                }
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2 * k).strokeBorder(Color.gray.opacity(0.4), lineWidth: 0.75).frame(width: 110 * k, height: 9 * k)
                }
                Spacer(minLength: 0)
                Text("Up next: article").font(.system(size: 6.5 * k, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6 * k).padding(.vertical, 4 * k)
                    .background(blue, in: RoundedRectangle(cornerRadius: 3 * k)).ring(true, k)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(10 * k)
        }
        .foregroundStyle(.black)
        .frame(width: width, height: 150 * k)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityLabel("\(Self.parts[part]) in the list on Khan Academy")
    }
}

// MARK: - Bluebook-like card

/// An official question set out like Bluebook: passage on the left in the test's serif, the question and lettered choices
/// on the right (Math has no passage column). College Board's result is marked: the correct letter green, a wrong pick red.
/// With `editable`, a click on any field turns it into a text field.
struct OfficialCard: View {
    @Binding var a: Official.Answer
    let key: String
    var right: Bool?
    var editable = false
    var picture: NSImage?                 // the student's picture of a graph the text can't rebuild
    var pastePicture: (() -> Void)?       // with it, such a graph without a picture shows where to paste one
    private var shown: Official.Answer { Khan.tidy(a) }   // text saved before Khan.flow shows flowed too; an edit saves it so

    var body: some View {
        let math = Session.section(of: key) == Sec.math
        HStack(spacing: 0) {
            if !math {
                ScrollView { VStack(spacing: 20) { passage(15, figureFirst: true) }.lineSpacing(4).padding(20) }
                    .frame(maxWidth: .infinity)
                Divider()
            }
            ScrollView { side(math) }.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: L.inner, style: .continuous))
    }

    private func side(_ math: Bool) -> some View {
        let (_, _, n) = Session.parts(key)
        let correct = Practice.letters.contains(a.correct) ? a.correct : nil
        let mine = a.yours.map { $0.uppercased() }.flatMap { Practice.letters.contains($0) ? $0 : nil }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(n)").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.surface)
                    .frame(width: 30, height: 30).background(Color.primary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Field(text: text(\.skill), size: 12, serif: false, editable: editable).foregroundStyle(.secondary)
                if let right {
                    Label(right ? "Right" : "Wrong", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(T.card).foregroundStyle(right ? Palette.right : Palette.wrong).fixedSize()
                }
            }
            .padding(4).padding(.trailing, 6)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if math, shown.passage != nil { passage(16, figureFirst: false, drawn: true) }
            Field(text: text(\.question), size: 16, editable: editable)
            if let cs = a.choices, !cs.isEmpty {
                ForEach(0..<Swift.max(4, cs.count), id: \.self) { i in
                    let letter = Practice.letters.indices.contains(i) ? Practice.letters[i] : "\(i + 1)"
                    choice(letter, i, letter == correct ? Palette.right : letter == mine && right == false ? Palette.wrong : nil)
                }
            } else if !a.correct.isEmpty {   // a grid-in: the answers as numbers
                HStack(spacing: 8) {
                    Text("Correct").foregroundStyle(.secondary)
                    Text(a.correct).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Palette.right)
                    if right == false {
                        Text("You answered").foregroundStyle(.secondary).padding(.leading, L.inner)
                        Text(a.yours ?? "—").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Palette.wrong)
                    }
                }
                .font(.system(size: 13.5, weight: .medium))
            }
        }
        .padding(20)
    }

    /// A choice row as in Bluebook: letter circle and text; filled green for the answer, red for a wrong pick.
    private func choice(_ letter: String, _ i: Int, _ tint: Color?) -> some View {
        HStack(spacing: 12) {
            Text(letter).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint == nil ? Color.primary : .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint ?? .clear))
                .overlay(Circle().strokeBorder(tint ?? Color.primary.opacity(0.6), lineWidth: 1.5))
            Field(text: Binding(get: { a.choices?.indices.contains(i) == true ? a.choices![i] : "" }, set: { v in
                var cs = a.choices ?? []
                while cs.count <= i { cs.append("") }
                cs[i] = v
                a.choices = cs
            }), size: 15, editable: editable)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: L.inner, style: .continuous).strokeBorder(tint ?? Color.secondary.opacity(0.45), lineWidth: tint == nil ? 1 : 2))
    }

    /// The passage with Khan's description of a graph or table drawn as the figure: above it in Reading and Writing, below
    /// it in Math (then the question), as Bluebook sets them. The stored text keeps the description (the tutor reads it);
    /// an edit changes only the words shown.
    @ViewBuilder private func passage(_ size: CGFloat, figureFirst: Bool, drawn: Bool = true) -> some View {
        let p = Figure.split(shown.passage ?? "")
        if figureFirst && drawn { figure(p.figure) }
        if !p.text.isEmpty || editable {
            Field(text: Binding(get: { p.text }, set: { v in
                let s = [p.source, v].filter { !$0.isEmpty }.joined(separator: "\n")
                var b = shown
                b.passage = s.isEmpty ? nil : s
                a = b
            }), size: size, editable: editable)
        }
        if !figureFirst && drawn { figure(p.figure) }
    }

    @ViewBuilder private func figure(_ f: Figure?) -> some View {
        if let f { FigureView(f: f) }
        if let picture {
            Image(nsImage: picture).resizable().scaledToFit().frame(maxWidth: 520, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).frame(maxWidth: .infinity)
        } else if let pastePicture, Khan.pictured(a) {
            Button(action: pastePicture) { Label("Paste Picture of the Graph", systemImage: "photo.badge.plus").frame(maxWidth: .infinity, minHeight: 120) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help("Copy a screenshot of the graph on Khan Academy, then click here")
        }
    }

    private func text(_ path: WritableKeyPath<Official.Answer, String?>) -> Binding<String> {
        Binding(get: { shown[keyPath: path] ?? "" }, set: { var b = shown; b[keyPath: path] = $0.isEmpty ? nil : $0; a = b })
    }
}

/// Text in the test's serif (math through `Rich`); when editable, a click turns it into a field and Return or a click away ends it.
private struct Field: View {
    @Binding var text: String
    var size: CGFloat
    var serif = true
    var editable = false
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(serif ? .custom("STIX Two Text", size: size) : .system(size: size))
                .focused($focused)
                .onAppear { focused = true }
                .onChange(of: focused) { if !focused { editing = false } }
                .onSubmit { editing = false }
                .padding(6)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Group {
                if text.isEmpty { Text(editable ? "—" : "").font(.system(size: size)).foregroundStyle(.tertiary) }
                else if serif { Practice.serif(text, size: size) }
                else { Text(text).font(.system(size: size)) }
            }
            .lineSpacing(4)   // the same leading as the passage, for the question and choices too
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if editable { editing = true } }
            .pointerStyle(editable ? .horizontalText : nil)
        }
    }
}
