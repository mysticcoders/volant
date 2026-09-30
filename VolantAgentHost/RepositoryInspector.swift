import Foundation
import VolantCore

/// Runs `RepositoryStatusCommand` in the folders local agents are working in, with a short
/// timeout and bounded output. Nothing else is executed.
enum RepositoryInspector {
    /// Folders that are missing, relative or not repositories are left out of the result rather
    /// than reported as errors, since most agent panes share a handful of repositories.
    static func states(for paths: [String]) throws -> [String: RepositoryState] {
        guard paths.count <= RepositoryStateLimit.paths else { throw CocoaError(.fileReadTooLarge) }
        guard let git = RepositoryStatusCommand.git() else { return [:] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result: [String: RepositoryState] = [:]
        for path in Set(paths) where path.hasPrefix("/") && !path.contains("\0") {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue,
                  let output = try? HerdrProcess.run(executable: URL(fileURLWithPath: git), arguments: RepositoryStatusCommand.arguments,
                                                     home: home, timeout: 3, directory: path,
                                                     environment: RepositoryStatusCommand.environment(home: home)),
                  let state = RepositoryState.parse(porcelainV2: String(decoding: output, as: UTF8.self)) else { continue }
            result[path] = state
        }
        return result
    }
}
