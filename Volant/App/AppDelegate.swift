import AppKit
import ServiceManagement
import Combine
import VolantCore

/// Owns the long-lived services: menu bar item, hotkeys, app index, clipboard monitor, and the panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The one connection to the input helper, shared by dictation, Search Menu Items and Settings.
    /// It connects only when the owner has chosen Type at the cursor or turned on Search Menu Items.
    private let inputHost = InputHostConnection()
    private lazy var dictationAccess = DictationTypingAccess(client: inputHost, canReconnect: { [weak self] in
        guard let model = self?.panel.model else { return true }
        return !model.dictation.isListening && !model.dictationTypesAtCursor
    })
    /// Turning Search Menu Items off stops the helper only when dictation isn't typing with it.
    private lazy var menuItemsAccess = MenuItemsAccess(client: inputHost, canDisconnect: { [weak self] in
        guard let self else { return true }
        return self.config.dictationOutput == .copy && !self.panel.model.dictationTypesAtCursor
    })
    private lazy var settingsPanel: SettingsWindowController = SettingsWindowController(conversations: panel.model.conversations, dictationAccess: dictationAccess,
                                                                                        menuItemsAccess: menuItemsAccess, openAI: { [weak self] configuration in
        guard let self else { return }
        self.settingsPanel.window?.orderOut(nil)
        self.panel.model.acp.configure(configuration)
        if !self.panel.isVisible { self.panel.toggle() }
        self.panel.model.presentAIChat()
        self.panel.makeKeyAndOrderFront(nil)
        if !self.panel.model.acp.active, !self.panel.model.acp.canResume { self.panel.model.acp.start() }
    }, showWelcome: { [weak self] in
        self?.settingsPanel.window?.orderOut(nil)
        self?.showWelcome()
    }, onChange: { [weak self] in self?.reloadConfig(); self?.notesStore.reload() })
    private func showAISettings() {
        panel.orderOut(nil)
        showSettings()
        settingsPanel.state.section = .ai
    }

    private func openAIChat() {
        guard !panel.model.acp.active else { return }
        let acp = panel.model.acp
        let configuration = try? AIConfiguration.load()
        // With no provider chosen, the chat shows installed agents to pick from; Settings opens only when
        // a chosen API connection still needs its key.
        if !acp.openChat(configuration: configuration, connect: acp.start), configuration?.isConfigured == true { showAISettings() }
    }

    private lazy var settingsSync: ICloudSettingsSync = {
        let sync = ICloudSettingsSync(onApplied: { [weak self] in self?.reloadConfig() })
        sync.onStatus = { [weak self] status in self?.settingsPanel.state.iCloudStatus = status.text }
        return sync
    }()

    private let currencyRates = CurrencyRatesStore()
    /// The floating indicator for hotkey dictation, created on first use.
    private lazy var dictationIndicator = DictationIndicatorPanel(model: panel.model.dictationIndicator)
    private let dictationEscape = DictationEscapeKey(register: { HotKeyCenter.shared.register($0, handler: $1) },
                                                     unregister: { HotKeyCenter.shared.unregister($0) })
    private var dictationIndicatorObserver: AnyCancellable?
    private let updater = AppUpdater()
    private var statusItem: NSStatusItem?
    private var memoryCheck: MemoryCheck?
    /// Read before `config` loads, because loading writes a default file when none exists; a fresh
    /// install is how the Welcome window tells a new Mac from an existing one.
    private let configExistedAtLaunch = FileManager.default.fileExists(atPath: Preferences.configURL.path)
    private var config = Preferences.load()
    private var summonRegistered = true
    private var welcome: WelcomeWindowController?
    private let index = AppIndex()
    private var indexObserver: AnyCancellable?
    private lazy var clipboardStore = ClipboardStore(retention: config.clipboardRetention)
    private lazy var clipboardMonitor = ClipboardMonitor(store: clipboardStore)
    private let notesStore = NotesStore()
    private lazy var notesSync: NotesICloudSync = {
        let sync = NotesICloudSync(store: notesStore)
        sync.onStatus = { [weak self] status in self?.settingsPanel.state.notesICloudStatus = status.text }
        return sync
    }()
    /// Created on first use. Pane previews follow `config.rexPanePreviews`; turning them on or off
    /// in the window writes the configuration and reloads it, so Settings shows the same choice.
    private lazy var rexOverview = RexOverviewWindowController(model: RexOverviewModel(previewsAllowed: config.rexPanePreviews, save: { [weak self] allowed in
        try Preferences.updateBoolean("rexPanePreviews", value: allowed)
        self?.reloadConfig()
    }))
    private var rexOverviewCreated = false
    private lazy var notesPanel: NotesPanel = {
        let notes = NotesPanel(store: notesStore)
        notes.floatingPeer = panel
        panel.floatingPeer = notes
        return notes
    }()
    private let focus = FocusController()
    private let focusActions = FocusBarActions()
    private lazy var focusBar = FocusBarPanel(controller: focus, actions: focusActions)
    private lazy var focusReminder = FocusReminderPanel(controller: focus, snoozeMinutes: { [weak self] in self?.config.focus.snoozeMinutes ?? 3 })
    private lazy var focusStatusItem = FocusStatusItem(controller: focus, actions: focusActions)
    private lazy var focusNotch = FocusNotchPanel(controller: focus, actions: focusActions, snoozeMinutes: { [weak self] in self?.config.focus.snoozeMinutes ?? 3 })
    private lazy var breaks = BreakController(preferences: config.breaks)
    private lazy var breakPresenter = BreakPresenter(controller: breaks)
    private lazy var panel: LauncherPanel = LauncherPanel(index: index, clipboard: clipboardStore, notes: notesStore, config: config, focus: focus, breaks: breaks) { [weak self] action in
        switch action {
        case .settings: self?.showSettings()
        case .extensionSettings:
            self?.showSettings()
            self?.settingsPanel.state.section = .extensions
        case .ai: self?.openAIChat()
        case .aiSettings: self?.showAISettings()
        case .reloadConfig: self?.reloadConfig()
        case .editApp(let app):
            self?.showSettings()
            self?.settingsPanel.edit(app)
        case .agents: self?.showAgents()
        case .rexOverview:
            self?.rexOverviewCreated = true
            self?.rexOverview.show()
        case .open(let id): self?.notesPanel.open(noteID: id)
        case .create(let text): self?.notesPanel.openNew(text: text)
        case .confetti: ConfettiWindow.celebrate()
        case .camera: self?.showCamera()
        case .systemAction(let action): self?.performSystemAction(action)
        case .checkForUpdates: self?.checkForUpdates()
        case .whatsNew:
            self?.showSettings()
            self?.settingsPanel.state.section = .whatsNew
        case .menuItemsSettings:
            self?.showSettings()
            self?.settingsPanel.state.section = .general
        case .about:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        case .quit: NSApp.terminate(nil)
        case .welcome: self?.showWelcome()
        }
    }

    private let extensionUpdateChecker = ExtensionUpdateChecker()

    /// Shows extension updates from the last accepted catalog in the launcher, and runs the daily
    /// catalog check when the owner turned it on.
    private func startExtensionUpdates() {
        let checker = extensionUpdateChecker
        checker.manager = { [weak self] in
            let manager = self?.panel.model.extensions ?? ExtensionManager()
            manager.loadIfNeeded()
            return manager
        }
        checker.enabled = { [weak self] in self?.config.extensionUpdateChecks == true }
        checker.onCheck = { [weak self] in self?.panel.model.extensions.invalidateCatalog() }
        panel.model.extensionUpdates = { checker.available() }
        checker.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.resolvedSupportDirectory.moveLegacyDefaults(in: .standard)
        if CommandLine.arguments.contains("--acp-check") {
            // The smoke check keeps its resume record in its own suite, apart from the owner's.
            let model = ACPModel(resumeStore: UserDefaults(suiteName: "volant.acp-check")!)
            model.project = "/tmp/volant-acp-fixture"
            if let index = CommandLine.arguments.firstIndex(of: "--acp-provider"), CommandLine.arguments.indices.contains(index + 1) {
                model.provider = CommandLine.arguments[index + 1]
            }
            model.start()
            var submitted = false
            var checkTimer: Timer?
            checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                if model.state.phase == "failed" {
                    print("ACP check failed: " + model.state.status)
                    checkTimer?.invalidate(); model.disconnect(); NSApp.terminate(nil)
                } else if model.state.phase == "ready" && !model.submitting {
                    if CommandLine.arguments.contains("--acp-prompt-check") && !submitted {
                        submitted = true
                        model.draft = "Reply with exactly VOLANT_ACP_OK. Do not use tools or read or change files."
                        model.send()
                    } else {
                        let output = model.state.messages.filter { $0.role == "Agent" }.map(\.text).joined()
                        print("ACP initialized: " + model.state.agentName + "; session: " + (model.state.sessionID == nil ? "missing" : "created"))
                        if submitted { print("ACP prompt: " + (output.contains("VOLANT_ACP_OK") ? "passed" : "failed: " + model.state.status)) }
                        checkTimer?.invalidate(); model.disconnect(); NSApp.terminate(nil)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 80) {
                print("ACP check timed out: " + model.state.status)
                checkTimer?.invalidate(); model.disconnect(); NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--agents-check") {
            let model = panel.model.agents
            model.connect()
            if CommandLine.arguments.contains("--focus-current-pane"), let pane = ProcessInfo.processInfo.environment["HERDR_PANE_ID"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if let session = model.sessions.first(where: { $0.paneID == pane }) { model.focus(session) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                print("Herdr bridge: \(model.connected && !model.busy ? "connected" : "failed"); sessions: \(model.sessions.count); \(model.message)")
                if CommandLine.arguments.contains("--focus-current-pane") { print("Focus current pane: \(model.lastFocusSucceeded == true ? "passed" : "failed")") }
                model.disconnect()
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--agents") {
            DispatchQueue.main.async { [weak self] in self?.showAgents() }
        }

        NSApp.setActivationPolicy(config.showInDock ? .regular : .accessory)
        applyTheme()
        if let ai = try? AIConfiguration.load() { panel.model.acp.configure(ai) }
        if config.syncSettingsWithICloud { settingsSync.update(enabled: true) }
        notesSync.update(enabled: config.syncSettingsWithICloud)
        panel.model.inputHost = inputHost
        panel.model.menuItems.client = inputHost
        currencyRates.loadCache()
        currencyRates.onUpdate = { [weak self] in self?.panel.model.refreshForCurrencyRates() }
        panel.model.onCalculationQuery = { [weak self] query in self?.currencyRates.noteQuery(query) }
        updater.start()
        installApplicationMenu()
        installStatusItem()
        startFocus()
        startBreaks()
        indexObserver = index.$apps.sink { [weak self] apps in self?.settingsPanel.state.apps = apps }
        index.start()
        clipboardMonitor.start()
        registerHotKeys()
        dictationIndicatorObserver = panel.model.dictationIndicator.$phase.removeDuplicates().sink { [weak self] phase in
            self?.updateDictationEscape(listening: phase == .listening)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--run-extension"), CommandLine.arguments.indices.contains(i + 1) {
            let manager = ExtensionManager()
            manager.onLog = { print("log: \($0)") }
            manager.reload()
            let input = CommandLine.arguments.indices.contains(i + 2) ? CommandLine.arguments[i + 2] : ""
            guard let ext = manager.search(CommandLine.arguments[i + 1]).first else { print("no such extension"); exit(2) }
            manager.runText(ext, input: input) { result in
                switch result {
                case .success(let out):
                    if let notice = out.notice { print("notice: \(notice)") }
                    print("result: \(out.text ?? "")"); exit(0)
                case .failure(let err): print("error: \(err.localizedDescription)"); exit(1)
                }
            }
            return
        }
        startExtensionUpdates()
        if CommandLine.arguments.contains("--import-raycast") {
            DispatchQueue.main.async { [weak self] in self?.settingsPanel.showRaycastImport() }
        }
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
        if CommandLine.arguments.contains("--register-login") {
            try? SMAppService.mainApp.register()
            print("login item: \(SMAppService.mainApp.status == .enabled ? "enabled" : "not enabled")")
        }
        let launchedForTask = ["--import-raycast", "--settings", "--agents", "--show", "--notes"].contains { CommandLine.arguments.contains($0) }
        var showingWelcome = false
        switch WelcomeLaunch.decide(configExisted: configExistedAtLaunch, completed: config.welcomeCompleted) {
        case .markDone: try? WelcomeModel.markCompleted()
        case .show where !launchedForTask && !CommandLine.arguments.contains("--memory-check"):
            // Recorded as not done yet, so a Welcome that never closed shows again next launch.
            try? Preferences.updateBoolean("welcomeCompleted", value: false)
            showingWelcome = true
            DispatchQueue.main.async { [weak self] in self?.showWelcome() }
        case .show, .skip: break
        }
        if config.showOnLaunch && !showingWelcome && !launchedForTask {
            // AppKit is ready on the next main turn; Spotlight results refresh independently.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.panel.isVisible else { return }
                self.panel.toggle()
            }
        }
        if CommandLine.arguments.contains("--notes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.notesPanel.toggle() }
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.panel.toggle()
                if let i = CommandLine.arguments.firstIndex(of: "--query"), CommandLine.arguments.indices.contains(i + 1) {
                    self.panel.setQuery(CommandLine.arguments[i + 1])
                }
            }
        }
        if CommandLine.arguments.contains("--memory-check") {
            let check = MemoryCheck(steps: .init(
                showLauncher: { [weak self] in if self?.panel.isVisible == false { self?.panel.toggle() } },
                setQuery: { [weak self] in self?.panel.setQuery($0) },
                hideLauncher: { [weak self] in if self?.panel.isVisible == true { self?.panel.toggle() } },
                showSettings: { [weak self] in self?.showSettings() },
                closeSettings: { [weak self] in self?.settingsPanel.window?.close() }))
            memoryCheck = check
            check.run()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { panel.toggle(source: .workspace) }
        else { panel.makeKeyAndOrderFront(nil) }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        breaks.stop()
        breakPresenter.close()
        panel.model.caffeinate.stop()
        panel.model.restoreDictationVolume()
        clipboardMonitor.stop()
        notesStore.flush()
        HotKeyCenter.shared.unregisterAll()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let wing = NSImage(named: "VolantWing") {
            wing.size = NSSize(width: 16, height: 16)
            wing.isTemplate = true
            item.button?.image = wing
        } else {
            item.button?.image = NSImage(systemSymbolName: "arrow.up.forward.circle", accessibilityDescription: "Volant")
        }
        item.button?.setAccessibilityLabel("Volant")
        let menu = StatusMenu.make(target: self, show: #selector(togglePanel), settings: #selector(showSettings), update: #selector(checkForUpdates))
        item.menu = menu
        statusItem = item
    }

    /// Creates the focus bar, reminder and menu bar item, which follow the controller from then on,
    /// and celebrates completed sessions.
    private func startFocus() {
        focus.onComplete = { ConfettiWindow.celebrate() }
        focusActions.edit = { [weak self] in self?.panel.showFocusForm(editing: true) }
        focusActions.resetPosition = { [weak self] in self?.focusBar.resetPosition() }
        focusBar.refresh()
        focusStatusItem.refresh()
        focusNotch.refresh()
        focusReminder.shownElsewhere = { [weak self] in self?.focusNotch.isShowingSession == true }
    }

    /// Starts the Break schedule and its windows. A break pauses a running Focus session and resumes
    /// it afterward; a session the owner had already paused is left paused.
    private func startBreaks() {
        breaks.pauseFocus = { [weak self] in
            guard let self, let session = self.focus.session, !session.isPaused else { return false }
            self.focus.pause()
            self.focus.dismissReminder()
            return true
        }
        breaks.resumeFocus = { [weak self] in
            guard let self, self.focus.session?.isPaused == true else { return }
            self.focus.resume()
        }
        _ = breakPresenter
        breaks.start()
    }

    /// The Toggle Focus Session shortcut: ends the running session, or starts one with the last
    /// setup, opening the form instead when that setup blocks nothing.
    private func toggleFocus() {
        if focus.isRunning { focus.end(); return }
        let setup = config.focus.lastSetup
        guard setup.blocksAnything else { panel.showFocusForm(editing: false); return }
        focus.start(setup)
    }

    private func registerHotKeys() {
        updateDictationEscape(listening: false)
        HotKeyCenter.shared.unregisterAll()
        var failures: [String] = []
        summonRegistered = true
        if let combo = KeyCombo(parsing: config.summonHotKey) {
            if HotKeyCenter.shared.register(combo, handler: { [weak self] in self?.togglePanelFromHotkey() }) == nil {
                summonRegistered = false
                failures.append(String(localized: "Show Volant shortcut unavailable: \(KeyCombo.display(config.summonHotKey))", comment: "Settings error when a global shortcut can't be registered; the value is the key combination"))
            }
        }
        if let combo = KeyCombo(parsing: config.notesHotKey) {
            if HotKeyCenter.shared.register(combo, handler: { [weak self] in self?.toggleNotes() }) == nil {
                failures.append(String(localized: "Open Notes shortcut unavailable: \(KeyCombo.display(config.notesHotKey))", comment: "Settings error when a global shortcut can't be registered; the value is the key combination"))
            }
        }
        if let combo = KeyCombo(parsing: config.emojiHotKey) {
            if HotKeyCenter.shared.register(combo, handler: { [weak self] in
                self?.panel.showEmoji()
            }) == nil { failures.append(String(localized: "Search Emoji shortcut unavailable: \(KeyCombo.display(config.emojiHotKey))", comment: "Settings error when a global shortcut can't be registered; the value is the key combination")) }
        }
        if let combo = KeyCombo(parsing: config.talkHotKey) {
            // The only hotkey that also acts on release: hold it to dictate, let go to transcribe.
            // A quick tap starts and the next tap stops, so both habits work.
            if HotKeyCenter.shared.register(combo, handler: { [weak self] in
                self?.beginDictationFromHotkey()
            }, onRelease: { [weak self] in
                self?.endDictationFromHotkey()
            }) == nil { failures.append(String(localized: "Dictate Text shortcut unavailable: \(KeyCombo.display(config.talkHotKey))", comment: "Settings error when a global shortcut can't be registered; the value is the key combination")) }
        }
        if let combo = KeyCombo(parsing: config.focusHotKey) {
            if HotKeyCenter.shared.register(combo, handler: { [weak self] in self?.toggleFocus() }) == nil {
                failures.append(String(localized: "Toggle Focus Session shortcut unavailable: \(KeyCombo.display(config.focusHotKey))", comment: "Settings error when a global shortcut can't be registered; the value is the key combination"))
            }
        }
        for (value, action) in [(config.lockScreenHotKey, SystemAction.lockScreen), (config.sleepDisplaysHotKey, .sleepDisplays)] {
            guard let combo = KeyCombo(parsing: value) else { continue }
            if HotKeyCenter.shared.register(combo, handler: { [weak self] in self?.performSystemAction(action) }) == nil {
                failures.append(String(localized: "\(action.title) shortcut unavailable: \(KeyCombo.display(value))", comment: "Settings error when a global shortcut can't be registered; the values are the command name and the key combination"))
            }
        }
        failures += AppHotKeys.register(config.appHotKeys) { [weak self] message in
            guard let state = self?.settingsPanel.state else { return }
            if !state.registrationErrors.contains(message) { state.registrationErrors.append(message) }
        }
        settingsPanel.state.registrationErrors = failures
        updateDictationEscape(listening: panel.model.dictationIndicator.isListening)
    }

    private func installApplicationMenu() {
        let bar = NSMenu()
        let item = NSMenuItem()
        bar.addItem(item)
        let menu = NSMenu(title: "Volant")
        menu.addItem(withTitle: String(localized: "Agents…", comment: "Application menu item"), action: #selector(showAgents), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Check for Updates…", comment: "Application menu item"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        let settings = menu.addItem(withTitle: String(localized: "Settings…", comment: "Application menu item"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Volant", comment: "Application menu item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        item.submenu = menu
        // Preserve standard text-editing shortcuts in the native notes editor.
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let edit = NSMenu(title: String(localized: "Edit", comment: "Edit menu title in the menu bar"))
        for (title, selector, key) in [(String(localized: "Undo", comment: "Edit menu item"), "undo:", "z"), (String(localized: "Cut", comment: "Edit menu item"), "cut:", "x"), (String(localized: "Copy", comment: "Edit menu item"), "copy:", "c"), (String(localized: "Paste", comment: "Edit menu item"), "paste:", "v"), (String(localized: "Select All", comment: "Edit menu item"), "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = edit
        NSApp.mainMenu = bar
    }

    @objc private func showAgents() {
        NSApp.activate(ignoringOtherApps: true)
        panel.showAgents()
    }

    @objc private func checkForUpdates() { updater.checkForUpdates() }

    @objc private func showSettings() {
        panel.orderOut(nil)
        settingsPanel.refresh(config, apps: index.apps)
        settingsPanel.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleNotes() { notesPanel.toggle() }

    /// Opens the Welcome window, from the first launch, the `welcome` command or Settings › About.
    /// Its buttons close it before showing the launcher, AI Chat or Settings, and closing it records it
    /// as done on this Mac.
    @objc func showWelcome() {
        panel.orderOut(nil)
        if let welcome { welcome.present(); return }
        let actions = WelcomeActions(
            tryQuery: { [weak self] text in
                guard let self else { return }
                self.welcome?.close()
                if !self.panel.isVisible { self.panel.toggle() }
                self.panel.setQuery(text)
            },
            connectAgent: { [weak self] provider in
                guard let self else { return }
                self.welcome?.close()
                if !self.panel.isVisible { self.panel.toggle() }
                self.panel.model.chooseAIProvider(provider)
            },
            browseCatalog: { [weak self] in
                guard let self else { return }
                self.welcome?.close()
                if !self.panel.isVisible { self.panel.toggle() }
                self.panel.model.openExtensionCatalog()
            },
            openDictationSettings: { [weak self] in
                self?.showSettings()
                self?.settingsPanel.state.section = .dictation
            },
            openAISettings: { [weak self] in self?.showAISettings() },
            configChanged: { [weak self] in self?.reloadConfig() })
        let model = WelcomeModel(config: config, summonRegistered: summonRegistered, actions: actions)
        let controller = WelcomeWindowController(model: model) { [weak self] in
            try? WelcomeModel.markCompleted()
            self?.reloadConfig()
        }
        welcome = controller
        controller.present()
    }

    /// Held long enough to be a hold rather than a tap, the release stops dictation. A tap leaves
    /// it listening so the same key can stop it, which is how push-to-talk and toggle both work.
    private var dictationPressedAt: Date?

    private func beginDictationFromHotkey() {
        let model = panel.model
        if model.dictation.isListening {
            dictationPressedAt = nil
            model.finishDictation()
            return
        }
        dictationPressedAt = Date()
        _ = dictationIndicator
        model.toggleDictation(stopHint: String(localized: "Release or press \(KeyCombo.display(config.talkHotKey)) to stop", comment: "Dictation indicator hint; the value is the dictation key combination"), surface: .indicator)
    }

    /// Holds unmodified Escape as a Carbon hotkey only while the indicator is listening, so Escape
    /// cancels without Volant taking focus, plus unmodified Return to finish when the dictation
    /// types at the cursor, and tells the indicator which of them to mention.
    private func updateDictationEscape(listening: Bool) {
        let model = panel.model
        model.dictationIndicator.escapeCancels = dictationEscape.update(
            listening: listening, finishesOnReturn: model.dictationTypesAtCursor,
            onEscape: { [weak model] in model?.cancelDictation() },
            onReturn: { [weak model] in model?.finishDictation() })
        model.dictationIndicator.returnFinishes = dictationEscape.isReturnRegistered
    }

    private func endDictationFromHotkey() {
        guard let pressedAt = dictationPressedAt else { return }
        dictationPressedAt = nil
        guard Date().timeIntervalSince(pressedAt) >= 0.4 else { return }
        panel.model.finishDictation()
    }

    private func togglePanelFromHotkey() {
        let started = ProcessInfo.processInfo.systemUptime
        panel.toggle(source: .hotkey, requestedAt: started)
    }
    @objc private func togglePanel() { panel.toggle(source: .menu) }

    /// Created on first use, so the camera is never touched before Open Camera is chosen.
    private lazy var cameraWindow: CameraPreviewWindow = {
        let window = CameraPreviewWindow()
        window.onFailure = { [weak self] message in
            guard let self else { return }
            if !self.panel.isVisible { self.panel.toggle() }
            self.panel.model.actionFeedback = message
        }
        return window
    }()

    private func showCamera() { cameraWindow.present() }

    /// One path for the launcher and the hotkeys. The launcher is hidden first and the action
    /// runs a moment later, so it is not on screen when the Mac locks or a dialog appears. A
    /// failure reopens the launcher with the reason rather than failing silently.
    private func performSystemAction(_ action: SystemAction) {
        panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let problem = SystemActions.perform(action) else { return }
            if !self.panel.isVisible { self.panel.toggle() }
            self.panel.model.actionFeedback = problem
        }
    }

    /// Applies the color theme and its light or dark appearance; a nil appearance follows macOS,
    /// including its automatic switching.
    private func applyTheme() {
        let appearance = config.appearance
        MainActor.assumeIsolated { ThemeStore.shared.apply(appearance) }
    }

    @objc private func reloadConfig() {
        let loaded = Preferences.load()
        if let error = Preferences.loadError {
            let alert = NSAlert()
            alert.messageText = String(localized: "Configuration not applied", comment: "Alert title when config.json couldn't be loaded")
            alert.informativeText = error
            if let window = settingsPanel.window { settingsPanel.showWindow(nil); alert.beginSheetModal(for: window) }
            return
        }
        config = loaded
        breaks.apply(config.breaks)
        if config.dictationOutput == .copy, !config.searchMenuItems, !panel.model.dictationTypesAtCursor { inputHost.disconnect() }
        NSApp.setActivationPolicy(config.showInDock ? .regular : .accessory)
        applyTheme()
        settingsPanel.refresh(config, apps: index.apps)
        registerHotKeys()
        welcome?.model.refresh(config: config, summonRegistered: summonRegistered)
        panel.apply(config: config)
        if rexOverviewCreated { rexOverview.model.updateAllowed(config.rexPanePreviews) }
        if let ai = try? AIConfiguration.load() { panel.model.conversations.apply(ai) }
        clipboardStore.retention = config.clipboardRetention
        settingsSync.update(enabled: config.syncSettingsWithICloud)
        notesSync.update(enabled: config.syncSettingsWithICloud)
        currencyRates.keyChanged()
    }
}
