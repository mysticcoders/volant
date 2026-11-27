import SwiftUI
import UIKit
import VolantCore

/// The keyboard's `KeyboardPanel`, filled from its model and wired to its text proxy.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    unowned let inputController: KeyboardViewController

    var body: some View {
        KeyboardPanel(
            bar: bar,
            message: message,
            snippets: model.snippets,
            style: model.style,
            returnTitle: model.returnTitle,
            levels: model.levels,
            listeningSince: model.local != nil ? model.localSince : (model.isMine ? model.state.listeningSince : nil),
            globe: model.needsGlobe ? AnyView(GlobeKey(controller: inputController)) : nil,
            onDictate: { model.dictate() },
            onFinish: { model.finish() },
            onCancel: { model.cancel() },
            onStyle: { model.style = $0 },
            onSnippet: { model.insertSnippet($0) },
            onSpace: { inputController.insert(" ") },
            onDelete: { inputController.deleteBackward() },
            onDeleteWord: { inputController.deleteWordBackward() },
            onReturn: { inputController.insert("\n") })
    }

    private var bar: KeyboardPanel.Bar {
        switch model.local {
        case .starting: return .starting(String(localized: "Starting…"))
        case .listening(let text): return .listening(text)
        case .finishing: return .finishing
        case nil: break
        }
        if model.isMine {
            switch model.state.phase {
            case .preparing: return .starting(model.state.message ?? String(localized: "Starting…"))
            case .listening: return .listening(model.state.text)
            case .finishing: return .finishing
            default: break
            }
        }
        return model.starting ? .starting(String(localized: "Opening Volant…")) : .idle
    }

    private var message: String? {
        if !model.hasFullAccess {
            return String(localized: "To dictate, turn on Allow Full Access for Volant in Settings › Apps › Volant › Keyboards.")
        }
        if let notice = model.notice { return notice }
        if model.isMine, model.state.phase == .failed { return model.state.message ?? String(localized: "Dictation stopped.") }
        return nil
    }
}

/// The globe key, which must be a UIKit control so iOS can show the keyboard list on a long press.
private struct GlobeKey: UIViewRepresentable {
    unowned let controller: UIInputViewController

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = String(localized: "Next Keyboard")
        button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
