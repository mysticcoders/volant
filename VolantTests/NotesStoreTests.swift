import XCTest
@testable import Volant

final class NotesStoreTests: XCTestCase {
    func testCreateUpdateSearchDelete() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("volant-notes-\(UUID().uuidString)")
        let store = NotesStore(directory: dir)
        let note = store.create(initialText: "# Groceries\nmilk")
        XCTAssertEqual(store.notes.first?.title, "Groceries")
        store.update(note.id, text: "# Groceries\nmilk\neggs")
        store.flush()
        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "# Groceries\nmilk\neggs")
        XCTAssertEqual(store.search("eggs").count, 1)
        XCTAssertEqual(store.search("bread").count, 0)
        store.delete(note.id)
        XCTAssertTrue(store.notes.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    func testFailedCreationSurvivesReloadAndRetries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("volant-recovery-\(UUID().uuidString)")
        let store = NotesStore(directory: dir)
        try FileManager.default.removeItem(at: dir)
        let note = store.create(initialText: "Fictional draft")
        XCTAssertNotNil(store.saveErrors[note.id])
        store.reload()
        XCTAssertEqual(store.notes.first?.text, "Fictional draft")
        store.flush()
        XCTAssertEqual(store.dirtyText[note.id], "Fictional draft")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.flush()
        XCTAssertTrue(store.dirtyText.isEmpty)
        XCTAssertTrue(store.saveErrors.isEmpty)
        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "Fictional draft")
        try FileManager.default.removeItem(at: dir)
    }

    func testFailedUpdatePreservesLatestTextAndSelection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("volant-retry-\(UUID().uuidString)")
        let store = NotesStore(directory: dir)
        let note = store.create(initialText: "First")
        try FileManager.default.removeItem(at: dir)
        store.update(note.id, text: "Latest")
        store.flush()
        XCTAssertNotNil(store.saveErrors[note.id])
        store.delete(note.id)
        XCTAssertEqual(store.notes.first?.text, "Latest")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.flush()
        XCTAssertTrue(store.dirtyText.isEmpty)
        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "Latest")
        try FileManager.default.removeItem(at: dir)
    }

    func testNewNoteClearsFilterAndPinsPersist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("volant-model-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
            UserDefaults.standard.removeObject(forKey: "notes." + dir.path + ".selected")
            UserDefaults.standard.removeObject(forKey: "notes." + dir.path + ".pinned")
        }
        let store = NotesStore(directory: dir)
        let model = NotesModel(store: store)
        model.newNote(text: "Pinned reference")
        let pinnedID = try XCTUnwrap(model.selectedID)
        model.togglePin()
        model.show(.browse)
        model.filter = "does not match"
        model.newNote(text: "New thought")
        XCTAssertEqual(model.filter, "")
        XCTAssertNil(model.overlay)
        XCTAssertTrue(model.editing)
        XCTAssertEqual(model.filtered.first?.id, pinnedID)
        let restored = NotesModel(store: store)
        XCTAssertEqual(restored.selectedID, model.selectedID)
        XCTAssertTrue(restored.pinned.contains(pinnedID))
    }
}

import SwiftUI
import AppKit

final class NotesRenderTests: XCTestCase {
    @MainActor
    func testRenderNotesStates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("volant-render-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
            UserDefaults.standard.removeObject(forKey: "notes." + dir.path + ".selected")
            UserDefaults.standard.removeObject(forKey: "notes." + dir.path + ".pinned")
        }
        let store = NotesStore(directory: dir)
        let model = NotesModel(store: store)
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let scheme: ColorScheme = dark ? .dark : .light
            model.selectedID = nil
            // Empty state uses a separate empty store to keep the fixture independent of prior iteration.
            let emptyDir = dir.appendingPathComponent(mode)
            let emptyStore = NotesStore(directory: emptyDir)
            render(NotesView(model: NotesModel(store: emptyStore)).environment(\.colorScheme, scheme), name: "\(mode)-empty", size: NSSize(width: 380, height: 300), dark: dark)
            model.newNote(text: "# Weekend ideas\n\nA small place for thoughts worth keeping.\n\n- Walk by the lake\n- Try a new recipe\n\n```swift\nlet greeting = \"Hello, world!\"\nprint(greeting)\n```\n\nhttps://example.com/notes")
            for size in [NSSize(width: 380, height: 300), NSSize(width: 560, height: 620)] {
                render(NotesView(model: model).environment(\.colorScheme, scheme), name: "\(mode)-edit-\(Int(size.width))", size: size, dark: dark)
            }
            render(NotesView(model: model).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .accessibility3), name: "\(mode)-large-text", size: NSSize(width: 800, height: 700), dark: dark)
            let liveState = LiveEditorState()
            model.newNote(text: "# A little space to think\n\nKeep **useful things** close.\n\n```\ndef greet(name):\n    return 'Hello, ' + name\n```\n\nBack to the note.")
            render(NotesView(model: model, liveState: liveState).environment(\.colorScheme, scheme), name: "\(mode)-live-code", size: NSSize(width: 560, height: 620), dark: dark, prepare: {
                if let view = liveState.textView { view.setSelectedRange((view.string as NSString).range(of: "name):")) }
            })
            let compactState = LiveEditorState()
            render(NotesView(model: model, liveState: compactState).environment(\.colorScheme, scheme), name: "\(mode)-live-code-compact", size: NSSize(width: 380, height: 300), dark: dark, prepare: {
                if let view = compactState.textView { view.setSelectedRange((view.string as NSString).range(of: "name):")) }
            })
            model.show(.actions)
            render(NotesView(model: model).environment(\.colorScheme, scheme), name: "\(mode)-actions-overlay", size: NSSize(width: 560, height: 620), dark: dark)
            model.overlay = nil
            model.editing = false
            render(NotesView(model: model).environment(\.colorScheme, scheme), name: "\(mode)-preview", size: NSSize(width: 560, height: 620), dark: dark)
            model.show(.browse)
            render(NotesPicker(model: model, store: store).environment(\.colorScheme, scheme), name: "\(mode)-browse", size: NSSize(width: 340, height: 350), dark: dark)
            model.filter = "nothing matches"
            render(NotesPicker(model: model, store: store).environment(\.colorScheme, scheme), name: "\(mode)-no-matches", size: NSSize(width: 340, height: 350), dark: dark)
            model.show(.actions)
            render(NotesPicker(model: model, store: store).environment(\.colorScheme, scheme), name: "\(mode)-actions", size: NSSize(width: 340, height: 350), dark: dark)
            model.overlay = nil
            store.lastError = "Could not move note to Trash. Your note has been kept."
            render(NotesView(model: model).environment(\.colorScheme, scheme), name: "\(mode)-error", size: NSSize(width: 380, height: 300), dark: dark)
            store.lastError = nil
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, name: String, size: NSSize, dark: Bool, prepare: (() -> Void)? = nil) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        prepare?()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("No bitmap for \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
