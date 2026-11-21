import AppKit
import Carbon.HIToolbox

/// Runs one practice test: question visits, the raw event log, screen reading.
@MainActor final class Tracker: ObservableObject {
    static let shared = Tracker()
    @Published private(set) var session: Session?
    @Published private(set) var section = "Math"   // follows Bluebook's header on its own
    @Published private(set) var module = 1
    @Published private(set) var number: Int?      // nil = not on a question (start, review page, paused)
    @Published private(set) var paused = false
    @Published private(set) var now = Date()

    private let store = Store.shared
    private var log: FileHandle?
    private var monitor: Any?
    private var appObserver: NSObjectProtocol?
    private var ticker: Timer?
    private var lastInput = Date.distantPast
    private var scanning = false, rescan = false
    private var ticks = 0
    private var lastTimer: Int?        // Bluebook's countdown, seconds; it jumps back up when a module starts
    private var watcher: Timer?
    private var armed = true           // auto-start only after Bluebook has shown a non-question screen since the last stop
    private var lastEvent = Date.distantPast             // any click, key or scroll
    private var lastShot: (visit: Date, frame: Date)?    // visit start and capture time of the last frame checked for saving
    private var written: [Date: Date] = [:]              // per visit (by start): capture time of the frame on disk, so an older one never overwrites it
    private var pendingScan: Task<Void, Never>?
    private var lastPeek: Date?

    var key: String? { number.map { Session.key(section, module, $0) } }

    /// One symbol per state, shared by the menu bar and the floating timer.
    static var stateIcon: String {
        let t = shared
        if t.session != nil { return t.paused ? "pause.circle.fill" : t.number == nil ? "eye" : "timer" }
        return Store.shared.busy.isEmpty ? "chart.bar.xaxis" : "sparkles"
    }
    var guessed: Bool { key.flatMap { session?.q[$0]?.guessed } ?? false }
    var flagged: Bool { key.flatMap { session?.q[$0]?.flagged } ?? false }
    var questionTime: Double { key.flatMap { k in session?.seconds(k, now: now) } ?? 0 }
    var elapsed: Double { session.map { now.timeIntervalSince($0.start) } ?? 0 }

    // MARK: start / stop

