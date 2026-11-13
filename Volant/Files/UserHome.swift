import Foundation

/// The owner's real home folder. Inside App Sandbox `NSHomeDirectory()` returns the app's container
/// (`~/Library/Containers/<bundle id>/Data`), so anything that names a folder in the actual home,
/// such as `~/Applications` or a path to shorten to `~`, reads the account's home directory instead.
enum UserHome {
    static let path: String = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
}
