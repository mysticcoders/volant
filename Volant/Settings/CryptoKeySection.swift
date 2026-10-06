import SwiftUI
import VolantCore

/// The optional CoinGecko key for crypto prices. The key lives in Keychain only, never in
/// config.json, backups or logs, and is shown only as saved or not.
struct CryptoKeySection: View {
    var credentials = AICredentials.keychain
    let onChange: () -> Void
    @State private var draft = ""
    @State private var saved = false
    @State private var message: String?

    var body: some View {
        Section {
            if saved {
                LabeledContent("CoinGecko key") { Text("Saved in Keychain").foregroundStyle(.secondary) }
                LabeledContent {
                    Button("Remove Key") { store(nil) }
                } label: { EmptyView() }
            } else {
                SecureField("CoinGecko key", text: $draft, prompt: Text("Paste a Demo key to save it"))
                LabeledContent {
                    Button("Save Key") { store(draft.trimmingCharacters(in: .whitespaces)) }
                        .disabled(!CryptoPrices.validKey(draft.trimmingCharacters(in: .whitespaces)))
                } label: { EmptyView() }
            }
            if let message { Text(message).foregroundStyle(.red) }
        } header: {
            Text("Crypto prices")
        } footer: {
            SettingsFooter("Optional. With a free CoinGecko Demo key, conversions can include Bitcoin, Ether and other major coins. Prices refresh at most every 10 minutes while you convert crypto, and only the key is sent. Data provided by CoinGecko.")
        }
        .onAppear { saved = ((try? credentials.read(CurrencyRatesStore.keyAccount)) ?? nil) != nil }
    }

    private func store(_ key: String?) {
        do {
            try credentials.write(CurrencyRatesStore.keyAccount, key)
            saved = key != nil
            draft = ""
            message = nil
            onChange()
        } catch {
            message = error.localizedDescription
        }
    }
}
