import AppKit
import Darwin

/// Spike helper. Runs outside App Sandbox so it can signal processes, which the sandboxed app
/// provably cannot do. Every control that makes that defensible lives here, not in the caller.
final class PrivAccessHost: NSObject, VolantPrivAccessHostProtocol, NSXPCListenerDelegate {
    /// Only a build signed by this team may connect. This is the control that makes an
    /// unsandboxed helper defensible; without it any local process could drive it.
    private static let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"REMBT6JY4N\""

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if #available(macOS 13.0, *) {
            connection.setCodeSigningRequirement(Self.requirement)
        }
        connection.exportedInterface = NSXPCInterface(with: VolantPrivAccessHostProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func probe(pid: Int32, reply: @escaping (String) -> Void) {
        guard kill(pid, 0) == 0 else { reply("EPERM/errno \(errno)"); return }
        reply("permitted")
    }

    func terminate(pid: Int32, bundleIdentifier: String, reply: @escaping (String?) -> Void) {
        guard let refusal = Self.refusal(pid: pid, bundleIdentifier: bundleIdentifier) else {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                reply("process disappeared"); return
            }
            // Ask politely first; the helper is unsandboxed, so SIGTERM is available as a fallback.
            if app.terminate() { reply(nil); return }
            if kill(pid, SIGTERM) == 0 { reply(nil); return }
            reply("terminate() refused and SIGTERM failed with errno \(errno)")
            return
        }
        reply(refusal)
    }

    /// Returns a reason to refuse, or nil to proceed. Refusals live in the helper so that a
    /// caller cannot reach a target simply by not showing it in the launcher.
    private static func refusal(pid: Int32, bundleIdentifier: String) -> String? {
        guard pid > 1 else { return "refusing pid \(pid)" }
        guard pid != getpid(), pid != getppid() else { return "refusing to terminate Volant" }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return "pid \(pid) is not a running application"
        }
        guard let identifier = app.bundleIdentifier else {
            return "pid \(pid) has no bundle identifier"
        }
        // The pid may have been recycled since the caller chose it.
        guard identifier == bundleIdentifier else {
            return "pid \(pid) is now \(identifier), not \(bundleIdentifier)"
        }
        guard identifier != Bundle.main.bundleIdentifier else { return "refusing to terminate Volant" }
        guard ownedByCaller(pid: pid) else { return "pid \(pid) is not owned by this user" }
        return nil
    }

    /// Refuse anything not owned by the same uid, which excludes root and system daemons.
    private static func ownedByCaller(pid: Int32) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return false }
        return info.kp_eproc.e_ucred.cr_uid == getuid()
    }
}

let delegate = PrivAccessHost()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
