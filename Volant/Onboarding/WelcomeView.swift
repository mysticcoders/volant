import SwiftUI
import VolantCore

/// The first-run Welcome window: one page per step, with step dots, Back, Skip and Continue.
struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                page.padding(.horizontal, 36).padding(.top, 36).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            WelcomeFooter(model: model, finish: finish).padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(String(localized: "Couldn’t save that", comment: "Welcome window error title"),
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .shortcut: WelcomeShortcutPage(model: model)
        case .typing: WelcomeTypingPage(model: model)
        case .access: WelcomeAccessPage(model: model)
        case .agents: WelcomeAgentsPage(model: model)
        case .extensions: WelcomeExtensionsPage(model: model)
        }
    }
}

/// Step dots, then Back, Skip and Continue, or Done on the last page.
private struct WelcomeFooter: View {
    @ObservedObject var model: WelcomeModel
    let finish: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(model.steps) { step in
                    Circle().fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepLabel)
            Spacer()
            if !model.isFirstStep { Button("Back", action: model.back) }
            if !model.isLastStep {
                Button(String(localized: "Skip Setup", comment: "Welcome window button that closes it from any page"), action: finish)
                Button("Continue", action: model.next).keyboardShortcut(.defaultAction)
            } else {
                Button("Done", action: finish).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var stepLabel: String {
        let index = (model.steps.firstIndex(of: model.step) ?? 0) + 1
        return String(localized: "Step \(index, specifier: "%lld") of \(model.steps.count, specifier: "%lld")", comment: "Welcome window step dots, read by VoiceOver")
    }
}

/// A page's title and one-line introduction.
private struct WelcomeHeader: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(detail).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 18)
    }
}

/// Page 1: the summon shortcut, with the Settings recorder and a plain warning when it may not work.
private struct WelcomeShortcutPage: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomeHeader(title: String(localized: "Welcome to Volant", comment: "Welcome window title"),
                          detail: String(localized: "Apps, files, answers, notes and agents, one shortcut away. Let’s set it up.", comment: "Welcome window introduction"))
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your shortcut").font(.headline)
                    Text(shortcutSentence).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ShortcutControl(title: String(localized: "Show Volant", comment: "Keyboard Shortcuts settings row"), value: model.config.summonHotKey) { value in
                    try model.saveSummon(value, available: { HotKeyCenter.shared.isAvailable($0) })
                }
                .frame(width: 170)
            }
            .padding(16).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if !model.summonRegistered {
                WelcomeNotice(symbol: "exclamationmark.triangle.fill", tint: .orange,
                              text: String(localized: "macOS or another app is already using this shortcut, so it doesn’t open Volant yet. Choose another one above.", comment: "Welcome window warning when the summon shortcut failed to register"))
            } else if !model.competingLaunchers.isEmpty {
                WelcomeNotice(symbol: "info.circle.fill", tint: .blue,
                              text: String(localized: "\(model.competingLaunchers.formatted(.list(type: .and))) is running and may use the same shortcut. If pressing it opens the other app, choose another one above.", comment: "Welcome window note; the value names other running launchers, such as Raycast"))
            }
            Text("You can change it any time in Settings › Keyboard Shortcuts.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var shortcutSentence: String {
        let shortcut = KeyCombo.display(model.config.summonHotKey)
        return shortcut.isEmpty
            ? String(localized: "No shortcut is set. Record one to open Volant from anywhere.", comment: "Welcome window when the summon shortcut is empty")
            : String(localized: "Volant opens with \(shortcut, format: .verbatim). Press it from any app.", comment: "Welcome window; the value is a key combination such as ⌥Space")
    }
}

/// A short highlighted note under a control.
private struct WelcomeNotice: View {
    let symbol: String
    let tint: Color
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
    }
}

/// Page 2: what can be typed, each line with Try It.
private struct WelcomeTypingPage: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WelcomeHeader(title: String(localized: "What you can type", comment: "Welcome window page title"),
                          detail: String(localized: "Type to find apps or calculate. These words and characters jump straight to one thing.", comment: "Welcome window page introduction"))
            ForEach(WelcomeTip.all) { tip in
                WelcomeTipRow(tip: tip) { model.actions.tryQuery(tip.tryQuery) }
                if tip != WelcomeTip.all.last { Divider() }
            }
        }
    }
}

