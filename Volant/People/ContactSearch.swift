import Contacts

struct ContactEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let organization: String
    let email: String?
    let phone: String?

    var copyValue: String? { email ?? phone }
}

/// Read-only contact lookup by name. Asks for access on first use; never writes.
final class ContactSearch {
    private let store = CNContactStore()
    private let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
        CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
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
                    let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    out.append(ContactEntry(
                        id: contact.identifier,
                        name: name.isEmpty ? contact.organizationName : name,
                        organization: contact.organizationName,
                        email: contact.emailAddresses.first.map { String($0.value) },
                        phone: contact.phoneNumbers.first?.value.stringValue))
                    if out.count >= 5 { stop.pointee = true }
                }
                DispatchQueue.main.async { completion(out) }
            }
        }
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
