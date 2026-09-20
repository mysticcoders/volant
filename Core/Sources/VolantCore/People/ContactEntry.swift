import Foundation

/// One reachable value on a contact, with the label the Contacts app shows for it.
/// Labels arrive already localized; this layer never touches the Contacts framework.
public struct ContactField: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        case email, phone

        public var noun: String {
            switch self {
            case .email: return "Email"
            case .phone: return "Phone"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let value: String

    public init(id: String, kind: Kind, label: String, value: String) {
        self.id = id
        self.kind = kind
        self.label = label
        self.value = value
    }

    /// "work" reads as "Work", but "iPhone" and other mixed-case labels are left alone.
    public var displayLabel: String {
        guard !label.isEmpty, label == label.lowercased() else { return label }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Footer and Actions title, such as "Copy Work Email".
    public var copyTitle: String {
        displayLabel.isEmpty ? "Copy \(kind.noun)" : "Copy \(displayLabel) \(kind.noun)"
    }
}

public struct ContactEntry: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let organization: String
    public let fields: [ContactField]
    public let thumbnail: Data?

    public init(id: String, name: String, organization: String, fields: [ContactField], thumbnail: Data? = nil) {
        self.id = id
        self.name = name
        self.organization = organization
        self.fields = fields
        self.thumbnail = thumbnail
    }

    public var emails: [ContactField] { fields.filter { $0.kind == .email } }
    public var phones: [ContactField] { fields.filter { $0.kind == .phone } }

    /// Return copies this. Email wins because it is the value people paste.
    public var primaryField: ContactField? { emails.first ?? phones.first }
    /// Command-Return copies this, so a contact with both is one keystroke from either.
    public var secondaryField: ContactField? { emails.isEmpty ? nil : phones.first }

    public var email: String? { emails.first?.value }
    public var phone: String? { phones.first?.value }
    public var copyValue: String? { primaryField?.value }
}

public enum ContactMapping {
    /// Builds an entry from values a caller has already read out of the Contacts framework.
    /// Returns nil when there is nothing to show: no name, no organization, and nothing to copy.
    public static func entry(id: String,
                             givenName: String,
                             familyName: String,
                             organization: String,
                             emails: [(label: String, value: String)],
                             phones: [(label: String, value: String)],
                             thumbnail: Data? = nil) -> ContactEntry? {
        let organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = person.isEmpty ? organization : person
        var fields: [ContactField] = []
        var seen = Set<String>()
        for (kind, values) in [(ContactField.Kind.email, emails), (ContactField.Kind.phone, phones)] {
            for (label, value) in values {
                let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, seen.insert(kind.rawValue + ":" + value.lowercased()).inserted else { continue }
                fields.append(ContactField(id: "\(id):\(kind.rawValue):\(fields.count)",
                                           kind: kind,
                                           label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                           value: value))
            }
        }
        // A row with no title is not useful even when it carries an address.
        guard !name.isEmpty else { return nil }
        return ContactEntry(id: id, name: name, organization: organization, fields: fields, thumbnail: thumbnail)
    }
}
