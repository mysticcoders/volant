import Foundation

extension ExtensionManifest {
    /// Whether this manifest asks for nothing `previous` did not already have: the same ABI, and
    /// capabilities, hosts, tokens, app link schemes and permissions that are each a subset of the old
    /// ones, with storage only if the old version had it. A catalog update that passes keeps the owner's
    /// choice to enable the extension; one that fails is off until the owner enables it again.
    public func requestsNoMoreThan(_ previous: ExtensionManifest) -> Bool {
        (abiVersion ?? 1) == (previous.abiVersion ?? 1) &&
            Set(capabilities).isSubset(of: previous.capabilities) &&
            Set(declaredHosts).isSubset(of: previous.declaredHosts) &&
            Set(declaredSecrets).isSubset(of: previous.declaredSecrets) &&
            Set(declaredAppLinks).isSubset(of: previous.declaredAppLinks) &&
            Set(declaredPermissions).isSubset(of: previous.declaredPermissions) &&
            (!usesStorage || previous.usesStorage)
    }
}
