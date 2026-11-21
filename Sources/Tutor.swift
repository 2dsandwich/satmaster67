import AppKit
import ImageIO
import Security

/// The Anthropic API key lives in the login Keychain, in this app's own item only.
enum Keychain {
    static let service = "dev.masashik.sattracker", account = "anthropic-api-key"

    /// Test runs (SAT_DATA set) never touch the keychain, so they can't trigger a password prompt.
    static let testing = ProcessInfo.processInfo.environment["SAT_DATA"] != nil

    static func get(service: String = service) -> String? {
        if testing { return nil }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Raw HTTPS Messages API client (Swift has no official Anthropic SDK).
enum Claude {
    static let model = "claude-opus-5-5"
    private static var cached: String??

    static var apiKey: String? {
        if let e = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !e.isEmpty { return e }
        if let cached { return cached }
        let k = Keychain.get()   // only our own item: reading another app's item makes macOS ask for a password
        cached = .some(k)
        return k
    }

    static func setKey(_ key: String?) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(k)
        cached = .some(k?.isEmpty == false ? k : nil)
    }

    static var hasKey: Bool { !(apiKey ?? "").isEmpty }

    enum Failure: LocalizedError {
        case noKey, http(Int, String), refused, cutOff, empty
        var errorDescription: String? {
            switch self {
            case .noKey: "Add a Claude API key in Settings."
            case .http(let code, let msg): "Claude error \(code): \(msg)"
            case .refused: "Claude declined this question."
            case .cutOff: "The answer was too long and got cut off."
            case .empty: "Claude sent back nothing."
            }
        }
    }

    /// Images are stored in messages as {"type":"image","local_path":"shots/…"} and swapped
    /// for base64 only when sending, so saved history stays small and replays byte-for-byte.
    static func body(system: String, messages: [[String: Any]], schema: [String: Any]?, base: URL, effort: String = "high") throws -> [String: Any] {
        let resolved: [[String: Any]] = try messages.map { m in
            guard let parts = m["content"] as? [[String: Any]] else { return m }
            var out = m
            out["content"] = try parts.map { p -> [String: Any] in
                guard let path = p["local_path"] as? String else { return p }
                let data = try Data(contentsOf: base.appendingPathComponent(path))
                return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
            }
            return out
        }
        var output: [String: Any] = ["effort": effort]
        if let schema { output["format"] = ["type": "json_schema", "schema": schema] }
        return ["model": model, "max_tokens": 16000, "system": system, "messages": resolved,
                "thinking": ["type": "adaptive"], "output_config": output,
                "fallbacks": "default"]   // a safety-classifier decline is retried server-side on another model
    }

    /// Returns the assistant's raw content blocks (kept for follow-ups) and its text.
    static func send(system: String, messages: [[String: Any]], schema: [String: Any]? = nil, base: URL, effort: String = "high") async throws -> (content: [[String: Any]], text: String) {
        guard let key = apiKey, !key.isEmpty else { throw Failure.noKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body(system: system, messages: messages, schema: schema, base: base, effort: effort))
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(status, ((json["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data, as: UTF8.self))
        }
        switch json["stop_reason"] as? String {
        case "refusal": throw Failure.refused
        case "max_tokens": throw Failure.cutOff
        default: break
        }
        let content = json["content"] as? [[String: Any]] ?? []
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw Failure.empty }
        return (content, text)
    }
}

/// Explains each question in plain English for a student who learned math in another language.
@MainActor enum Tutor {
    static let system = """
    You are a calm, precise SAT tutor. The student knows the math well but learned it in another language, so English \
    math vocabulary and the SAT's way of phrasing questions slow them down. You get a screenshot of one practice question \
    as the student left it (usually from College Board's Bluebook app; the chosen answer is highlighted or typed in the \
    answer box), plus the time they spent and the target pace.

    Solve the question yourself and check your answer carefully. Then read the screenshot to find what the student chose. \
    Bluebook shows choices the student eliminated with a line through them; if they crossed out the correct answer, say so. \
    Write in plain, simple English: short sentences (under 20 words), common words. No praise, no filler. \
    Advice must hold on any test: never say "tomorrow", "today" or "on test day", and don't refer to dates. \
    Titles never end with a period; every sentence does.

    Every field has one job. Say each fact once across all fields: if the key point names the clue, the steps use it \
    without repeating it, and "Reading the question" stays empty unless the question's own wording is the trap. \
    The screen already shows the student's answer, the correct answer, crossed-out choices and the time, so never \
    restate them ("You chose A", "C is correct", "you crossed out C"); explain why instead. \
    If the screenshot doesn't show a question (for example a directions page), say so in question_en and set verdict to "unclear".

    Formatting, so the student can see what you're pointing at: put words quoted from the passage, question or choices \
    in double quotes; write every bit of math between $ signs in simple LaTeX ($x^2$, $\\frac{24}{n}$, $\\sqrt{x}$, $\\le$, \
    $\\cdot$, $\\pi$); mark at most one key term per field with **double asterisks**. No other markup.
    """

    static let schema: [String: Any] = {
        func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        func e(_ v: [String]) -> [String: Any] { ["type": "string", "enum": v] }
        let props: [String: Any] = [
            "question_en": s("The question and answer choices as written, in plain text (math as plain text like x^2)."),
            "topic": e(["Algebra", "Advanced Math", "Problem-Solving and Data Analysis", "Geometry and Trigonometry",
                        "Craft and Structure", "Information and Ideas", "Standard English Conventions", "Expression of Ideas", "Other"]),
            "skill": s("The specific SAT skill, e.g. 'Linear equations in two variables'."),
            "difficulty": e(["Easy", "Medium", "Hard"]),
            "correct_answer": s("The correct choice letter or value only, e.g. 'C' or '24'."),
            "student_answer": s("The letter or value the student chose, or 'none'. If they crossed out choices, add them in parentheses: 'A (crossed out C, D)'. Nothing else."),
            "key_point": s("One rule that would still be true on a different question of this type, so the student can reuse it. Don't use the correct choice's words or this passage's names or topic. If the rule only holds under a condition, state the condition. One sentence, max 14 words. Example: 'A blank after \"this\" repeats the idea of the sentence before it.'"),
            "verdict": e(["correct", "wrong", "unanswered", "unclear"]),
            "solution": s("2 to 4 steps, each on its own line starting with its number ('1.'), shortest reliable method; each step is a new action and the last one ends with the deciding value or fact. Never write the answer letter, 'The answer is', or anything about crossed-out choices. Don't repeat the key point."),
            "wording": s("Empty string unless a specific word or phrase in the question line itself (not the passage) caused the mistake, such as NOT, EXCEPT, 'most logically' or 'the value of': then that phrase and what it asks, one line, not repeating the key point."),
            "trap": s("If the student chose a wrong answer: why that choice fails, in one or two sentences about its flaw. If they left it blank: the trap that catches students, without saying they chose anything. If right: the trap that catches others, or empty string. Never invent a choice the student didn't make; don't say which choice they picked or crossed out."),
            "time_note": s("One short sentence: the time spent against the target pace. A fact only, no advice."),
            "mistake_cause": e(["none", "misread", "vocabulary", "grammar", "calculation", "concept", "time", "guess"]),
            "coach_line": s("A habit for next time that works on other questions too. One imperative sentence, max 15 words, said to the student. Share no content word with the key point. If the habit is a check, say what to do for each outcome."),
            "desmos": ["type": "array", "items": ["type": "string"], "description": "Math only, and only when graphing is how a strong SAT student would actually solve or check this question in Bluebook's Desmos: a system of equations or inequalities (read the intersection or shaded region), zeros/x-intercepts, a vertex or maximum/minimum, comparing two graphs, a regression on given data, or an equation that is messy by hand (graph both sides and read the intersection). Otherwise an empty array: never for one-step algebra, arithmetic, percentages, ratios, geometry or trig facts, statistics, probability, or word problems that only need a computed number. Give only the 1 to 3 expressions that matter, in Desmos LaTeX, e.g. 'y=x^{2}-4x+3', 'y=2x+1', 'y\\le x+7', data lists 'x_{1}=[1,2,3]', 'y_{1}=[2,5,9]' with 'y_{1}\\sim ax_{1}+b'. No points for answer choices and no axis lines like 'x=0'."],
            "desmos_focus": s("Only when desmos is not empty: the one point on those graphs where the answer is read (an intersection, an x-intercept, a vertex), as an ordered pair with numbers, e.g. '(14,0)'. It must lie on the graphed expressions. Empty string otherwise."),
            "key_phrase": s("The few English words on screen that decide this question (copied exactly as shown, max 8 words), e.g. 'the value of 6x - 4'."),
            "vocab": ["type": "array", "description": "At most 4 words or phrases from the passage or choices that are rarer than everyday school English and that a strong student reading in a second language may not know. For Reading and Writing questions whose answer choices are single words or short phrases, list every one of those choices first (all four), then at most 2 other hard words from the passage. Otherwise at most 4 words. For Math questions, list only math words and math phrasing (for example \"y-intercept\", \"reciprocal\", \"in terms of\", \"at most\"), never the story words of a word problem. Never include single letters, numbers or test instructions. The meaning must not reuse the word itself. Return an empty array rather than pad.",
                      "items": ["type": "object", "additionalProperties": false, "required": ["term", "meaning"],
                                "properties": ["term": s("The term as it appears"), "meaning": s("What it means, in a few plain words")]]],
        ]
        return ["type": "object", "additionalProperties": false, "required": Array(props.keys).sorted(), "properties": props]
    }()

    /// Stored names predate the English review (solutionJa, …); the API's names are mapped onto them so old tests still load.
    static let storedNames = ["solution": "solution_ja", "wording": "wording_ja", "trap": "trap_ja", "time_note": "time_ja",
                              "headline": "headline_ja", "summary": "summary_ja", "praise": "praise_ja",
                              "title": "title_ja", "why": "why_ja", "drill": "drill_ja", "term": "en", "meaning": "note"]

    /// Model text sometimes carries control characters or a dangling "e.g.,"; strip them before anything is stored.
    /// Titles never end with a period; sentences always end with one (or ? / !).
    static let titleKeys: Set<String> = ["title_ja"]
    static let sentenceKeys: Set<String> = ["pacing", "goal", "key_point", "trap_ja", "coach_line", "why_ja", "drill_ja", "summary_ja", "praise_ja", "headline_ja", "time_ja"]
    static func clean(_ t: String, title: Bool = false, sentence: Bool = false) -> String {
        var s = String(t.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
        s = s.replacingOccurrences(of: #"\s*\(?e\.g\.,?\)?\s*$"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        if title { while s.hasSuffix(".") { s.removeLast() } }
        if sentence, let last = s.last, !".?!:\"”')".contains(last) { s += "." }
        return s
    }

    static func stored(_ text: String) throws -> Data {
        func walk(_ v: Any) -> Any {
            if let a = v as? [Any] {   // vocab: drop blank, one-letter or numeric terms
                return a.map(walk).filter { e in
                    guard let term = (e as? [String: Any])?["en"] as? String else { return true }
                    let t = term.trimmingCharacters(in: .whitespaces)
                    return t.count > 1 && Double(t) == nil
                }
            }
            guard var o = v as? [String: Any] else { return v }
            for (new, old) in storedNames { if let x = o.removeValue(forKey: new) { o[old] = x } }
            for (k, v) in o { if let t = v as? String { o[k] = clean(t, title: titleKeys.contains(k), sentence: sentenceKeys.contains(k)) } }
            if o["en"] != nil { o["ja"] = "" }                       // vocab: no translation any more
            if o["question_en"] != nil { o["question_ja"] = "" }
            return o.mapValues(walk)
        }
        return try JSONSerialization.data(withJSONObject: walk(try JSONSerialization.jsonObject(with: Data(text.utf8))))
    }

    static func context(_ s: Session, _ key: String) -> String {
        let st = s.q[key] ?? QState()
        var lines = ["Section: \(s.section). \(s.label(key)).",
                     s.logged ? "Logged by hand after the test: there is no timing. Leave time_note empty and don't guess the time."
                              : "Time spent: \(Int(s.seconds(key))) s over \(s.visitCount(key)) visit(s). Target pace: \(Int(s.pace)) s per question."]
        if let o = s.official?.answers[key], o.correct.isEmpty, let r = o.right {   // result only, no letters on the page
            lines.append("Official College Board record: the student got this " + (r ? "RIGHT. Set verdict to \"correct\"." : "WRONG. Set verdict to \"wrong\".") + " This is final."
                         + " The answer key isn't on the page: solve the question and set correct_answer to the letter (or the value for a grid-in).")
            if let y = o.yours, !y.isEmpty { lines.append("The student says they answered \(y)." + (r ? " That is the correct answer." : "")) }
            if let d = o.domain { lines.append("Domain: \(d).") }
        } else if let o = s.official?.answers[key] {   // College Board's own record: the explanation must agree with it
            lines.append("Official College Board record: correct answer \(o.correct); the student answered \(o.yours ?? "nothing (omitted)"). "
                         + "This is final. Set correct_answer and student_answer to these and the verdict accordingly.")
            if let e = o.explanation { lines.append("College Board's explanation (use it, don't contradict it):\n\(e)") }
        }
        if let o = s.official?.answers[key], let q = o.question {
            let choices = zip(Practice.letters, o.choices ?? []).map { "\($0). \($1)" }
            lines.append("Official question text:\n" + ([o.passage, q].compactMap { $0 } + choices).joined(separator: "\n\n"))
        }
        if s.official?.answers[key].map({ $0.right == false && ($0.yours ?? "").isEmpty && !$0.correct.isEmpty }) == true || st.analysis?.studentAnswer.lowercased() == "none" {
            lines.append("The student left this question blank (no answer). Don't invent a chosen option; mistake_cause is \"time\" unless the screen shows otherwise.")
        }
        if st.image != nil { lines.append("The picture was added after the test from another site: it shows the question but not the student's choice.") }
        if st.guessed { lines.append("The student marked this as a guess.") }
        if !st.reasons.isEmpty { lines.append("The student says why they missed it: \(st.reasons.joined(separator: ", ")). Take that as true.") }
        if let m = st.memo, !m.isEmpty { lines.append("The student's own note on this question: \(m)") }
        if st.flagged { lines.append("The student flagged this question.") }
        if let m = st.mark {   // checked by the student against the official answer key: final
            lines.append(m ? "Checked against the official answer key: the student got this RIGHT. Set verdict to \"correct\"."
                           : "Checked against the official answer key: the student got this WRONG, even if their choice looks right to you. "
                             + "Set verdict to \"wrong\", re-solve carefully to find the correct answer, and explain what led the student astray.")
        }
        return lines.joined(separator: "\n")
    }

    static let snake: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()

    static func analyze(_ sid: String, _ key: String) async {
        let store = Store.shared
        guard let full = store.session(sid), full.explainable(key) else { return }
        let shot = full.shot(key)   // nil for a logged test: the official question text is all there is
        let s = full.only(Session.section(of: key))
        let tag = "\(sid)/\(key)"
        guard !store.busy.contains(tag) else { return }
        store.busy.insert(tag)
        defer { store.busy.remove(tag) }
        let url = shot.map { store.dir(sid).appendingPathComponent($0) }
        var ctx = context(s, key)
        if shot == nil { ctx += "\nThere is no screenshot: the question is the official text above." }
        let brain = Brain.provider(for: .explain)
        // A redo by a text-only tutor keeps the grade an earlier tutor made from the screenshot, and explains toward it.
        let prior = full.q[key]?.analysis.flatMap { $0.verdict == "unclear" ? nil : $0 }
        if let p = prior, s.official?.answers[key] == nil, !brain.seesImages {
            ctx += "\nAn earlier check that could see the screen found: correct answer \(p.correctAnswer), the student chose \(p.studentAnswer). Explain toward that answer."
        }
        var parts: [[String: Any]] = []
        if brain.seesImages, let shot { parts.append(["type": "image", "local_path": shot]) }
        else if s.official?.answers[key]?.question == nil, let url {
            // A text-only tutor reads the screenshot's words instead (on-device OCR).
            let words = await Task.detached { () -> String in
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "" }
                return Capture.read(img)
            }.value
            ctx += "\nText on the screen (OCR, may contain errors; the student's choice can't be seen):\n" + String(words.prefix(3500))
        }
        parts.append(["type": "text", "text": ctx])
        let first: [String: Any] = ["role": "user", "content": parts]
        do {
            let text = try await Brain.send(task: .explain, system: system + "\n\nWhat you know about the student:\n" + Student.brief(), messages: [first], schema: schema, base: store.dir(sid))
            var a = try snake.decode(Analysis.self, from: stored(text))
            // Apple's model sometimes fills the schema with blanks; keep the old explanation rather than store nothing.
            if a.solutionJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw Provider.Failure.empty(brain) }
            // Right and wrong never come from the AI when better sources exist; Apple's model never grades at all.
            if let o = s.official?.answers[key], o.correct.isEmpty, let r = o.right {
                a.verdict = r ? "correct" : "wrong"
            } else if let o = s.official?.answers[key] {
                a.correctAnswer = o.correct
                a.studentAnswer = o.yours ?? "none"
                a.verdict = Session.same(o.yours, o.correct) ? "correct" : o.yours == nil ? "unanswered" : "wrong"
            } else if !brain.seesImages {
                a.verdict = prior?.verdict ?? "unclear"
                if let p = prior { a.correctAnswer = p.correctAnswer; a.studentAnswer = p.studentAnswer }
            }
            let convo = try JSONSerialization.data(withJSONObject: [first, ["role": "assistant", "content": [["type": "text", "text": text]]]])
            let box = await Task.detached { () -> [Double]? in
                guard let p = a.keyPhrase, let url, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
                return Capture.find(p, in: img)
            }.value
            store.update(sid) {
                $0.q[key, default: QState()].analysis = a
                $0.q[key]!.convo = convo; $0.q[key]!.error = nil; $0.q[key]!.highlight = box
            }
        } catch {
            store.update(sid) { $0.q[key, default: QState()].error = error.localizedDescription }
        }
    }

    /// The student's right/wrong beats Claude's. When they disagree, re-explain that question as marked, then redo the debrief.
    static func mark(_ sid: String, _ key: String, _ value: Bool?) {
        let store = Store.shared
        store.update(sid) { $0.q[key, default: QState()].mark = value }
        guard let v = value, let s = store.session(sid), s.explainable(key), Brain.ready else { return }
        if let verdict = s.q[key]?.analysis?.verdict, (verdict == "correct") == v { return }
        Task {
            await analyze(sid, key)
            redebrief(sid, Session.section(of: key))
        }
    }

    /// The student's own picture of the question (the tracker's was wrong or missing). Old analysis stays until the new one lands.
    static func replaceImage(_ sid: String, _ key: String, _ image: NSImage) {
        let store = Store.shared
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = Capture.jpeg(cg) else { return }
        let name = "shots/\(key)_own_\(Int(Date().timeIntervalSince1970)).jpg"   // new name each time: ZoomedShot caches by URL
        let url = store.dir(sid).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        store.update(sid) { $0.q[key, default: QState()].image = name; $0.q[key]!.highlight = nil; $0.q[key]!.error = nil }
        guard Brain.ready else { return }
        Task {
            await analyze(sid, key)
            if Brain.provider(for: .debrief) != .apple { redebrief(sid, Session.section(of: key)) }   // the on-device debrief is weaker than the one it would replace
        }
    }

    /// Every explanation and debrief again (for example after the switch to English); marks and grades stay.
    /// The old explanation stays on screen until its replacement arrives.
    static func redo(_ sid: String) async {
        Store.shared.update(sid) { s in
            for k in s.q.keys { s.q[k]!.convo = nil; s.q[k]!.chat = []; s.q[k]!.highlight = nil; s.q[k]!.error = nil }
            s.debriefs = [:]
        }
        guard let s = Store.shared.session(sid) else { return }
        await explain(sid, s.keys.filter { s.explainable($0) })
    }

    /// Explains the given questions four at a time, then the debriefs, publishing progress for the loading screen.
    static func explain(_ sid: String, _ todo: [String]) async {
        let store = Store.shared
        store.progress[sid] = .init(done: 0, total: todo.count)
        defer { store.progress[sid] = nil }
        await withTaskGroup(of: Void.self) { g in
            for (i, k) in todo.enumerated() {
                if i >= 4 { await g.next(); store.progress[sid]?.done += 1 }
                g.addTask { await analyze(sid, k) }
            }
            while await g.next() != nil { store.progress[sid]?.done += 1 }
        }
        for sec in store.session(sid)?.sections ?? [] { await debrief(sid, sec) }
    }

    /// After official answers arrive: re-explain only the questions whose verdict disagrees, then redo the debriefs.
    static func reconcile(_ sid: String) {
        guard let s = Store.shared.session(sid), let o = s.official, Brain.ready else { return }
        let changed = o.answers.keys.filter { k in
            guard let a = s.q[k]?.analysis else { return s.explainable(k) }
            let c = o.answers[k]!.correct
            return (!c.isEmpty && a.correctAnswer != c) || (a.verdict == "correct") != (s.correct(k) == true)
        }
        Task {
            await withTaskGroup(of: Void.self) { g in
                for (i, k) in changed.enumerated() {
                    if i >= 4 { await g.next() }
                    g.addTask { await analyze(sid, k) }
                }
            }
            for sec in Store.shared.session(sid)?.sections ?? [] { redebrief(sid, sec) }
        }
    }

    private static var pending: Set<String> = []
    /// Marks often come in a burst: a debrief already running gets one rerun at the end, not one per mark.
    static func redebrief(_ sid: String, _ sec: String) {
        let tag = "\(sid)/debrief-\(sec)"
        if Store.shared.busy.contains(tag) { pending.insert(tag); return }
        Task {
            await debrief(sid, sec)
            if pending.remove(tag) != nil { redebrief(sid, sec) }
        }
    }

    /// Every question with a screenshot or official text and no analysis yet, four at a time.
    static func analyzeAll(_ sid: String) {
        guard let s = Store.shared.session(sid) else { return }
        let todo = s.keys.filter { s.q[$0]?.analysis == nil && s.explainable($0) }
        Task { await explain(sid, todo) }
    }

    static let debriefSchema: [String: Any] = {
        func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        let fix: [String: Any] = [
            "cause": ["type": "string", "enum": ["misread", "vocabulary", "calculation", "concept", "time", "guess"]],
            "title": s("The fix as a short instruction, max 6 words."),
            "why": s("One short sentence: the evidence from this test."),
            "drill": s("One concrete practice task (what to do and how many), one short sentence that works for any test. Not a fact to remember, and no 'tomorrow'."),
            "questions": ["type": "array", "items": ["type": "string"], "description": "Labels of the questions this comes from, exactly as given (e.g. 'Q7')."],
        ]
        let props: [String: Any] = [
            "headline": s("The single most important takeaway, said to the student, max 12 words."),
            "summary": s("Two short sentences, like a coach talking face to face: where the points went and why."),
            "praise": s("One specific thing that went well. Concrete, not generic."),
            "pacing": s("One or two sentences on how the time went across the modules, with the evidence from the FACT lines (time used, slow or rushed questions); what to change."),
            "goal": s("One measurable goal for the next practice test in this section, e.g. 'Miss no more than 2 Words in Context questions.'"),
            "fixes": ["type": "array", "description": "The three changes that would gain the most points, most valuable first.",
                      "items": ["type": "object", "additionalProperties": false, "required": Array(fix.keys).sorted(), "properties": fix]],
        ]
        return ["type": "object", "additionalProperties": false, "required": Array(props.keys).sorted(), "properties": props]
    }()

    /// One text-only call over every analysed question: headline, praise, three fixes.
    static func debrief(_ sid: String, _ sec: String) async {
        let store = Store.shared
        guard let s = store.session(sid)?.only(sec), s.keys.contains(where: { s.q[$0]?.analysis != nil }) else { return }
        let tag = "\(sid)/debrief-\(sec)"
        guard !store.busy.contains(tag) else { return }
        store.busy.insert(tag)
        defer { store.busy.remove(tag) }
        var lines = [s.logged ? "Section: \(s.section). Logged by hand after the test: there is no timing. Leave pacing empty and never mention time."
                              : "Section: \(s.section). Target pace \(Int(s.pace)) s per question. Total \(Int(s.studyTime)) s."]
        for m in s.modules {   // facts the review must match exactly
            let ks = s.keys(m), limit = Int(Sec.limit(s.section)), used = Int(s.used(m))
            let blank = ks.filter { s.q[$0]?.analysis?.studentAnswer.lowercased() == "none" }.map { s.label($0) }
            let time = s.logged ? "" : "; time used \(used) s of \(limit) s\(used >= limit - 5 ? " (ran out of time)" : "")"
            lines.append("FACT Module \(m): \(ks.filter { s.correct($0) == true }.count) of \(ks.count) right\(time); blank: \(blank.isEmpty ? "none" : blank.joined(separator: ", ")).")
        }
        let why = Student.reasons([s]).compactMap { r in Cause.of(r.id, section: r.section).map { "\($0.name) \(r.count)" } }
        if !why.isEmpty { lines.append("FACT The student's own reasons for misses in this section (misses per reason): \(why.joined(separator: ", ")).") }
        for k in s.keys {
            let st = s.q[k] ?? QState(), a = st.analysis, o = s.official?.answers[k]
            let topic: String = a.map { "\($0.topic) / \($0.skill) / \($0.difficulty)" } ?? o.map { [$0.domain, $0.skill, $0.difficulty].compactMap { $0 }.joined(separator: " / ") } ?? ""
            let time: [String] = s.logged ? [] : ["\(Int(s.seconds(k))) s", "visits \(s.visitCount(k))"]
            lines.append(([s.label(k)] + time + [resultName(s.correct(k)), st.guessed ? "guessed" : "", topic,
                          st.reasons.isEmpty ? (a?.mistakeCause.map { "cause: \($0)" } ?? "") : "cause: \(st.reasons.joined(separator: ", ")) (student's own)",
                          st.memo.map { "student's note: \($0)" } ?? "", a?.coachLine ?? ""]).filter { !$0.isEmpty }.joined(separator: " | "))
        }
        let msg: [String: Any] = ["role": "user", "content": [["type": "text", "text": "Here is my whole practice test, one line per question, after the FACT lines. Give me the debrief. "
            + "Every count, difficulty, time and question label you mention must match these lines exactly; don't guess. The headline must not repeat a fix title.\n\n" + lines.joined(separator: "\n")]]]
        do {
            let text = try await Brain.send(task: .debrief, system: system + "\n\nWhat you know about the student:\n" + Student.brief(), messages: [msg], schema: debriefSchema, base: store.dir(sid))
            let d = try snake.decode(Debrief.self, from: stored(text))
            store.update(sid) { $0.debriefs[sec] = d }
        } catch {
            print("debrief failed: \(error.localizedDescription)")
        }
    }

    /// Follow-up questions in the question panel: the explanation is already on screen, so answer only what was asked.
    static let chatRules = """
    Now the student is asking follow-up questions about this question. They can already see your full explanation \
    (key point, why their choice fails, the steps and the words), the correct answer and their own answer. \
    Answer only what they asked, directly, in one to four short sentences of plain prose; use a short numbered list \
    only if they ask for steps. Don't repeat the explanation, the key point or the answers unless the question is about \
    them. Name another question the way the app does ("RW1 Q3", "M2 Q7"), so the student can click it. No JSON, no headings.
    """

    static func ask(_ sid: String, _ key: String, _ question: String) async {
        let store = Store.shared
        guard let s = store.session(sid), let data = s.q[key]?.convo,
              var convo = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        let tag = "\(sid)/\(key)/chat"   // its own tag: the explanation panel shows "Explaining…" only for its own work
        store.busy.insert(tag)
        defer { store.busy.remove(tag) }
        store.update(sid) { $0.q[key]!.chat.append(ChatLine(fromStudent: true, text: question)) }
        convo.append(["role": "user", "content": [["type": "text", "text": question]]])
        do {
            let text = try await Brain.send(task: .chat, system: system + "\n\n" + chatRules + "\n\nWhat you know about the student:\n" + Student.brief(), messages: convo, base: store.dir(sid))
            convo.append(["role": "assistant", "content": [["type": "text", "text": text]]])
            let saved = try JSONSerialization.data(withJSONObject: convo)
            store.update(sid) { $0.q[key]!.chat.append(ChatLine(fromStudent: false, text: text)); $0.q[key]!.convo = saved }
        } catch {
            store.update(sid) { $0.q[key]!.chat.append(ChatLine(fromStudent: false, text: error.localizedDescription)) }
        }
    }
}
