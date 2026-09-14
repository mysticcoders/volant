import SwiftUI

struct ACPConversationView: View {
    @ObservedObject var model: ACPModel
    @State private var follow = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if model.active {
                    Text(model.provider == "cursor" ? "Cursor" : "OpenCode").fontWeight(.medium)
                    Label(URL(fileURLWithPath: model.project).lastPathComponent, systemImage: "folder")
                        .foregroundStyle(.secondary).lineLimit(1).help(model.project)
                } else {
                    Picker("Provider", selection: $model.provider) {
                        Text("OpenCode").tag("opencode")
                        Text("Cursor").tag("cursor")
                    }.labelsHidden().frame(width: 125)
                    Button(action: model.chooseProject) {
                        Label(model.project.isEmpty ? "Choose project…" : URL(fileURLWithPath: model.project).lastPathComponent, systemImage: "folder").lineLimit(1)
                    }.help(model.project)
                }
                Spacer(minLength: 4)
                if model.active { Button("End", action: model.disconnect) }
                else { Button("Start", action: model.start).disabled(model.project.isEmpty) }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.state.messages.isEmpty {
                        Text("A conversation in your project")
                            .font(.headline)
                        Text("Uses your provider’s existing login and tool permissions. Your chosen folder is the working directory; it does not sandbox the agent.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Volant sends only the prompt you write here. Sign in through the provider’s CLI before starting.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.state.messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.role).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(message.text).font(.system(size: 14)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(model.state.permissions) { permission in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(permission.title, systemImage: "hand.raised").font(.headline)
                            DisclosureGroup("Operation details") {
                                Text(permission.detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            }
                            // No default approval or Return shortcut. The user selects the exact agent-provided option.
                            ViewThatFits(in: .horizontal) {
                                HStack { permissionButtons(permission) }
                                VStack(alignment: .leading) { permissionButtons(permission) }
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)).id(permission.id)
                    }
                    if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let permission = model.state.permissions.first { proxy.scrollTo(permission.id, anchor: .top) }
                    else if follow { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                }
            }
            .onChange(of: model.state.messages) { _, _ in
                if follow { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.state.permissions) { _, _ in
                if let permission = model.state.permissions.first { proxy.scrollTo(permission.id, anchor: .top) }
            }
            }
            Divider()
            HStack(spacing: 8) {
                if model.state.busy && model.state.permissions.isEmpty { ProgressView().controlSize(.small) }
                Text(model.state.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).font(.caption)
                if ["working", "cancelling"].contains(model.state.phase) {
                    Button("Cancel", action: model.cancel).disabled(model.state.phase == "cancelling")
                }
            }.padding(.horizontal, 16).padding(.vertical, 6)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask your agent…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...4).font(.system(size: 14))
                    .padding(9).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Agent prompt")
                Button("Send", action: model.send).disabled(!model.canSend)
                    .keyboardShortcut(.return, modifiers: .command)
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
    }
    private func permissionButtons(_ permission: ACPPermission) -> some View {
        ForEach(permission.options) { option in
            Button(option.name) { model.choose(permission, option) }
                .help(option.kind.replacingOccurrences(of: "_", with: " "))
                .disabled(model.state.phase != "working")
        }
    }
}


struct ACPActivityStrip: View {
    @ObservedObject var model: ACPModel
    var open: () -> Void
    var body: some View {
        if model.active {
            Button(action: open) {
                HStack {
                    Image(systemName: model.state.permissions.isEmpty ? "bubble.left.and.bubble.right" : "hand.raised")
                    Text(model.provider == "cursor" ? "Cursor" : "OpenCode")
                    Text(model.state.status).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("Open conversation").foregroundStyle(.secondary)
                }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 8)
            }.buttonStyle(.plain)
            Divider()
        }
    }
}
