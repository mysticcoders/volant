import SwiftUI

struct WiFiJoinView: View {
    @ObservedObject var model: LauncherModel
    let network: WiFiChoice
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    private func cancel() {
        guard !model.connectivityBusy else { return }
        password = ""; model.wifiJoin = nil; model.searchFocusRequest = UUID()
    }
    private func submit() {
        guard !password.isEmpty, !model.connectivityBusy else { return }
        model.joinWiFi(network, password: password, useSaved: false)
        password = ""
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Join \(network.name)").font(.headline)
            Text("Enter the Wi-Fi password or use the password saved in your Keychain.")
                .font(.subheadline).foregroundStyle(.secondary)
            SecureField("Wi-Fi password", text: $password)
                .textFieldStyle(.roundedBorder).focused($passwordFocused)
                .disabled(model.connectivityBusy)
                .onSubmit { submit() }
                .onExitCommand { cancel() }
            HStack {
                Button("Cancel") { cancel() }
                    .disabled(model.connectivityBusy)
                Spacer()
                Button("Use Saved Password") { model.joinWiFi(network, password: nil, useSaved: true) }
                    .disabled(model.connectivityBusy)
                Button(model.connectivityBusy ? "Joining…" : "Join") {
                    submit()
                }.keyboardShortcut(.defaultAction).disabled(password.isEmpty || model.connectivityBusy)
            }
            Spacer()
        }.padding(24)
        .onAppear { passwordFocused = true }
        .onChange(of: model.connectivityBusy) { _, busy in if !busy { passwordFocused = true } }
    }
}
