import CloudKit
import Foundation
import Security
import VolantCore

/// Tells Volant for iPhone that a break started or is over, by overwriting one CloudKit record per
/// kind in the owner's private database. CloudKit runs through the system's iCloud daemon, as notes
/// and settings sync do, so the app gains no network access. Only release builds carry the CloudKit
/// entitlement; elsewhere `isAvailable` is false and nothing is sent. Failures are kept for Settings
/// and never logged with any content.
final class BreakPhoneAlerts: ObservableObject {
    /// The app's sender; Settings reads its `problem`.
    static let shared = BreakPhoneAlerts()

    /// Why the last alert didn't reach iCloud, for Settings; nil after a success.
    @Published private(set) var problem: String?

    private let save: (BreakAlert, Date, @escaping (Error?) -> Void) -> Void

    /// Uses CloudKit; tests pass their own `save`.
    init(save: ((BreakAlert, Date, @escaping (Error?) -> Void) -> Void)? = nil) {
        self.save = save ?? Self.cloudKitSave
    }

    /// Whether this build is signed with CloudKit, without which a container can't be opened.
    static let isAvailable: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) else { return false }
        let services = (value as? [String]) ?? [(value as? String)].compactMap { $0 }
        return services.contains("CloudKit") || services.contains("*")
    }()

    /// Sends one alert stamped `at`, and records whether it reached iCloud.
    func send(_ alert: BreakAlert, at: Date = Date()) {
        save(alert, at) { [weak self] error in
            DispatchQueue.main.async {
                self?.problem = error.map(Self.describe)
            }
        }
    }

    /// Overwrites the alert's record, so the iPhone's subscription fires on every write.
    private static func cloudKitSave(_ alert: BreakAlert, at: Date, done: @escaping (Error?) -> Void) {
        guard isAvailable else { return done(nil) }
        let record = CKRecord(recordType: alert.recordType, recordID: CKRecord.ID(recordName: BreakAlert.recordName))
        record[BreakAlert.timeField] = at as NSDate
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.qualityOfService = .userInitiated
        operation.modifyRecordsResultBlock = { result in
            if case .failure(let error) = result { done(error) } else { done(nil) }
        }
        CKContainer(identifier: BreakAlert.containerIdentifier).privateCloudDatabase.add(operation)
    }

    /// A short reason for Settings; CloudKit's own messages can name internal identifiers.
    static func describe(_ error: Error) -> String {
        switch (error as? CKError)?.code {
        case .notAuthenticated:
            return String(localized: "Sign in to iCloud on this Mac to alert your iPhone.", comment: "Breaks phone alerts error: no iCloud account")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return String(localized: "iCloud couldn’t be reached, so the last alert didn’t reach your iPhone.", comment: "Breaks phone alerts error: iCloud unreachable")
        case .quotaExceeded:
            return String(localized: "Your iCloud storage is full, so the last alert didn’t reach your iPhone.", comment: "Breaks phone alerts error: iCloud full")
        default:
            return String(localized: "The last alert didn’t reach your iPhone.", comment: "Breaks phone alerts error: any other failure")
        }
    }
}
