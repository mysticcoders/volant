import AppKit
import Combine
import VolantCore

/// The Accessibility state Settings shows for Search Menu Items, managed the way Type at the cursor
/// manages it. Nothing talks to the input helper while the switch is off. Turning it on asks once,
/// through the helper, with the system prompt (macOS shows it only if Volant isn't allowed yet);
/// later visits check without prompting. Turning it off disconnects the helper unless Type at the
/// cursor still uses it. Both features share the one "Volant" entry in Privacy & Security.
final class MenuItemsAccess: ObservableObject {
    typealias State = DictationTypingAccess.State

    @Published private(set) var state = State.idle
    /// Set after the owner turns the switch off here, so Settings can say how to remove the grant.
    @Published private(set) var stoppedHelper = false

    private let client: InputHostClient
    private let canDisconnect: () -> Bool
    private var generation = 0

    /// `canDisconnect` says whether nothing else, such as Type at the cursor, uses the helper.
    init(client: InputHostClient, canDisconnect: @escaping () -> Bool = { true }) {
        self.client = client
        self.canDisconnect = canDisconnect
    }

    /// The owner turned the switch on or off in Settings, after it was saved.
    func chose(_ enabled: Bool) {
        generation += 1
        if enabled {
            stoppedHelper = false
            check(prompt: true)
        } else {
            let disconnects = canDisconnect()
            if disconnects { client.disconnect() }
            stoppedHelper = disconnects && (state != .idle || stoppedHelper)
            state = .idle
        }
    }

    /// Settings appeared or Volant became active again. Checks without prompting while the switch is on.
    func refresh(_ enabled: Bool) {
        guard enabled else {
            if state != .idle { state = .idle }
            return
        }
        guard state != .checking else { return }
        check(prompt: false)
    }

    /// Asks the helper for its status; a reply after the owner turned the switch off, or superseded by
    /// a later check, is ignored. A quiet re-check keeps showing the last answer until the new one
    /// arrives, so Settings doesn't flash Checking each time the section scrolls back into view.
    private func check(prompt: Bool) {
        generation += 1
        let current = generation
        if prompt || state == .idle || state == .unavailable { state = .checking }
        client.status(prompt: prompt) { [weak self] status in
            guard let self, self.generation == current else { return }
            guard let status else { self.state = .unavailable; return }
            self.state = status.trusted ? .allowed : .notAllowed
        }
    }
}
