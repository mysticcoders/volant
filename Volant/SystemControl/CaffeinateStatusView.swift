import SwiftUI

struct CaffeinateStatusView: View {
    @ObservedObject var service: CaffeinateService
    @State private var hovering = false
    @State private var showingError = false
    var body: some View {
        if service.isActive {
            Button { showingError = !service.stop() } label: {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 15)).foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 24)
                    .background(hovering ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Caffeinate: " + service.summary + ". Click to stop.")
            .accessibilityLabel("Stop Caffeinate")
            .accessibilityValue(service.summary)
            .popover(isPresented: $showingError) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Couldn't stop Caffeinate").font(.headline)
                    Text(service.error ?? "Try stopping the session again.").font(.callout)
                    Button("Try Again") { showingError = !service.stop() }
                }
                .padding(16).frame(width: 280)
            }
        }
    }
}
