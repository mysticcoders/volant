import XCTest
@testable import Slingshot
final class AssessmentRegressionTests: XCTestCase {
 func testRapidNotesHaveUniqueFiles() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("audit-collision-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: dir) }
  let store = NotesStore(directory: dir)
  for i in 0..<10 { store.create(initialText: "fictional note \(i)") }
  XCTAssertEqual(Set(store.notes.map(\.id)).count, 10)
  XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 10)
 }
 func testReloadPreservesPendingEdits() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("audit-reload-" + UUID().uuidString)
  let store = NotesStore(directory: dir)
  defer { store.flush(); try? FileManager.default.removeItem(at: dir) }
  let note = store.create(initialText: "old fictional text")
  store.update(note.id, text: "new fictional text")
  store.reload()
  XCTAssertEqual(store.notes.first?.text, "new fictional text")
 }
 func testPreviousConfigDecodesWithNewDefaults() throws {
  let json = #"{"summonHotKey":"cmd+space","appHotKeys":[],"clipboardRetention":500,"_help":"custom"}"#
  XCTAssertNoThrow(try JSONDecoder().decode(Preferences.self, from: Data(json.utf8)))
 }
 func testMarkdownIdentityIsStableAndUnique() {
  let rule = MarkdownBlock.rule
  XCTAssertEqual(rule.id, rule.id)
  let blocks = MarkdownBlocks.parse("repeat\n\nrepeat")
  XCTAssertEqual(Set(blocks.map(\.id)).count, blocks.count)
 }
}
