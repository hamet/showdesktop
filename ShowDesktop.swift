// Show Desktop — instantly clears all windows away and shows the desktop.
//
// Click the Dock icon (or press ⌃⌥D while the app is running):
//   • first click  → every app with visible windows is hidden (like ⌘H);
//   • second click → they come back, and focus returns to the previously active app.
// Apps that were already hidden before the click are left alone.
// No Accessibility permission required.
// If dockhide is installed, Show Desktop must be in its excludedBundleIDs,
// otherwise dockhide intercepts clicks on the active Show Desktop's icon.
//
// Build: ./build.sh   (swiftc -O, no Xcode)

import Cocoa
import Carbon.HIToolbox

// MARK: - Screen freeze (private SkyLight API, as used by yabai).
// While updates are disabled, WindowServer doesn't draw intermediate states:
// windows don't get to "dim" on focus change and don't vanish/appear one by one.
// The system re-enables updates by itself after ~1 s, so the screen can't get stuck.
private enum ScreenFreeze {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias UpdFn  = @convention(c) (Int32) -> Int32
    private static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let sky, let p = dlsym(sky, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    private static let conn    = sym("SLSMainConnectionID", ConnFn.self)?() ?? 0
    private static let disable = sym("SLSDisableUpdate", UpdFn.self)
    private static let enable  = sym("SLSReenableUpdate", UpdFn.self)
    private static var frozen = false

    static func begin() {
        guard !frozen, let disable else { return }
        _ = disable(conn); frozen = true
    }
    static func end() {
        guard frozen, let enable else { return }
        _ = enable(conn); frozen = false
    }
}

final class Controller: NSObject, NSApplicationDelegate {
    private let myPID = ProcessInfo.processInfo.processIdentifier
    private var stash: [NSRunningApplication] = []   // hidden by us, front to back
    private var lastFront: NSRunningApplication?      // last active app other than us
    private var restoreFront: NSRunningApplication?
    private var hotKeyRef: EventHotKeyRef?
    private var lastToggle = Date.distantPast
    private var pendingHide: [NSRunningApplication]?   // waiting for our own activation before hiding

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != myPID {
            lastFront = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != self.myPID else { return }
            self.lastFront = app
        }
        registerHotKey()
        // Do NOT toggle here: we are not active yet, and hiding the active app
        // would make the system activate (= unhide) Finder.
        // The first toggle happens in applicationDidBecomeActive.
    }

    // Launched from the Dock, or icon clicked while we are NOT active: macOS activates
    // the app first, and the reopen event may not arrive.
    func applicationDidBecomeActive(_ note: Notification) {
        if let apps = pendingHide {
            pendingHide = nil
            performHide(apps)
            return
        }
        trigger()
    }

    // Dock icon clicked while we are already active.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        trigger()
        return false
    }

    /// A single click may deliver both an activation and a reopen; our own activation
    /// in hide() also delivers didBecomeActive. Anything arriving within 0.5 s
    /// of the previous toggle is treated as the same event.
    private func trigger() {
        guard Date().timeIntervalSince(lastToggle) > 0.5 else { return }
        toggle()
    }

    // MARK: - Toggle

    /// Strict alternation: if there are apps hidden by us that are still hidden,
    /// bring them back; otherwise hide everything visible.
    func toggle() {
        lastToggle = Date()
        stash.removeAll { $0.isTerminated || !$0.isHidden }
        if !stash.isEmpty {
            restore()
        } else {
            let visible = appsWithVisibleWindows()
            if !visible.isEmpty { hide(visible) }
        }
    }

    private func hide(_ apps: [NSRunningApplication]) {
        restoreFront = lastFront
        stash = apps
        ScreenFreeze.begin()

        // Only hide while we ourselves are active: hiding the active app makes the
        // system activate the next one — usually Finder — which unhides its windows.
        if NSApp.isActive {
            performHide(apps)
        } else {
            // Hotkey path: request activation and hide once it happens.
            pendingHide = apps
            if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let apps = self.pendingHide else { return }
                self.pendingHide = nil
                self.performHide(apps)          // activation was denied — hide anyway
            }
        }
    }

    private func performHide(_ apps: [NSRunningApplication]) {
        for app in apps { app.hide() }
        // While the screen is frozen, re-hide anything that popped back
        // (e.g. Finder, if the system handed it focus after all).
        waitThenUnfreeze {
            var ok = true
            for app in apps where !app.isTerminated && !app.isHidden {
                if !app.isActive || NSApp.isActive { app.hide() }
                ok = false
            }
            return ok
        }
    }

    private func restore() {
        let items = stash.filter { !$0.isTerminated }
        let front = restoreFront
        stash = []
        restoreFront = nil
        guard !items.isEmpty else { return }

        ScreenFreeze.begin()
        for app in items.reversed() where app.isHidden { app.unhide() }
        let target = (front.map { !$0.isTerminated } ?? false) ? front! : items[0]
        target.activate(options: [])
        waitThenUnfreeze {
            items.allSatisfy { $0.isTerminated || !$0.isHidden } && target.isActive
        }
    }

    /// Hide/unhide are asynchronous: wait until every app has complied, then
    /// show the result in a single frame. At most ~0.4 s.
    private func waitThenUnfreeze(_ done: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(0.4)
        func tick() {
            if done() || Date() > deadline {
                // one more frame so the apps can redraw
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { ScreenFreeze.end() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: tick)
            }
        }
        tick()
    }

    /// Regular apps (with a Dock icon) that have windows on the current screen,
    /// in stacking order — front to back.
    private func appsWithVisibleWindows() -> [NSRunningApplication] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var order: [pid_t] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != myPID, !order.contains(pid) else { continue }
            order.append(pid)
        }
        return order.compactMap { NSRunningApplication(processIdentifier: $0) }
                    .filter { $0.activationPolicy == .regular && !$0.isHidden }
    }

    // MARK: - Hotkey ⌃⌥D

    fileprivate func triggerFromHotKey() { trigger() }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<Controller>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.triggerFromHotKey() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x5348_4454), id: 1)   // 'SHDT'
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Menu (so that ⌘Q works)

    private func buildMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        main.addItem(item)
        let sub = NSMenu()
        sub.addItem(withTitle: "Quit Show Desktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = sub
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
