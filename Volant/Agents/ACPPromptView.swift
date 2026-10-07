import AppKit
import SwiftUI

/// Owns the chat editor and its native focus, independently of launcher search.
struct ACPPromptView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID
    let send: () -> Void
    /// Called with the location of an @ typed at the start of a word, after it is inserted.
    var mention: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PromptScrollView {
        let scroll = PromptScrollView()
        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 64))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.insertionPointColor = ThemeStore.shared.theme.resolvedNSAccent
        editor.textContainerInset = NSSize(width: 9, height: 9)
        editor.minSize = NSSize(width: 0, height: 64)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Agent prompt")
        editor.setAccessibilityHelp("Return to send; Shift-Return for a new line")
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
        /// An @ opens the picker only at the start of a word, so email addresses and handles typed
        /// mid-word stay ordinary text, and never while an input method is composing.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard text == "@", !textView.hasMarkedText() else { return true }
            let source = textView.string as NSString
            let atWordStart = range.location == 0 || (range.location <= source.length
                && CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: range.location - 1)) ?? " "))
            if atWordStart {
                let location = range.location
                DispatchQueue.main.async { [weak self] in self?.parent.mention(location) }
            }
            return true
        }
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
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            // Let the input method commit its marked text before considering submission.
            if isReturn && !hasMarkedText() && (modifiers.isEmpty || modifiers == .command) {
                if !event.isARepeat { submit() }
            } else { super.keyDown(with: event) }
        }
    }
}
