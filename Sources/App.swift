import AppKit
import SwiftUI

@main
struct Main {
    static func main() {
        atexit { if Thread.isMainThread { MainActor.assumeIsolated { Store.shared.flush() } } }   // headless runs (--redo, --live) exit straight after saving
        if SelfTest.handled(CommandLine.arguments) { exit(0) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar app; the Dock icon appears while the window is open
        app.run()
    }
}

/// Never takes focus from the test, floats over every app and full-screen Space.
final class FloatingPanel: NSPanel {
    init(_ view: some View) {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true          // set before level: it resets level to .floating
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false          // the pill draws its own soft shadow; the window shadow gave a hard outline
        contentViewController = NSHostingController(rootView: view)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    static var shared: AppDelegate?
    private var panel: FloatingPanel!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        buildMenu()
        panel = FloatingPanel(BarView())
        if !panel.setFrameUsingName("Bar"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - 120, y: f.maxY - 80, width: 512, height: 68), display: false)
        }
        panel.setFrameAutosaveName("Bar")
        MainActor.assumeIsolated {
            MenuBar.shared.install()
            Notifier.install()
            Tracker.shared.resume()
            Tracker.shared.watch()
            // A logged test that was never explained (logged before auto-explain, or the tutor was offline) catches up once.
            if Settings.autoAnalyze, Brain.ready, ProcessInfo.processInfo.environment["SAT_DATA"] == nil {
                for s in Store.shared.sessions where s.logged && !s.keys.contains(where: { s.q[$0]?.analysis != nil }) { Tutor.analyzeAll(s.id) }
            }
            updateBar()
        }
        HotKeys.install()
        if Store.shared.sessions.isEmpty || !MainActor.assumeIsolated({ PlanStore.shared.profile.onboarded }) { showMain() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ n: Notification) {
        MainActor.assumeIsolated {
            if Tracker.shared.session != nil { Tracker.shared.stop() }
            Store.shared.flush()
        }
    }

    /// The timer shows only during a test (and only if wanted); it fades in and out.
    @MainActor func updateBar() {
        let size = Bar(scale: UserDefaults.standard.object(forKey: "barSize") as? Double ?? 1).window
        if panel.frame.size != size {   // keep the top-left corner where the user put it
            panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        }
        let want = Tracker.shared.session != nil && (UserDefaults.standard.object(forKey: "showBar") as? Bool ?? true)
        guard want != (panel.isVisible && panel.alphaValue > 0.5) else { return }
        if want { panel.alphaValue = 0; panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.25
            panel.animator().alphaValue = want ? 1 : 0
        }, completionHandler: { [panel] in if !want { panel?.orderOut(nil) } })
    }

    func windowWillClose(_ n: Notification) { NSApp.setActivationPolicy(.accessory) }

    @MainActor func showMain(_ nav: Store.Nav? = nil) {
        if let nav { Store.shared.nav = nav }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: MainView()))
            w.title = "SAT Tracker"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 1100, height: 760))
            w.setFrameAutosaveName("Main")
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func openSettings() { MainActor.assumeIsolated { showMain(.settings) } }
    @objc private func toggleSidebar() { MainActor.assumeIsolated { Sidebar.shared.toggle() } }

    /// The sidebar item reads Show or Hide like SidebarCommands; it needs the main window up front.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(toggleSidebar) else { return true }
        return MainActor.assumeIsolated {
            item.title = Sidebar.shared.hidden ? "Show Sidebar" : "Hide Sidebar"
            return window?.isKeyWindow == true && PlanStore.shared.profile.onboarded
        }
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(), app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit SAT Tracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let viewItem = NSMenuItem(), view = NSMenu(title: "View")
        let side = view.addItem(withTitle: "Hide Sidebar", action: #selector(toggleSidebar), keyEquivalent: "s")
        side.keyEquivalentModifierMask = [.control, .command]
        side.target = self
        viewItem.submenu = view
        main.addItem(viewItem)
        let winItem = NSMenuItem(), win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}
