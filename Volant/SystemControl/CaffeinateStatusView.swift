import SwiftUI

struct CaffeinateStatusView: View {
    @ObservedObject var service: CaffeinateService
    var body: some View {
        if service.isActive {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.accentColor)
                    Text(service.summary).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Stop") { service.stop() }.controlSize(.small)
                        .accessibilityLabel("Stop Caffeinate")
                }
                if let error = service.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            Divider().opacity(0.6)
        }
    }
}
