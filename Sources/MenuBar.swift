import AppKit
import Combine
import SwiftUI

/// Menu bar item: shows the question timer during a test; click for the drop-down.
@MainActor final class MenuBar: NSObject, ObservableObject {
    static let shared = MenuBar()
    @Published var naming = false
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var watch: AnyCancellable?

    func install() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "SAT Tracker")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.hasFullSizeContent = true
        let host = NSHostingController(rootView: MenuView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        watch = Tracker.shared.objectWillChange.merge(with: Store.shared.objectWillChange).sink { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        refresh()
    }

    private var shownIcon = ""

    private func refresh() {
        let t = Tracker.shared
        let icon = Tracker.stateIcon
        if icon != shownIcon {
            shownIcon = icon
            item.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: "SAT Tracker")
            item.button?.animator().alphaValue = 1
        }
        AppDelegate.shared?.updateBar()
        let title = t.session == nil ? "" : " " + (t.number.map { "Q\($0) \(Fmt.clock(t.questionTime))" } ?? (t.paused ? "Paused" : "—"))
        item.button?.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }

    @objc private func toggle() { popover.isShown ? close() : show() }

    func show(naming: Bool = false) {
        guard let b = item.button else { return }
        self.naming = naming
        NSApp.activate()          // so the name field can take typing
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    func close() { popover.performClose(nil) }
}

/// Menu metrics: one width, one row height, one radius (concentric with the popover's padding).
enum M {
    static let width: CGFloat = 280
    static let pad: CGFloat = 16
    static let row: CGFloat = 32
    static let radius: CGFloat = 10
    static let gap: CGFloat = 8
    static let offscreen = CommandLine.arguments.contains { $0.hasPrefix("--snapshot") }
}

extension View {
    /// The one control surface in the menu: Liquid Glass that responds to hover and press.
    @ViewBuilder func menuGlass() -> some View {
        // On the view itself: its label is drawn into the glass. (A background glass inside a GlassEffectContainer was composited over the labels and blurred them.)
        // Off-screen renders draw glass as nothing, so snapshots show a plain fill where the glass is.
        if M.offscreen { background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: M.radius, style: .continuous)) }
        else { glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: M.radius, style: .continuous)) }
    }
}

