import AppKit
import SwiftUI
import Combine
import ServiceManagement
import Carbon.HIToolbox

/// A panel that floats above other windows and can take keyboard input
/// without activating the app (so clicking a checkbox doesn't steal focus).
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func zoom(_ sender: Any?) {}   // ignore double-click-to-zoom on the header

    // Text being typed is drawn by the window's shared "field editor", which paints a white
    // box by default. Make it transparent so new/edited items sit directly on the note color.
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        if let tv = editor as? NSTextView {
            tv.drawsBackground = false
            tv.backgroundColor = .clear
        }
        return editor
    }

    // When not pinned, a click should still bring the note in front of other windows,
    // even though the panel never activates the app.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { orderFrontRegardless() }
        super.sendEvent(event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private var panel: FloatingPanel!
    private var alertPanel: FloatingPanel!
    private var alertHost: NSView?
    private var reminderTimer: Timer?
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var noteHotKey: HotKey?
    private var loginItem: NSMenuItem!
    private var onTopItem: NSMenuItem!
    private var alertsItem: NSMenuItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusItem()
        setupEditMenu()

        // ⌃⌥T toggles the note from anywhere.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }
        // ⌃⌥N opens a blank quick note, ready to type.
        noteHotKey = HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.quickNote()
        }

        setupAlertPanel()

        store.$opacity
            .sink { [weak self] in self?.panel.alphaValue = $0 }
            .store(in: &cancellables)
        store.$items
            .sink { [weak self] items in self?.updateBadge(items.filter { !$0.done }.count) }
            .store(in: &cancellables)
        // ⌘+ / ⌘− / ⌘0 resize the text while the note is focused.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command
            else { return event }
            switch event.charactersIgnoringModifiers {
            case "=", "+": self.store.fontSize = TextSizes.step(self.store.fontSize, by: 1)
            case "-", "_": self.store.fontSize = TextSizes.step(self.store.fontSize, by: -1)
            case "0":      self.store.fontSize = TextSizes.default
            case "1":      self.store.tab = .todo
            case "2":      self.store.tab = .notes
            case "n":      // ⌘N: new to-do row or new note, depending on the tab
                if self.store.tab == .todo { self.store.newEntryRequest += 1 } else { self.store.newNote() }
            default:       return event
            }
            return nil
        }

        store.$alwaysOnTop
            .sink { [weak self] onTop in self?.panel.level = onTop ? .floating : .normal }
            .store(in: &cancellables)

        showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNotesNow()     // flush any typing that hasn't been written yet
    }

    /// A menu-bar app has no visible menu bar, but text fields only get ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z
    /// through the app's main menu. This one is never shown; it just carries those shortcuts.
    private func setupEditMenu() {
        let main = NSMenu()
        main.addItem(NSMenuItem())                  // slot macOS reserves for the app menu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = edit.addItem(withTitle: "Paste and Match Style",
                                 action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func quickNote() {
        store.newNote()
        showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    // MARK: - Panel

    private func setupPanel() {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 380),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.minSize = NSSize(width: 220, height: 160)

        let root = ContentView(
            store: store,
            window: { [weak self] in self?.panel },
            onHide: { [weak self] in self?.hidePanel() })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []          // let the user size the window, not SwiftUI
        panel.contentView = host

        let autosave = "TackiePanel"
        if !panel.setFrameUsingName(autosave), let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - 300, y: vf.maxY - 400))
        }
        panel.setFrameAutosaveName(autosave)
    }

    private func showPanel() {
        panel.orderFrontRegardless()
        panel.makeKey()
        store.focusRequest += 1
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }

    private func togglePanel() {
        // Hide only if you're already using the note; otherwise bring it forward
        // (when unpinned it may be sitting behind other windows).
        panel.isVisible && panel.isKeyWindow ? hidePanel() : showPanel()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tackie")
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        let toggle = NSMenuItem(title: "Show / Hide Note", action: #selector(toggleAction), keyEquivalent: "t")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.target = self
        menu.addItem(toggle)

        let note = NSMenuItem(title: "New Quick Note", action: #selector(quickNoteAction), keyEquivalent: "n")
        note.keyEquivalentModifierMask = [.control, .option]
        note.target = self
        menu.addItem(note)

        onTopItem = NSMenuItem(title: "Keep on Top", action: #selector(toggleOnTop), keyEquivalent: "")
        onTopItem.target = self
        menu.addItem(onTopItem)

        let clear = NSMenuItem(title: "Clear Completed", action: #selector(clearCompleted), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        alertsItem = NSMenuItem(title: "Reminder Alerts", action: #selector(toggleAlerts), keyEquivalent: "")
        alertsItem.target = self
        menu.addItem(alertsItem)
        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        onTopItem.state = store.alwaysOnTop ? .on : .off
        alertsItem.state = store.alertsEnabled ? .on : .off
    }

    @objc private func toggleAlerts() { store.alertsEnabled.toggle() }

    @objc private func toggleOnTop() { store.alwaysOnTop.toggle() }

    private func updateBadge(_ count: Int) {
        statusItem?.button?.title = count > 0 ? " \(count)" : ""
    }

    @objc private func toggleAction() { togglePanel() }
    @objc private func quickNoteAction() { quickNote() }
    @objc private func clearCompleted() { store.clearCompleted() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = "\(error.localizedDescription)\n\nTip: move the app to /Applications and try again."
            alert.runModal()
        }
    }

    // MARK: - Reminder alerts

    private func setupAlertPanel() {
        alertPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        alertPanel.level = .statusBar                 // above everything, including the pinned note
        alertPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        alertPanel.hidesOnDeactivate = false
        alertPanel.isReleasedWhenClosed = false
        alertPanel.isOpaque = false
        alertPanel.backgroundColor = .clear
        alertPanel.hasShadow = false                  // the cards draw their own shadows
        let host = NSHostingView(rootView: ReminderAlertView(store: store, onOpenNote: { [weak self] in
            self?.store.tab = .todo
            self?.showPanel()
        }))
        host.sizingOptions = []
        alertPanel.contentView = host
        alertHost = host

        // Check every few seconds; cheap, and catches up right after the Mac wakes.
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkReminders()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkReminders()
        }
        store.$alerting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in self?.layoutAlertPanel(count: ids.count) }
            .store(in: &cancellables)
        checkReminders()
    }

    private func checkReminders() {
        if store.checkDueReminders() {
            NSSound(named: "Glass")?.play()
        }
    }

    /// Size the alert window to its cards and pin it to the top-right of the screen.
    private func layoutAlertPanel(count: Int) {
        guard count > 0, let host = alertHost else { alertPanel.orderOut(nil); return }
        DispatchQueue.main.async { [self] in
            let size = host.fittingSize
            guard let screen = NSScreen.main else { return }
            let vf = screen.visibleFrame
            alertPanel.setFrame(NSRect(x: vf.maxX - size.width - 8, y: vf.maxY - size.height - 4,
                                       width: size.width, height: size.height), display: true)
            alertPanel.orderFrontRegardless()
        }
    }
}

// MARK: - Global hotkey (Carbon; no Accessibility permission needed)

final class HotKey {
    private static var nextID: UInt32 = 1
    private let id: UInt32
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.id = HotKey.nextID
        HotKey.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            // Every hotkey handler sees every press; only act on (and consume) our own.
            guard pressed.id == me.id else { return OSStatus(eventNotHandledErr) }
            me.action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x464C_5452), id: self.id)   // 'FLTR'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
