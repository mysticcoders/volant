import Foundation
import Security
import VolantCore

/// Runs Rex's two fixed scripts (`RexScript`) against this Mac's Rex server. Only a `rex` signed by
/// Superlogical's team runs, so an unrelated tool that happens to be called `rex` is never handed a
/// script. Volant never starts Rex: with no server running, the reply says so.
final class RexHost {
    static let teamIdentifier = "AG92C3PT77"
    let queue = DispatchQueue(label: "com.mysticcoders.volant.rex")
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    /// Signature checks by resolved path, valid while the file's modification date is unchanged.
    private var verified: [String: Date] = [:]

    enum Failure: LocalizedError {
        case notFound, notRunning, unreadable, changed
        var errorDescription: String? {
            switch self {
            case .notFound: return "Rex was not found. Install Rex, then try again."
            case .notRunning: return "Rex isn’t running. Open Rex, then try again."
            case .unreadable: return "Couldn’t read Rex panes."
            case .changed: return "This pane changed or closed. Refresh before continuing."
            }
        }
    }

    /// Where Rex installs its CLI: inside its server bundle, inside the app, then owner tool folders.
    static func candidates(home: String) -> [String] {
        [home + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
         "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex",
         "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex",
         home + "/.local/bin/rex", "/opt/homebrew/bin/rex", "/usr/local/bin/rex"]
    }

    /// Every pane with its status, parsed and bounded here so the app receives only validated values.
    func inventory() throws -> Data {
        let output: Data
        do { output = try run(RexScript.inventoryArguments(home: home)) }
        catch let failure as Failure { throw failure }
        catch { throw Failure.unreadable }
        guard let inventory = try? RexInventory.parse(output) else { throw Failure.unreadable }
        return try JSONEncoder().encode(inventory)
    }

    /// Focuses the pane if the script still finds it as a terminal in that session.
    func focus(session: String, block: String) throws {
        guard let arguments = RexScript.focusArguments(home: home, session: session, block: block) else { throw Failure.changed }
        do { _ = try run(arguments) }
        catch let failure as Failure where failure != .unreadable { throw failure }
        catch { throw Failure.changed }
    }

    /// Runs the first signed `rex` found, mapping Rex's not-running exit status to its own message.
    private func run(_ arguments: [String]) throws -> Data {
        guard let executable = Self.candidates(home: home).lazy
            .map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath() })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) && self.isSignedByRex($0) }) else { throw Failure.notFound }
        do {
            return try HerdrProcess.run(executable: executable, arguments: arguments, home: home, timeout: 8,
                                        environment: ChildProcessEnvironment.rex(home: home, user: NSUserName()))
        } catch {
            let status = (error as NSError).userInfo[HerdrProcess.terminationStatusKey] as? Int32
            throw status == RexScript.notRunningStatus ? Failure.notRunning : Failure.unreadable
        }
    }

    /// Checks the executable's signature against Superlogical's team, once per version of the file.
    private func isSignedByRex(_ url: URL) -> Bool {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let modified, verified[url.path] == modified { return true }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(Self.teamIdentifier)\""
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        verified[url.path] = modified
        return true
    }
}
