import XCTest

@testable import VolantCore

final class ContactMappingTests: XCTestCase {
    private func entry(given: String = "Ada",
                       family: String = "Lovelace",
                       organization: String = "",
                       emails: [(label: String, value: String)] = [],
                       phones: [(label: String, value: String)] = [],
                       thumbnail: Data? = nil) -> ContactEntry? {
        ContactMapping.entry(id: "person-1", givenName: given, familyName: family,
                             organization: organization, emails: emails, phones: phones,
                             thumbnail: thumbnail)
    }

    func testNameFallsBackToOrganizationAndDropsContactsWithNeither() {
        XCTAssertEqual(entry()?.name, "Ada Lovelace")
        XCTAssertEqual(entry(given: "Ada", family: "")?.name, "Ada")
        XCTAssertEqual(entry(given: "  ", family: "  ", organization: "Analytical Engines")?.name, "Analytical Engines")
        XCTAssertNil(entry(given: "", family: "", organization: "",
                           emails: [("work", "nobody@example.test")]))
    }

    func testEveryLabeledValueIsKeptInOrder() {
        let contact = entry(emails: [("work", "ada@work.test"), ("home", "ada@home.test")],
                            phones: [("iPhone", "+15550100"), ("home", "+15550101")])
        XCTAssertEqual(contact?.emails.map(\.value), ["ada@work.test", "ada@home.test"])
        XCTAssertEqual(contact?.phones.map(\.value), ["+15550100", "+15550101"])
        XCTAssertEqual(contact?.fields.count, 4)
        XCTAssertEqual(Set(contact?.fields.map(\.id) ?? []).count, 4, "field identities must be unique")
    }

    func testBlankAndDuplicateValuesAreDropped() {
        let contact = entry(emails: [("work", "ada@work.test"), ("other", "   "), ("home", "ADA@WORK.TEST")],
                            phones: [("home", "+15550100"), ("mobile", "+15550100")])
        XCTAssertEqual(contact?.emails.map(\.value), ["ada@work.test"])
        XCTAssertEqual(contact?.phones.map(\.value), ["+15550100"])
    }

    func testReturnCopiesEmailAndCommandReturnCopiesPhone() {
        let both = entry(emails: [("work", "ada@work.test")], phones: [("home", "+15550100")])
        XCTAssertEqual(both?.primaryField?.value, "ada@work.test")
        XCTAssertEqual(both?.secondaryField?.value, "+15550100")

        let phoneOnly = entry(phones: [("home", "+15550100")])
        XCTAssertEqual(phoneOnly?.primaryField?.value, "+15550100")
        XCTAssertNil(phoneOnly?.secondaryField, "with nothing else to offer, command-return must not repeat return")

        let neither = entry()
        XCTAssertNil(neither?.primaryField)
        XCTAssertNil(neither?.copyValue)
    }

    func testCopyTitlesCarryTheContactsLabelWithoutMangingMixedCase() {
        let contact = entry(emails: [("work", "ada@work.test")], phones: [("iPhone", "+15550100")])
        XCTAssertEqual(contact?.primaryField?.copyTitle, "Copy Work Email")
        XCTAssertEqual(contact?.secondaryField?.copyTitle, "Copy iPhone Phone")

        let unlabeled = entry(emails: [("", "ada@work.test")])
        XCTAssertEqual(unlabeled?.primaryField?.copyTitle, "Copy Email")
    }

    func testLegacyAccessorsStillReturnTheFirstOfEachKind() {
        let contact = entry(emails: [("work", "ada@work.test"), ("home", "ada@home.test")],
                            phones: [("home", "+15550100")])
        XCTAssertEqual(contact?.email, "ada@work.test")
        XCTAssertEqual(contact?.phone, "+15550100")
        XCTAssertEqual(contact?.copyValue, "ada@work.test")
    }

    func testThumbnailIsCarriedThroughUntouchedAndIsOptional() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(entry(thumbnail: bytes)?.thumbnail, bytes)
        XCTAssertNil(entry()?.thumbnail)
    }
}
