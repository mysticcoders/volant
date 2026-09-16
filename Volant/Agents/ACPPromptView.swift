import AppKit
import SwiftUI

/// Owns the chat editor and its native focus, independently of launcher search.
struct ACPPromptView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID
    let send: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PromptScrollView {
        let scroll = PromptScrollView()
        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 64))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.textContainerInset = NSSize(width: 9, height: 9)
        editor.minSize = NSSize(width: 0, height: 64)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Agent prompt")
        editor.delegate = context.coordinator
        editor.string = text
        editor.submit = send
        scroll.documentView = editor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.editor = editor
        return scroll
    }
    func updateNSView(_ view: PromptScrollView, context: Context) {
        context.coordinator.parent = self
        view.editor?.submit = send
        if let editor = view.editor, editor.string != text, !editor.hasMarkedText() { editor.string = text }
        if view.request != focusRequest {
            view.request = focusRequest
            view.focusEditor()
        }
    }
    static func dismantleNSView(_ view: PromptScrollView, coordinator: Coordinator) { view.active = false }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ACPPromptView
        init(_ parent: ACPPromptView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
    final class PromptScrollView: NSScrollView {
        weak var editor: PromptTextView?
        var request: UUID?
        var active = true
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); focusEditor() }
        func focusEditor() {
            let current = request
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.request == current, let editor = self.editor,
                      let window = self.window, window.isVisible, window.isKeyWindow else { return }
                window.makeFirstResponder(editor)
            }
        }
    }
    final class PromptTextView: NSTextView {
        var submit: () -> Void = {}
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 && event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
                submit()
            } else { super.keyDown(with: event) }
        }
    }
}
