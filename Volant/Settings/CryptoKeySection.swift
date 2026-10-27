import SwiftUI
import VolantCore

/// The optional CoinGecko key for crypto prices, which otherwise come from CoinGecko's keyless
/// public API. The key lives in Keychain only, never in config.json, backups or logs, and is shown
/// only as saved or not.
struct CryptoKeySection: View {
    var credentials = AICredentials.keychain
    let onChange: () -> Void
    @State private var draft = ""
    @State private var saved = false
    @State private var message: String?

    var body: some View {
        Section {
            Group { keyRows }.onAppear { saved = ((try? credentials.read(CurrencyRatesStore.keyAccount)) ?? nil) != nil }
        } header: {
            Text("Crypto prices")
        } footer: {
            SettingsFooter(String(localized: "Conversions include Bitcoin, Ether and other major coins without a key. A free CoinGecko Demo key is optional and gives steadier rate limits. Prices refresh at most every 10 minutes while you convert crypto, and nothing you type is sent. Data provided by CoinGecko."))
        }
    }

    /// The key's rows. Settings rebuilds sections row by row, so the Keychain check rides on the rows
    /// rather than on the section.
    @ViewBuilder private var keyRows: some View {
        if saved {
            LabeledContent("CoinGecko key") { Text("Saved in Keychain").foregroundStyle(.secondary) }
            LabeledContent {
                Button("Remove Key") { store(nil) }
            } label: { EmptyView() }
        } else {
            LabeledContent("CoinGecko key") {
                SecureField("CoinGecko key", text: $draft, prompt: Text("Optional Demo key")).labelsHidden().frame(maxWidth: 240)
            }
            LabeledContent {
                Button("Save Key") { store(draft.trimmingCharacters(in: .whitespaces)) }
                    .disabled(!CryptoPrices.validKey(draft.trimmingCharacters(in: .whitespaces)))
            } label: { EmptyView() }
        }
        if let message { Text(message).foregroundStyle(.red) }
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
