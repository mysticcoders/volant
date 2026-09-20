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
    private let fileLabel = NSTextField(wrappingLabelWithString: "Choose a .rayconfig export from Raycast.")
    private let status = NSTextField(wrappingLabelWithString: "Your password is used locally and is not saved.")
    private let choose = NSButton(title: "Choose Export…", target: nil, action: nil)
    private let unlock = NSButton(title: "Unlock & Preview", target: nil, action: nil)
    private let applyButton = NSButton(title: "Import Selected", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let details = NSTextView()
    private var choices: [RaycastCategory: NSButton] = [:]
    private var archive: Data?
    private var plan: RaycastImportPlan?
    private var generation = UUID()
    private var recovery: URL?
    private let reveal = NSButton(title: "Show Recovery Backup", target: nil, action: nil)
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 670), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Import from Raycast"
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
        password.placeholderString = "Export password"
        password.setAccessibilityLabel("Raycast export password")
        password.target = self; password.action = #selector(unlockFile)
        password.isEnabled = false
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let title = NSTextField(labelWithString: "Bring your setup with you.")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Preview what can move to Volant. Existing items are kept, and a recovery backup is created before import.")
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
        details.setAccessibilityLabel("Import preview and compatibility report")
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
        panel.message = "Choose a Raycast schema 3 .rayconfig export."
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            self.reset()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= RaycastArchive.fileLimit else { throw RaycastArchive.failure("Choose an export smaller than 64 MB.") }
                let data = try Data(contentsOf: url)
                guard data.starts(with: Data("RAYCFG3\n".utf8)) else { throw RaycastArchive.failure("This is not a supported schema 3 Raycast export.") }
                self.archive = data; self.fileLabel.stringValue = url.lastPathComponent
                self.password.isEnabled = true; self.unlock.isEnabled = true
                window.makeFirstResponder(self.password)
            } catch { self.status.stringValue = error.localizedDescription }
        }
    }
    @objc private func unlockFile() {
        guard let data = archive, unlock.isEnabled else { return }
        guard !password.stringValue.isEmpty, password.stringValue.utf8.count <= 4096 else { status.stringValue = "Enter the export password (up to 4,096 UTF-8 bytes)."; return }
        let secret = password.stringValue
        password.stringValue = ""
        let token = UUID(); generation = token
        plan = nil; applyButton.isEnabled = false; choices.values.forEach { $0.isEnabled = false }
        choose.isEnabled = false; unlock.isEnabled = false; password.isEnabled = false
        details.string = ""; status.stringValue = "Unlocking locally…"; progress.startAnimation(nil)
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
            choices[category]?.title = "\(category.rawValue) — \(count) new"
            choices[category]?.isEnabled = count > 0
            choices[category]?.state = count > 0 && category != .hotkeys ? .on : .off
        }
        var lines = ["READY TO ADD"]
        lines += incoming.snippets.map { "Snippet: \($0.name)" }
        lines += incoming.quicklinks.map { "Quicklink: \($0.name) → \($0.url)" }
        lines += incoming.aliases.keys.sorted().map { "Alias: \($0) → \(incoming.aliases[$0, default: ""])" }
        lines += incoming.hotkeys.map { "Hotkey: \(KeyCombo.display($0.hotKey)) → \($0.bundleIdentifier)" }
        lines += incoming.notes.values.sorted().map { "Note: \($0.split(separator: "\n").first.map(String.init) ?? "Untitled")" }
        lines += ["", "COMPATIBILITY & CONFLICTS"] + incoming.report
        details.string = lines.joined(separator: "\n\n")
        updateSelection()
    }
    @objc private func updateSelection() {
        let total = RaycastCategory.allCases.filter { choices[$0]?.state == .on }.reduce(0) { $0 + (plan?.count($1) ?? 0) }
        applyButton.isEnabled = total > 0
        status.stringValue = total > 0 ? "\(total) items selected. Review the report before importing." : "No new items selected. Review skipped items in the report."
    }
    @objc private func applyImport() {
        guard let plan else { return }
        do {
            recovery = try plan.apply(Set(RaycastCategory.allCases.filter { choices[$0]?.state == .on }))
            self.plan = nil; archive = nil; password.stringValue = ""
            applyButton.isEnabled = false; unlock.isEnabled = false; password.isEnabled = false
            choices.values.forEach { $0.isEnabled = false }
            reveal.isHidden = false; status.stringValue = "Import complete. Existing items were kept. Your recovery backup is available below."
            onChange()
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func showRecovery() { if let recovery { NSWorkspace.shared.activateFileViewerSelecting([recovery]) } }
    private func reset() {
        generation = UUID(); archive = nil; plan = nil; recovery = nil
        password.stringValue = ""; details.string = ""; reveal.isHidden = true
        progress.stopAnimation(nil); choose.isEnabled = true; unlock.isEnabled = false; applyButton.isEnabled = false; password.isEnabled = false
        fileLabel.stringValue = "Choose a .rayconfig export from Raycast."
        status.stringValue = "Your password is used locally and is not saved."
        for category in RaycastCategory.allCases { choices[category]?.title = category.rawValue; choices[category]?.state = .off; choices[category]?.isEnabled = false }
    }
    func windowWillClose(_ notification: Notification) { reset() }
}