struct MenuView: View {
    @ObservedObject var t = Tracker.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var menu = MenuBar.shared
    @ObservedObject var plan = PlanStore.shared
    @AppStorage("test") private var test = TestChoice.bluebook[0]
    @AppStorage("barSize") private var size = 1.0
    @AppStorage("showBar") private var showBar = true
    @State private var custom = ""
    @State private var finishing = false   // Finish asks once before ending the test
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: M.pad) {
                Group {
                    if t.session == nil { setup.transition(.opacity.combined(with: .move(edge: .top))) }
                    else { running.transition(.opacity.combined(with: .move(edge: .bottom))) }
                }
                if t.session == nil {   // during a test the menu is only the test's controls
                    VStack(spacing: M.gap) {
                        section("Floating timer") {
                            Switch(title: "Floating timer", isOn: $showBar).scaleEffect(0.8)
                                .onChange(of: showBar) { AppDelegate.shared?.updateBar() }
                        }
                        if showBar {
                            Segments(items: Bar.sizes.map { ($0.name, $0.scale) }, value: $size, height: M.row, radius: M.radius)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    let recent = store.sessions.filter { $0.end != nil }.prefix(3)
                    if !recent.isEmpty {
                        VStack(spacing: 2) { ForEach(Array(recent)) { s in RecentRow(s: s) } }
                    }
                }
                footer
            }
        }
        .animation(.smooth(duration: 0.3), value: t.session == nil)
        .onChange(of: t.session == nil) { _, ended in
            finishing = false
            // After a test, offer the next Bluebook test not taken yet, so the picker doesn't repeat the one just listed under it.
            if ended, TestChoice.bluebook.contains(test),
               let next = TestChoice.bluebook.first(where: { n in !store.sessions.contains { $0.test == n } }) { test = next }
        }
        .onDisappear { finishing = false }
        .animation(.smooth(duration: 0.25), value: showBar)
        .padding(M.pad)
        .frame(width: M.width)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())   // a plain panel; only the controls are glass
    }

    private func section(_ name: String, @ViewBuilder _ trailing: () -> some View) -> some View {
        HStack {
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, M.pad)
    }

    // MARK: before a test

    private var setup: some View {
        VStack(spacing: M.pad) {
            if plan.sittingToday != nil || plan.nextTask != nil {
                VStack(spacing: M.gap) {
                    section("Today") { EmptyView() }
                    if plan.sittingToday != nil {
                        Label("SAT today", systemImage: "flag.checkered").font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, M.pad).frame(height: M.row)
                    } else if let task = plan.nextTask { TodayRow(task: task) }
                }
            }
            VStack(spacing: M.gap) {
            section("Track a Bluebook test") { EmptyView() }
            if menu.naming {
                TextField("Practice name", text: $custom)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, M.pad).frame(height: M.row)
                    .menuGlass()
                    .focused($nameFocused)
                    .onAppear { custom = TestChoice.bluebook.contains(test) ? "" : test; nameFocused = true }
                    .onSubmit {
                        let n = custom.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { test = n }
                        withAnimation(.smooth(duration: 0.25)) { menu.naming = false }
                    }
            } else {
                TestMenu(onOther: { withAnimation(.smooth(duration: 0.25)) { menu.naming = true } }) {
                    HStack {
                        Text(plan.trackChoice(test)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, M.pad).frame(height: M.row)
                    .contentShape(Rectangle())
                    .menuGlass()
                }
            }
            Button { MenuBar.shared.close(); t.start() } label: {
                Label("Start tracking", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: M.row)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: M.radius, style: .continuous))   // accent even when the popover isn't key
                    .contentShape(RoundedRectangle(cornerRadius: M.radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: during a test

    private var running: some View {
        VStack(spacing: M.gap) {
            HStack(spacing: M.gap) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: M.gap) {
                        Text(Fmt.clock(moduleLeft)).font(.system(size: 24, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(countsDown: true))
                            .help("Time left in this module")
                        Text(t.number.map { "Q\($0) \(Fmt.clock(t.questionTime))" } ?? (t.paused ? "Paused" : "Review"))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .monospacedDigit().lineLimit(1)
                    Text("\(t.session?.title ?? "") · \(t.section == "Math" ? "Math" : "R&W")")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .animation(.smooth(duration: 0.3), value: t.number)
                .animation(.smooth(duration: 0.3), value: Int(t.elapsed))
                .padding(.leading, M.pad)
                Spacer(minLength: 0)
                Step(icon: "chevron.left") { t.step(-1) }
                Step(icon: "chevron.right") { t.step(1) }
            }
            HStack(spacing: M.gap) {
                Tile(icon: "questionmark", name: "Guess", on: t.guessed) { t.toggleGuess() }
                Tile(icon: "flag.fill", name: "Flag", on: t.flagged) { t.toggleFlag() }
                Tile(icon: t.paused ? "play.fill" : "pause.fill", name: t.paused ? "Resume" : "Pause", on: t.paused) { t.togglePause() }
            }
            Segments(items: [("Module 1", 1), ("Module 2", 2)], value: Binding(get: { t.module }, set: { t.setModule($0) }),
                     height: M.row, radius: M.radius)
            if finishing {
                HStack(spacing: M.gap) {
                    FooterButton(name: "Cancel") { withAnimation(.smooth(duration: 0.2)) { finishing = false } }
                    FooterButton(name: "Finish test", bold: true) { MenuBar.shared.close(); t.stop() }
                }
            } else {
                FooterButton(name: "Finish…") { withAnimation(.smooth(duration: 0.2)) { finishing = true } }
            }
        }
    }

    /// Bluebook's module clock, from the time spent on this module's questions.
    /// shortcut: leaves out time on Bluebook's review page; read Bluebook's own countdown if the gap shows.
    private var moduleLeft: Double {
        guard let s = t.session else { return 0 }
        return max(0, Sec.limit(t.section) - s.only(t.section).used(t.module))
    }

    private var footer: some View {
        VStack(spacing: M.gap) {
            if t.session == nil { FooterButton(name: "Open SAT Tracker") { MenuBar.shared.close(); AppDelegate.shared?.showMain() } }
            HStack {
                FooterButton(icon: "gearshape") { MenuBar.shared.close(); AppDelegate.shared?.showMain(.settings) }
                Spacer()
                FooterButton(icon: "power") { NSApp.terminate(nil) }
            }
        }
    }
}

private struct Step: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: M.row, height: M.row)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct Tile: View {
    let icon: String, name: String
    var on = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(name).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(on ? Color.white : (tint ?? Color.primary))
            .frame(maxWidth: .infinity).frame(height: M.row * 1.5)
            .contentShape(Rectangle())
            .background(on ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: M.radius, style: .continuous))   // tinted glass blanks off-screen renders
            .menuGlass()
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: on)
    }
}

private struct RecentRow: View {
    let s: Session
    @State private var hover = false

    var body: some View {
        Button {
            MenuBar.shared.close()
            AppDelegate.shared?.showMain(.session(s.id))
        } label: {
            HStack(spacing: M.gap) {
                Text(s.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(s.start.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let n = s.scoreNote { Text(n).font(.system(size: 12, weight: n == "No results" ? .regular : .semibold)).foregroundStyle(n == "No results" ? .secondary : .primary).monospacedDigit() }
            }
            .padding(.horizontal, M.pad).frame(height: M.row)
            .background(Color.primary.opacity(hover ? 0.07 : 0), in: RoundedRectangle(cornerRadius: M.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.smooth(duration: 0.15)) { hover = h } }
    }
}

private struct TodayRow: View {
    let task: StudyTask
    @State private var hover = false

    var body: some View {
        Button {   // starts it: the app opens on what the task needs
            MenuBar.shared.close()
            AppDelegate.shared?.showMain(.today)
            Actions.start(task)
        } label: {
            HStack(spacing: M.gap) {
                Image(systemName: task.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(task.tint).frame(width: 18)
                Text(task.line).font(.system(size: 13, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if task.minutes > 0 { Text(Fmt.hm(task.minutes)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().fixedSize() }
            }
            .padding(.horizontal, M.pad).padding(.vertical, 4).frame(minHeight: M.row)
            .background(Color.primary.opacity(hover ? 0.07 : 0), in: RoundedRectangle(cornerRadius: M.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.smooth(duration: 0.15)) { hover = h } }
    }
}

/// A named row (text aligned with the rows above it) or a round icon button.
private struct FooterButton: View {
    var icon = "", name: String? = nil
    var bold = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: M.gap) {
                if let name { Text(name); Spacer(minLength: 0) } else { Image(systemName: icon).frame(width: 18) }
            }
            .font(.system(size: 13, weight: bold ? .semibold : .medium))
            .padding(.horizontal, name == nil ? 0 : M.pad)
            .frame(maxWidth: name == nil ? M.row : .infinity).frame(height: M.row)
            .contentShape(Rectangle())
            .menuGlass()
        }
        .buttonStyle(.plain)
    }
}
