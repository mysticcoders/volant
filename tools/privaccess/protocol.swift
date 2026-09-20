import Foundation

/// The entire vocabulary of the privileged helper. One operation, plus a probe that sends no
/// signal. There is deliberately no signal-number parameter: that would turn a process killer
/// into a general signalling primitive. Names and patterns are not accepted either, so the
/// helper can never be asked to resolve a target itself.
@objc protocol VolantPrivAccessHostProtocol {
    /// Reports whether the helper would be permitted to signal `pid`, without signalling it.
    func probe(pid: Int32, reply: @escaping (String) -> Void)

    /// Terminates `pid` only if it is still the application named by `bundleIdentifier`.
    /// The pair is revalidated inside the helper at the moment of action, because process
    /// identifiers are recycled: the pid the user selected can belong to something else by now.
    /// Replies with nil on success, or a reason.
    func terminate(pid: Int32, bundleIdentifier: String, reply: @escaping (String?) -> Void)
}