    func start() {
        guard session == nil else { return }
        if !Capture.allowed { CGRequestScreenCaptureAccess() }
        // Key logging needs Accessibility; without it only clicks are logged.
        let testing = CommandLine.arguments.contains("--track-test")
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": !testing] as CFDictionary)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let choice = TestChoice.current
        let s = Session(id: f.string(from: Date()), start: Date(), test: choice.name,
                        source: NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
        section = "Math"; module = 1
        store.save(s)
        let url = store.dir(s.id).appendingPathComponent("events.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        begin(s, log: url)
        record("start", ["app": s.source])
    }

    /// After a relaunch mid-test (crash, update), keep tracking the open session instead of losing it.
    func resume() {
        guard session == nil, var s = store.sessions.first(where: { $0.end == nil }) else { return }
        let url = store.dir(s.id).appendingPathComponent("events.jsonl")
        let last = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? s.start
        guard Date().timeIntervalSince(last) < 30 * 60 else { return }
        closeVisit(&s, at: last)
        section = s.visits.last?.section ?? s.section
        module = s.visits.last?.module ?? 1
        store.save(s)
        begin(s, log: url)
        log?.seekToEndOfFile()
        record("resume_app", ["gap": Int(Date().timeIntervalSince(last))])
    }

    private func begin(_ s: Session, log url: URL) {
        session = s
        number = nil; paused = false; now = Date(); lastTimer = nil
        log = try? FileHandle(forWritingTo: url)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] e in
            MainActor.assumeIsolated { self?.input(e) }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? ""
            MainActor.assumeIsolated { self?.record("app", ["name": app]) }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.1
        scan(at: Date())
    }

    func stop() {
        guard var s = session else { return }
        closeVisit(&s, at: Date())
        s.end = Date()
        session = s
        record("stop", ["seconds": Int(s.studyTime)])
        store.save(s)
        try? log?.close(); log = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        monitor = nil; appObserver = nil
        ticker?.invalidate(); ticker = nil
        pendingScan?.cancel(); pendingScan = nil
        session = nil; number = nil; armed = false
        AppDelegate.shared?.showMain(.session(s.id))   // nil in tests: no window
        if Settings.autoAnalyze, Brain.ready { Tutor.analyzeAll(s.id) }
    }

    /// Snapshot tests only: show a fixed state in the bar.
    func preview(_ s: Session?, number n: Int?) { session = s; number = n; now = s?.end ?? Date() }

    // MARK: manual controls (buttons and ⌃⌥ shortcuts)

    func step(_ delta: Int) {
        guard session != nil else { return }
        go(section: section, module: module, number: max(1, (number ?? 0) + delta), at: Date(), by: "manual")
    }

    func setModule(_ m: Int) {
        guard session != nil else { return }
        go(section: section, module: m, number: 1, at: Date(), by: "manual")
    }

    func toggleGuess() { toggle("guess") { $0.guessed.toggle() } }
    func toggleFlag() { toggle("flag") { $0.flagged.toggle() } }

    func togglePause() {
        guard var s = session else { return }
        paused.toggle()
        if paused { closeVisit(&s, at: Date()) } else if let n = number { openVisit(&s, section: section, module: module, number: n, at: Date()) }
        session = s
        record(paused ? "pause" : "resume", [:])
        store.save(s)
    }

    private func toggle(_ kind: String, _ change: (inout QState) -> Void) {
        guard var s = session, let k = key else { return }
        change(&s.q[k, default: QState()])
        session = s
        record(kind, ["q": k, "on": kind == "guess" ? s.q[k]!.guessed : s.q[k]!.flagged])
        store.save(s)
    }

    // MARK: question changes

    private func go(section sec: String, module m: Int, number n: Int, at t: Date, by source: String) {
        guard var s = session, !(sec == section && m == module && n == number) else { return }
        closeVisit(&s, at: t)
        section = sec; module = m; number = n
        if !paused { openVisit(&s, section: sec, module: m, number: n, at: t) }
        session = s
        record("question", ["q": Session.key(sec, m, n), "by": source])
        store.save(s)
    }

    private func leaveQuestion(at t: Date, reason: String) {
        guard var s = session, number != nil else { return }
        closeVisit(&s, at: t)
        number = nil
        session = s
        record("off_question", ["reason": reason])
        store.save(s)
    }

    private func openVisit(_ s: inout Session, section sec: String, module m: Int, number n: Int, at t: Date) {
        s.visits.append(Visit(section: sec, module: m, number: n, start: t))
    }

    private func closeVisit(_ s: inout Session, at t: Date) {
        if let i = s.visits.indices.last, s.visits[i].end == nil { s.visits[i].end = t }
    }

    // MARK: raw input and screen reading

    private func input(_ e: NSEvent) {
        var d: [String: Any] = ["type": e.type.rawValue]
        let p = NSEvent.mouseLocation
        switch e.type {
        case .keyDown where NSWorkspace.shared.frontmostApplication?.localizedName == session?.source:
            d["key"] = e.keyCode
            d["chars"] = e.characters ?? ""   // only in the test app: never log what's typed elsewhere
        case .scrollWheel:
            d["dy"] = e.scrollingDeltaY
            d["x"] = Int(p.x); d["y"] = Int(p.y)
        default:
            d["x"] = Int(p.x); d["y"] = Int(p.y)
        }
        d["app"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        record(e.type == .keyDown ? "key" : e.type == .scrollWheel ? "scroll" : "click", d)
        lastEvent = Date()
        guard e.type != .scrollWheel else { return }
        lastInput = lastEvent
        // Mouse-down shows the screen before the click acts (e.g. the chosen answer before "Next");
        // the later scan shows what the click changed. Events inside its 0.35 s share it.
        if e.type == .leftMouseDown { grabBeforeClick(); scan(at: lastInput) }
        guard pendingScan == nil else { return }
        let t = lastInput
        pendingScan = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.pendingScan = nil
            self?.scan(at: t)
        }
    }

    private func tick() {
        now = Date()
        ticks += 1
        if ticks % 4 == 0 { scan(at: now.timeIntervalSince(lastInput) < 5 ? lastInput : now) }
    }

    /// Capture → OCR → maybe a new question. One at a time; a request during a scan runs once after it.
    private func scan(at trigger: Date) {
        guard session != nil, !paused else { return }
        if scanning { rescan = true; return }
        scanning = true
        let frame = Date()
        Task {
            if let (img, app) = await Capture.frontWindow() {
                let d = await Task.detached { () -> Detected in
                    let d = Detected.parse(Capture.bluebook(img))
                    return d.number != nil ? d : Detected.parse(Capture.text(img))   // other practice sites, review page
                }.value
                handle(d, image: img, app: app, at: trigger, frame: frame)
            }
            scanning = false
            if rescan { rescan = false; scan(at: lastInput) }
        }
    }

    private func handle(_ d: Detected, image: CGImage, app: String, at trigger: Date, frame: Date) {
        guard var s = session else { return }
        if s.visits.isEmpty, let sec = d.section, d.number != nil { s.section = sec; session = s }
        // Bluebook shows the test's name; trust it over the picker for Bluebook tests.
        if let n = d.practiceTest, let name = TestChoice.bluebook.first(where: { $0 == "SAT Practice \(n)" }),
           s.test.map(TestChoice.bluebook.contains) ?? true, s.test != name {
            s.test = name; session = s; store.save(s)
        }
        if d.number != nil, s.source != app { s.source = app; s.total = d.of; session = s }
        if let n = d.number {
            let sec = d.section ?? section
            let t = d.timer.flatMap(Tracker.seconds)
            // No header (Desmos over it): a countdown that jumped back up means the next module began.
            let restarted = sec == section && t != nil && lastTimer != nil && t! > lastTimer! + 120
            let m = d.module ?? (sec != section ? 1 : restarted ? min(module + 1, 2) : module)
            if t != nil { lastTimer = t }
            go(section: sec, module: m, number: n, at: trigger, by: "screen")
            record("screen", ["q": Session.key(sec, m, n), "of": d.of ?? 0, "timer": d.timer ?? "", "section": d.section ?? ""])
        } else if d.reviewPage {
            leaveQuestion(at: trigger, reason: "review page")
        }
        if d.number != nil { saveShot(image, at: frame) }   // never bank a frame without "Question N of M" (e.g. "This Module Is Over")
    }

    /// Bluebook's countdown ("33:05") in seconds.
    static func seconds(_ clock: String) -> Int? {
        let p = clock.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : nil
    }

    /// True when a new frame can't differ from the last one checked: that one was captured over a second after the
    /// latest input (the screen had settled) and under `refresh` seconds before this one.
    static func unchanged(last: Date?, input: Date, frame: Date, refresh: TimeInterval) -> Bool {
        guard let last else { return false }
        return last.timeIntervalSince(input) >= 1 && frame.timeIntervalSince(last) < refresh
    }

    /// No test running: when Bluebook shows a question, start tracking on our own.
    func watch() {
        watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.peek() }
        }
        watcher?.tolerance = 1
    }

    private func peek() {
        guard session == nil, NSWorkspace.shared.frontmostApplication?.localizedName?.contains("Bluebook") == true,
              Capture.allowed else { lastPeek = nil; return }
        guard !scanning else { return }
        // No input (mouse moves count) since the last read, under 6 s ago: same screen, same outcome, so skip it.
        let now = Date(), idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if Tracker.unchanged(last: lastPeek, input: now - idle, frame: now, refresh: 6) { return }
        lastPeek = now
        scanning = true
        Task {
            let d: Detected? = if let (img, app) = await Capture.frontWindow(), app.contains("Bluebook") {
                await Task.detached { Detected.parse(Capture.bluebook(img)) }.value
            } else { nil }
            scanning = false
            if d == nil { lastPeek = nil }
            guard let d, session == nil else { return }
            if d.number == nil { armed = true } else if armed { start() }
        }
    }

    /// Keeps the newest frame of the visit, except that a frame with the question navigator open never replaces one
    /// that shows every choice.
    /// The screen at the moment of a click, before the click acts: it shows the choice the student settled on before
    /// pressing Next or opening the navigator. Captured right away, even while another read is running, and saved to
    /// the question that was open when they clicked (checked against the frame's own "Question N of M").
    private func grabBeforeClick() {
        guard let s = session, number != nil, !paused, let i = s.visits.indices.last, s.visits[i].end == nil else { return }
        let v = s.visits[i], now = Date()
        Task {
            guard let (img, _) = await Capture.frontWindow() else { return }
            let n = await Task.detached { Detected.parse(Capture.bluebook(img)).number }.value
            guard n == v.number else { return }   // not that question on screen (e.g. a review page): keep what we have
            saveShot(img, at: now, visit: v.start, force: true)
        }
    }

    private func saveShot(_ image: CGImage, at frame: Date, visit start: Date? = nil, force: Bool = false) {
        guard let s = session else { return }
        let found = start.flatMap { st in s.visits.lastIndex { $0.start == st } }
            ?? (number != nil ? s.visits.indices.last.flatMap { s.visits[$0].end == nil ? $0 : nil } : nil)
        guard let i = found else { return }
        let v = s.visits[i]
        // Same visit, no click, key or scroll since a settled frame, checked under 20 s ago: skip OCR and encoding.
        if !force, lastShot?.visit == v.start, Tracker.unchanged(last: lastShot?.frame, input: lastEvent, frame: frame, refresh: 20) { return }
        if !force { lastShot = (v.start, frame) }
        let n = s.visits[...i].filter { $0.key == v.key }.count
        let name = "shots/\(v.key)_v\(n).jpg"
        let url = store.dir(s.id).appendingPathComponent(name)
        Task {
            guard let (l, data) = await Task.detached(operation: { () -> (Capture.Layout, Data?)? in
                let l = Capture.layout(image)
                return (l, Capture.jpeg(image))
            }).value else { return }
            guard var s = session, let i = s.visits.lastIndex(where: { $0.start == v.start }) else { return }
            // Newest frame wins: a slower, older read finishing late never replaces it; a navigator frame never replaces a clean one.
            if let w = written[v.start], w > frame { return }
            if l.covered, s.visits[i].shot != nil, s.visits[i].covered == false { return }
            try? data?.write(to: url, options: .atomic)
            written[v.start] = frame
            let pane: [Double]? = l.pane.map { r in [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }
            let old = s.visits[i]
            if old.shot == name && old.covered == l.covered && old.pane == pane { return }
            s.visits[i].shot = name
            s.visits[i].covered = l.covered
            s.visits[i].pane = pane
            session = s
            store.save(s)
        }
    }

    private func record(_ kind: String, _ detail: [String: Any]) {
        var line = detail
        line["t"] = Fmt.iso.string(from: Date())
        line["event"] = kind
        if let k = key { line["at_q"] = k }
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        log?.write(data + Data("\n".utf8))
    }
}

