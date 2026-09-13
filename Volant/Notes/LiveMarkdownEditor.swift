import AppKit
import SwiftUI

final class LiveEditorState: ObservableObject {
    struct Context: Equatable {
        let fence: CodeFence
        let detected: CodeLanguage
    }
    @Published var context: Context?
    weak var textView: MarkdownTextView?

    func chooseLanguage(_ language: CodeLanguage) {
        guard let view = textView, !view.hasMarkedText(),
              let fence = LiveMarkdown.activeFence(in: view.string, selection: view.selectedRange()) else { return }
        view.replaceLanguage(fence: fence, tag: language.tag)
    }

    func copyCode() {
        guard let view = textView,
              let fence = LiveMarkdown.activeFence(in: view.string, selection: view.selectedRange()) else { return }
        let text = (view.string as NSString).substring(with: fence.content)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func focus() { if let view = textView { view.window?.makeFirstResponder(view) } }
}

final class MarkdownTextView: NSTextView {
    var restyle: (() -> Void)?
    // A dedicated undo manager prevents history from leaking between notes.
    private let noteUndoManager = UndoManager()
    override var undoManager: UndoManager? { noteUndoManager }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle?()
    }

    func replaceLanguage(fence: CodeFence, tag: String) {
        let range = fence.languageRange
        let oldSelection = selectedRange()
        let oldSource = string as NSString
        guard NSMaxRange(range) <= oldSource.length,
              oldSource.substring(with: range) != tag,
              shouldChangeText(in: range, replacementString: tag) else { return }
        breakUndoCoalescing()
        textStorage?.replaceCharacters(in: range, with: tag)
        didChangeText()
        let delta = tag.utf16.count - range.length
        func move(_ offset: Int) -> Int {
            if offset >= NSMaxRange(range) { return offset + delta }
            if offset > range.location { return range.location + tag.utf16.count }
            return offset
        }
        let start = move(oldSelection.location), end = move(NSMaxRange(oldSelection))
        setSelectedRange(NSRange(location: max(0, start), length: max(0, end - start)))
        undoManager?.setActionName("Change Code Language")
        breakUndoCoalescing()
        window?.makeFirstResponder(self)
    }
}

struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let live: Bool
    let state: LiveEditorState

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = MarkdownTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 0, height: 12)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.usesFindBar = true
        view.setAccessibilityLabel(live ? "Live Markdown editor" : "Markdown source editor")
        view.string = text
        view.delegate = context.coordinator
        view.restyle = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.style(view) }
        }
        scroll.documentView = view
        state.textView = view
        context.coordinator.style(view)
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changedMode = coordinator.parent.live != live
        coordinator.parent = self
        guard let view = scroll.documentView as? MarkdownTextView else { return }
        state.textView = view
        // Marked text belongs to the input method until composition is committed.
        guard !view.hasMarkedText() else { return }
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            coordinator.style(view)
        } else if changedMode { coordinator.style(view) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LiveMarkdownEditor
        private var styling = false
        init(parent: LiveMarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? MarkdownTextView else { return }
            parent.text = view.string
            guard !view.hasMarkedText() else { return }
            style(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !styling, let view = notification.object as? MarkdownTextView else { return }
            updateContext(view)
            updateTypingAttributes(view)
        }

        func style(_ view: MarkdownTextView) {
            guard !styling, !view.hasMarkedText(), let storage = view.textStorage else { return }
            styling = true
            let selection = view.selectedRanges
            view.undoManager?.disableUndoRegistration()
            let styled = LiveMarkdown.styled(view.string, live: parent.live)
            storage.beginEditing()
            styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attributes, range, _ in
                storage.setAttributes(attributes, range: range)
            }
            storage.endEditing()
            view.selectedRanges = selection
            view.undoManager?.enableUndoRegistration()
            styling = false
            updateTypingAttributes(view)
            updateContext(view)
        }

        private func updateTypingAttributes(_ view: NSTextView) {
            guard !view.hasMarkedText() else { return }
            var attributes = LiveMarkdown.bodyAttributes
            if !parent.live || LiveMarkdown.activeFence(in: view.string, selection: view.selectedRange()) != nil {
                attributes[.font] = LiveMarkdown.codeFont
            }
            view.typingAttributes = attributes
        }

        private func updateContext(_ view: MarkdownTextView) {
            let context = parent.live ? LiveMarkdown.activeFence(in: view.string, selection: view.selectedRange()).map {
                LiveEditorState.Context(fence: $0, detected: LiveMarkdown.language(for: $0, in: view.string))
            } : nil
            let state = parent.state
            DispatchQueue.main.async { [weak state, weak view] in
                guard let state, state.textView === view else { return }
                if state.context != context { state.context = context }
            }
        }
    }
}
