import Contacts
import VolantCore

/// Read-only contact lookup by name. Asks for access on first use; never writes.
/// Everything past reading the framework's values lives in `ContactMapping`, which has no
/// Contacts dependency and is tested without a permission grant.
final class ContactSearch {
    private let store = CNContactStore()
    private let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
        CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
        // The thumbnail is pre-scaled for small rows; the full-size image is never fetched.
        CNContactThumbnailImageDataKey,
    ] as [CNKeyDescriptor]

    var isAuthorized: Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized }

    /// `askIfNeeded` is true only for the explicit `@` prefix; merged search never triggers the system prompt.
    func search(_ term: String, askIfNeeded: Bool, completion: @escaping ([ContactEntry]) -> Void) {
        guard term.count >= 2 else { completion([]); return }
        if !askIfNeeded && !isAuthorized { completion([]); return }
        ensureAccess { [weak self] granted in
            guard granted, let self else { completion([]); return }
            DispatchQueue.global(qos: .userInitiated).async {
                let request = CNContactFetchRequest(keysToFetch: self.keys)
                request.predicate = CNContact.predicateForContacts(matchingName: term)
                var out: [ContactEntry] = []
                try? self.store.enumerateContacts(with: request) { contact, stop in
                    if let entry = Self.entry(for: contact) { out.append(entry) }
                    if out.count >= 5 { stop.pointee = true }
                }
                DispatchQueue.main.async { completion(out) }
            }
        }
    }

    /// Reads the framework's values and hands them to the mapping layer. Labels are localized
    /// here because `CNLabeledValue` is the only thing that can localize them.
    private static func entry(for contact: CNContact) -> ContactEntry? {
        ContactMapping.entry(
            id: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            organization: contact.organizationName,
            emails: contact.emailAddresses.map { (label(for: $0.label), String($0.value)) },
            phones: contact.phoneNumbers.map { (label(for: $0.label), $0.value.stringValue) },
            thumbnail: contact.thumbnailImageData)
    }

    private static func label(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: raw)
    }

    private func ensureAccess(_ completion: @escaping (Bool) -> Void) {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: completion(true)
        case .notDetermined:
            PermissionGate.begin()
            store.requestAccess(for: .contacts) { granted, _ in DispatchQueue.main.async { PermissionGate.end(); completion(granted) } }
        default: completion(false)
        }
    }
}