private struct WelcomeTipRow: View {
    let tip: WelcomeTip
    let tryIt: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tip.symbol).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(verbatim: tip.typed).font(.body.monospaced()).frame(width: 190, alignment: .leading)
            Text(tip.detail).foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Try It", comment: "Welcome window button that opens the launcher with an example typed"), action: tryIt)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Try \(tip.typed, format: .verbatim)", comment: "Accessibility label of a Welcome Try It button; the value is launcher syntax"))
        }
        .padding(.vertical, 7)
    }
}

/// Page 3: permissions, each with what it unlocks and one button. Opening this page never prompts.
private struct WelcomeAccessPage: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WelcomeHeader(title: String(localized: "Allow access", comment: "Welcome window page title"),
                          detail: String(localized: "Allow only what you’ll use. Anything you skip, Volant asks for the first time you need it.", comment: "Welcome window page introduction"))
            ForEach(model.shownPermissions) { permission in
                WelcomePermissionRow(permission: permission, status: model.permissions[permission] ?? .notDetermined) { model.request(permission) }
                Divider()
            }
            WelcomeAccessRow(symbol: "power", title: String(localized: "Open at Login", comment: "Welcome window access row"),
                             detail: String(localized: "Volant is ready after you restart your Mac.", comment: "Welcome window access row detail")) {
                Toggle("", isOn: Binding(get: { model.loginStatus == .enabled }, set: model.setOpenAtLogin)).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            WelcomeAccessRow(symbol: "keyboard", title: String(localized: "Type dictation at the cursor", comment: "Welcome window access row"),
                             detail: String(localized: "Optional. Needs Accessibility, set up in Settings › Dictation.", comment: "Welcome window access row detail")) {
                Button(String(localized: "Set Up…", comment: "Welcome window button opening Settings › Dictation"), action: model.actions.openDictationSettings)
            }
            Divider()
            WelcomeAccessRow(symbol: "wifi", title: String(localized: "Location and Bluetooth", comment: "Welcome window access row"),
                             detail: String(localized: "Asked the first time you use Wi-Fi or Bluetooth.", comment: "Welcome window access row detail")) { EmptyView() }
        }
    }
}

/// One access row: icon, name and what it unlocks, with its control at the trailing edge.
private struct WelcomeAccessRow<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let control: () -> Control
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 26).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 9)
    }
}

private struct WelcomePermissionRow: View {
    let permission: WelcomePermission
    let status: WelcomePermissionStatus
    let request: () -> Void

    var body: some View {
        WelcomeAccessRow(symbol: symbol, title: title, detail: detail) {
            switch status {
            case .allowed:
                Label(String(localized: "Allowed", comment: "Welcome window permission state"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Button(String(localized: "Open System Settings", comment: "Welcome window button for a denied permission")) { NSWorkspace.shared.open(permission.settingsURL) }
            case .notDetermined:
                Button(String(localized: "Allow", comment: "Welcome window button that asks macOS for a permission"), action: request)
            }
        }
    }

    private var symbol: String {
        switch permission {
        case .contacts: return "person.crop.circle"
        case .calendars: return "calendar"
        case .microphone: return "mic"
        }
    }
    private var title: String {
        switch permission {
        case .contacts: return String(localized: "Contacts", comment: "Welcome window access row")
        case .calendars: return String(localized: "Calendars", comment: "Welcome window access row")
        case .microphone: return String(localized: "Microphone", comment: "Welcome window access row")
        }
    }
    private var detail: String {
        switch permission {
        case .contacts: return String(localized: "Search people with @ or contacts.", comment: "Welcome window access row detail; @ and contacts are typed launcher syntax")
        case .calendars: return String(localized: "See your day with cal or today.", comment: "Welcome window access row detail; cal and today are typed launcher commands")
        case .microphone: return String(localized: "Dictate with talk or your dictation shortcut.", comment: "Welcome window access row detail; talk is a typed launcher command")
        }
    }
}

/// Page 4, only when something was found: chat agents and agent terminals, each connected or shown in
/// the status bar only on a click.
private struct WelcomeAgentsPage: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WelcomeHeader(title: String(localized: "Your agents", comment: "Welcome window page title"),
                          detail: String(localized: "Volant found these on your Mac. Nothing connects until you choose it.", comment: "Welcome window page introduction"))
            ForEach(model.agents) { agent in
                WelcomeAgentRow(model: model, agent: agent)
                Divider()
            }
        }
    }
}

private struct WelcomeAgentRow: View {
    @ObservedObject var model: WelcomeModel
    let agent: WelcomeAgent