/// System-wide ⌃⌥ shortcuts (Carbon hot keys need no permission and work over full-screen apps).
enum HotKeys {
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    static let list: [(key: Int, label: String, name: String, action: @MainActor () -> Void)] = [
        (kVK_ANSI_S, "⌃⌥S", "Start / stop", { let t = Tracker.shared; t.session == nil ? t.start() : t.stop() }),
        (kVK_RightArrow, "⌃⌥→", "Next question", { Tracker.shared.step(1) }),
        (kVK_LeftArrow, "⌃⌥←", "Previous question", { Tracker.shared.step(-1) }),
        (kVK_ANSI_G, "⌃⌥G", "Mark as guess", { Tracker.shared.toggleGuess() }),
        (kVK_ANSI_F, "⌃⌥F", "Flag", { Tracker.shared.toggleFlag() }),
        (kVK_ANSI_P, "⌃⌥P", "Pause / resume", { Tracker.shared.togglePause() }),
        (kVK_ANSI_M, "⌃⌥M", "Next module", { let t = Tracker.shared; t.setModule(t.module + 1) }),
    ]

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let n = id.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.actions[n]?() } }
            return noErr
        }, 1, &spec, nil, nil)
        for (i, h) in list.enumerated() {
            var ref: EventHotKeyRef?
            let id = UInt32(i + 1)
            RegisterEventHotKey(UInt32(h.key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x5341_5454), id: id),
                                GetApplicationEventTarget(), 0, &ref)
            actions[id] = h.action
        }
    }
}

enum Settings {
    static var autoAnalyze: Bool {
        get { UserDefaults.standard.object(forKey: "autoAnalyze") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoAnalyze") }
    }
}
