import AppKit
import VolantCore

private final class RaycastImportSurface: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Passwords remain in process memory, never preferences, logs, arguments, or temporary files.
final class RaycastImportWindowController: NSWindowController, NSWindowDelegate {
    private let password = NSSecureTextField()
    private let fileLabel = NSTextField(wrappingLabelWithString: String(localized: "Choose a .rayconfig export from Raycast.", comment: "Raycast import window file label"))
    private let status = NSTextField(wrappingLabelWithString: String(localized: "Your password is used locally and is not saved.", comment: "Raycast import window status"))
    private let choose = NSButton(title: String(localized: "Choose Export…", comment: "Raycast import window button"), target: nil, action: nil)
    private let unlock = NSButton(title: String(localized: "Unlock & Preview", comment: "Raycast import window button"), target: nil, action: nil)
    private let applyButton = NSButton(title: String(localized: "Import Selected", comment: "Raycast import window button"), target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let details = NSTextView()
    private var choices: [RaycastCategory: NSButton] = [:]
    private var archive: Data?
    private var plan: RaycastImportPlan?
    private var generation = UUID()
    private var recovery: URL?
    private let reveal = NSButton(title: String(localized: "Show Recovery Backup", comment: "Raycast import window button"), target: nil, action: nil)
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 670), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Import from Raycast", comment: "Raycast import window title")
        window.minSize = NSSize(width: 560, height: 630)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = RaycastImportSurface(frame: NSRect(x: 0, y: 0, width: 660, height: 670))
        choose.target = self; choose.action = #selector(chooseFile)
        unlock.target = self; unlock.action = #selector(unlockFile); unlock.isEnabled = false
        applyButton.target = self; applyButton.action = #selector(applyImport); applyButton.isEnabled = false
        reveal.target = self; reveal.action = #selector(showRecovery); reveal.isHidden = true
        [choose, unlock, applyButton, reveal].forEach { $0.bezelStyle = .rounded }
        password.placeholderString = String(localized: "Export password", comment: "Raycast import password field placeholder")
        password.setAccessibilityLabel(String(localized: "Raycast export password", comment: "Accessibility label for the Raycast import password field"))
        password.target = self; password.action = #selector(unlockFile)
        password.isEnabled = false
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let title = NSTextField(labelWithString: String(localized: "Bring your setup with you.", comment: "Raycast import window heading"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: String(localized: "Preview what can move to Volant. Existing items are kept, and a recovery backup is created before import.", comment: "Raycast import window subtitle"))
        subtitle.textColor = .secondaryLabelColor
        fileLabel.textColor = .secondaryLabelColor
        status.textColor = .secondaryLabelColor
        let fileRow = NSStackView(views: [choose, fileLabel]); fileRow.spacing = 12
        let passwordRow = NSStackView(views: [password, unlock, progress]); passwordRow.spacing = 12
        password.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        let categoryRow = NSStackView(); categoryRow.orientation = .vertical; categoryRow.alignment = .leading; categoryRow.spacing = 7
        for category in RaycastCategory.allCases {
            let button = NSButton(checkboxWithTitle: category.rawValue, target: self, action: #selector(updateSelection))
            button.isEnabled = false
            choices[category] = button; categoryRow.addArrangedSubview(button)
        }
        details.isEditable = false; details.isSelectable = true; details.font = .systemFont(ofSize: 12)
        details.textColor = .labelColor; details.backgroundColor = .textBackgroundColor
        details.textContainerInset = NSSize(width: 10, height: 10)
        details.autoresizingMask = [.width]; details.isVerticallyResizable = true; details.isHorizontallyResizable = false
        details.textContainer?.widthTracksTextView = true
        details.setAccessibilityLabel(String(localized: "Import preview and compatibility report", comment: "Accessibility label for the Raycast import report"))
        let scroll = NSScrollView(); scroll.documentView = details; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let buttons = NSStackView(views: [reveal, applyButton]); buttons.spacing = 12
        let stack = NSStackView(views: [title, subtitle, fileRow, passwordRow, categoryRow, scroll, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
                scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
                passwordRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
                status.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func chooseFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a Raycast schema 3 .rayconfig export.", comment: "Raycast import file picker message")
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            self.reset()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= RaycastArchive.fileLimit else { throw RaycastArchive.failure(String(localized: "Choose an export smaller than 64 MB.", comment: "Raycast import error")) }
                let data = try Data(contentsOf: url)
                guard data.starts(with: Data("RAYCFG3\n".utf8)) else { throw RaycastArchive.failure(String(localized: "This is not a supported schema 3 Raycast export.", comment: "Raycast import error")) }
                self.archive = data; self.fileLabel.stringValue = url.lastPathComponent
                self.password.isEnabled = true; self.unlock.isEnabled = true
                window.makeFirstResponder(self.password)
            } catch { self.status.stringValue = error.localizedDescription }
        }
    }
    @objc private func unlockFile() {
        guard let data = archive, unlock.isEnabled else { return }
        guard !password.stringValue.isEmpty, password.stringValue.utf8.count <= 4096 else { status.stringValue = String(localized: "Enter the export password (up to 4,096 UTF-8 bytes).", comment: "Raycast import window status"); return }
        let secret = password.stringValue
        password.stringValue = ""
        let token = UUID(); generation = token
        plan = nil; applyButton.isEnabled = false; choices.values.forEach { $0.isEnabled = false }
        choose.isEnabled = false; unlock.isEnabled = false; password.isEnabled = false
        details.string = ""; status.stringValue = String(localized: "Unlocking locally…", comment: "Raycast import window status"); progress.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try RaycastImportPlan.make(payload: RaycastArchive.decode(data, password: secret)) }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.progress.stopAnimation(nil); self.choose.isEnabled = true; self.unlock.isEnabled = true; self.password.isEnabled = true
                do { self.showPreview(try result.get()) }
                catch { self.status.stringValue = error.localizedDescription; self.window?.makeFirstResponder(self.password) }
            }
        }
    }
    /// Also used by the isolated native rendering fixture.
    func showPreview(_ incoming: RaycastImportPlan) {
        plan = incoming
        for category in RaycastCategory.allCases {
            let count = incoming.count(category)
            choices[category]?.title = String(localized: "\(category.rawValue) — \(count) new", comment: "Raycast import category checkbox; the values are the category and how many new items it has")
            choices[category]?.isEnabled = count > 0
            choices[category]?.state = count > 0 && category != .hotkeys ? .on : .off
        }
        var lines = [String(localized: "READY TO ADD", comment: "Raycast import report section heading")]
        lines += incoming.snippets.map { String(localized: "Snippet: \($0.name)", comment: "Raycast import report line") }
        lines += incoming.quicklinks.map { String(localized: "Quicklink: \($0.name) → \($0.url)", comment: "Raycast import report line; the values are the quicklink name and URL") }
        lines += incoming.aliases.keys.sorted().map { String(localized: "Alias: \($0) → \(incoming.aliases[$0, default: ""])", comment: "Raycast import report line; the values are the alias and its app") }
        lines += incoming.hotkeys.map { String(localized: "Hotkey: \(KeyCombo.display($0.hotKey)) → \($0.bundleIdentifier)", comment: "Raycast import report line; the values are the key combination and the app's bundle identifier") }
        lines += incoming.notes.values.sorted().map { note in
            note.split(separator: "\n").first.map { String(localized: "Note: \(String($0))", comment: "Raycast import report line; the value is the note's first line") }
                ?? String(localized: "Note: Untitled", comment: "Raycast import report line")
        }
        lines += ["", String(localized: "COMPATIBILITY & CONFLICTS", comment: "Raycast import report section heading")] + incoming.report
        details.string = lines.joined(separator: "\n\n")
        updateSelection()
    }
    @objc private func updateSelection() {
        let total = RaycastCategory.allCases.filter { choices[$0]?.state == .on }.reduce(0) { $0 + (plan?.count($1) ?? 0) }
        applyButton.isEnabled = total > 0
        status.stringValue = total > 0 ? String(localized: "\(total) items selected. Review the report before importing.", comment: "Raycast import window status") : String(localized: "No new items selected. Review skipped items in the report.", comment: "Raycast import window status")
    }
    @objc private func applyImport() {
        guard let plan else { return }
        do {
            recovery = try plan.apply(Set(RaycastCategory.allCases.filter { choices[$0]?.state == .on }))
            self.plan = nil; archive = nil; password.stringValue = ""
            applyButton.isEnabled = false; unlock.isEnabled = false; password.isEnabled = false
            choices.values.forEach { $0.isEnabled = false }
            reveal.isHidden = false; status.stringValue = String(localized: "Import complete. Existing items were kept. Your recovery backup is available below.", comment: "Raycast import window status")
            onChange()
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func showRecovery() { if let recovery { NSWorkspace.shared.activateFileViewerSelecting([recovery]) } }
    private func reset() {
        generation = UUID(); archive = nil; plan = nil; recovery = nil
        password.stringValue = ""; details.string = ""; reveal.isHidden = true
        progress.stopAnimation(nil); choose.isEnabled = true; unlock.isEnabled = false; applyButton.isEnabled = false; password.isEnabled = false
        fileLabel.stringValue = String(localized: "Choose a .rayconfig export from Raycast.", comment: "Raycast import window file label")
        status.stringValue = String(localized: "Your password is used locally and is not saved.", comment: "Raycast import window status")
        for category in RaycastCategory.allCases { choices[category]?.title = category.rawValue; choices[category]?.state = .off; choices[category]?.isEnabled = false }
    }
    func windowWillClose(_ notification: Notification) { reset() }
}