    var body: some View {
        WelcomeAccessRow(symbol: symbol, title: agent.title, detail: detail) {
            HStack(spacing: 10) {
                Toggle(String(localized: "Show Status", comment: "Welcome window toggle that shows an agent's activity in the launcher status bar"),
                       isOn: Binding(get: { model.showsStatus(agent) }, set: { model.setShowsStatus(agent, $0) }))
                    .toggleStyle(.checkbox)
                if case .chat(let provider) = agent.kind {
                    if agent.ready { Button(String(localized: "Chat", comment: "Welcome window button that opens AI Chat with this agent")) { model.actions.connectAgent(provider) } }
                    else { Button(String(localized: "Set Up…", comment: "Welcome window button opening Settings › AI"), action: model.actions.openAISettings) }
                }
            }
        }
    }

    private var symbol: String {
        switch agent.kind {
        case .chat: return "bubble.left.and.bubble.right"
        case .rex, .herdr: return "terminal"
        }
    }
    private var detail: String {
        switch agent.kind {
        case .chat: return agent.ready
            ? String(localized: "Chat with it in AI Chat. Type ai any time.", comment: "Welcome window agent detail; ai is a typed launcher command")
            : String(localized: "Installed, but needs setup before AI Chat can use it.", comment: "Welcome window agent detail")
        case .rex: return String(localized: "See which Rex panes need you. Type rex.", comment: "Welcome window agent detail; rex is a typed launcher command")
        case .herdr: return String(localized: "See which Herdr agents need you. Type herdr.", comment: "Welcome window agent detail; herdr is a typed launcher command")
        }
    }
}

/// The last page: the extensions on this Mac with their usual switches, the catalog, and GitHub.
private struct WelcomeExtensionsPage: View {
    @ObservedObject var model: WelcomeModel
    @State private var confirming: InstalledExtension?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WelcomeHeader(title: String(localized: "Extensions", comment: "Welcome window page title"),
                          detail: String(localized: "Extensions start off and run only when you invoke them. Turn on the ones you want.", comment: "Welcome window page introduction"))
            ForEach(model.extensions) { ext in
                WelcomeExtensionRow(ext: ext) { enabled in
                    if enabled && !model.missingHosts(ext).isEmpty { confirming = ext } else { model.setEnabled(ext, enabled) }
                }
                Divider()
            }
            HStack(spacing: 12) {
                Button(String(localized: "Browse the Catalog…", comment: "Welcome window button that opens the extension catalog"), action: model.actions.browseCatalog)
                Spacer()
            }
            .padding(.top, 14)
            WelcomeStarCard { model.actions.openURL(URL(string: "https://github.com/mysticcoders/volant")!) }.padding(.top, 24)
        }
        .sheet(item: $confirming) { ext in
            VStack(alignment: .leading, spacing: 16) {
                Text("Enable \(ext.name)?").font(.title2.bold())
                ExtensionHostList(hosts: model.missingHosts(ext))
                HStack {
                    Spacer()
                    Button("Cancel") { confirming = nil }.keyboardShortcut(.cancelAction)
                    Button("Allow and Enable") { confirming = nil; model.setEnabled(ext, true) }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 420).background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct WelcomeExtensionRow: View {
    let ext: InstalledExtension
    let setEnabled: (Bool) -> Void
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = ExtensionIcon.image(for: ext) {
                    Image(nsImage: icon).resizable().clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "puzzlepiece.extension").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(ext.name, isOn: Binding(get: { ext.enabled }, set: setEnabled))
                .labelsHidden().toggleStyle(.switch)
                .disabled(ext.communityBlocked || ext.revocation != nil)
        }
        .padding(.vertical, 9)
    }

    private var detail: String {
        ext.isCommunity
            ? String(localized: "From the catalog · \(ext.manifest.version, format: .verbatim)", comment: "Welcome window extension detail; the value is a version number")
            : String(localized: "Built in · \(ext.manifest.version, format: .verbatim)", comment: "Welcome window extension detail; the value is a version number")
    }
}

/// The GitHub star request: a sentence and one button that opens the project page in the browser.
private struct WelcomeStarCard: View {
    let star: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.fill").font(.title2).foregroundStyle(.yellow).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Like Volant?").font(.headline)
                Text("A star on GitHub helps other people find it.").foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: star) {
                Label(String(localized: "Star on GitHub", comment: "About settings link that opens Volant's GitHub page, where people can star the project"), systemImage: "star")
            }
        }
        .padding(16).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
