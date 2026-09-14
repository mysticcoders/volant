import AppKit
import CoreBluetooth
import IOBluetooth
import CoreLocation
import CoreWLAN

struct WiFiChoice: Hashable {
    let ssid: Data
    let name: String
    let security: String
    let signal: Int
    let current: Bool
    var id: String { ssid.base64EncodedString() + ":" + security }
}
enum ConnectivityItem: Hashable {
    case bluetooth(id: String, name: String)
    case wifi(WiFiChoice)
    case settings(String)
    case refresh(String)
    var id: String {
        switch self {
        case .bluetooth(let id, _): return "bluetooth:" + id
        case .wifi(let network): return "wifi:" + network.id
        case .settings(let source): return source + ":settings"
        case .refresh(let source): return source + ":refresh"
        }
    }
    var title: String {
        switch self {
        case .bluetooth(_, let name): return name
        case .wifi(let network): return network.name
        case .settings(let source): return "Open " + (source == "wifi" ? "Wi-Fi" : "Bluetooth") + " Settings"
        case .refresh: return "Refresh Devices and Networks"
        }
    }
    var detail: String {
        switch self {
        case .bluetooth: return "Connected"
        case .wifi(let network): return (network.current ? "Current · " : "") + network.security + " · \(network.signal) dBm"
        case .settings: return "System Settings"
        case .refresh: return "Scan again"
        }
    }
}
struct ConnectivitySnapshot {
    var items: [ConnectivityItem]
    var message: String?
}
protocol ConnectivityAccess: AnyObject {
    func load(_ source: String, refresh: Bool, completion: @escaping (ConnectivitySnapshot) -> Void)
    func join(_ network: WiFiChoice, password: String?, useSaved: Bool, completion: @escaping (String?) -> Void)
}

/// Created lazily by connectivity commands. No startup permission request or background scanning.
final class ConnectivityService: NSObject, ConnectivityAccess, CLLocationManagerDelegate, CBCentralManagerDelegate {
    private var location: CLLocationManager?
    private var bluetooth: CBCentralManager?
    private var pendingWiFi: ((ConnectivitySnapshot) -> Void)?
    private var pendingBluetooth: ((ConnectivitySnapshot) -> Void)?
    private let queue = DispatchQueue(label: "com.mysticcoders.volant.wifi", qos: .userInitiated)
    private var scanning = false
    private var cache: ConnectivitySnapshot?
    private var cacheDate = Date.distantPast

    func load(_ source: String, refresh: Bool = false, completion: @escaping (ConnectivitySnapshot) -> Void) {
        if source == "bluetooth" {
            pendingBluetooth = completion
            if bluetooth == nil {
                bluetooth = CBCentralManager(delegate: self, queue: .main)
            }
            showBluetooth()
        } else {
            pendingWiFi = completion
            if refresh { cache = nil }
            if location == nil { location = CLLocationManager(); location?.delegate = self }
            guard let location else { return }
            switch location.authorizationStatus {
            case .notDetermined:
                completion(ConnectivitySnapshot(items: [.settings("wifi")], message: "Allow Location access to show Wi-Fi network names. Volant does not request your coordinates."))
                location.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: scanWiFi()
            default: completion(ConnectivitySnapshot(items: [.settings("wifi")], message: "Wi-Fi names need Location access. Enable Volant in System Settings → Privacy & Security → Location Services."))
            }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let pendingWiFi else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: scanWiFi()
        case .denied, .restricted:
            pendingWiFi(ConnectivitySnapshot(items: [.settings("wifi")], message: "Location access is off. You can still manage Wi-Fi in System Settings."))
        default: break
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { showBluetooth() }
    private func showBluetooth() {
        guard let callback = pendingBluetooth, let bluetooth else { return }
        guard CBManager.authorization == .allowedAlways else {
            callback(ConnectivitySnapshot(items: [.settings("bluetooth")], message: CBManager.authorization == .notDetermined ? "Allow Bluetooth access to list connected devices." : "Bluetooth access is off. Enable Volant in System Settings → Privacy & Security → Bluetooth."))
            return
        }
        guard bluetooth.state == .poweredOn else {
            callback(ConnectivitySnapshot(items: [.settings("bluetooth"), .refresh("bluetooth")], message: bluetooth.state == .poweredOff ? "Bluetooth is turned off." : "Bluetooth is not ready. Try refreshing."))
            return
        }
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
        var seen = Set<String>()
        let items = devices.compactMap { device -> ConnectivityItem? in
            guard let id = device.addressString, seen.insert(id).inserted else { return nil }
            return .bluetooth(id: id, name: device.name ?? "Bluetooth Device")
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        callback(ConnectivitySnapshot(items: items + [.refresh("bluetooth"), .settings("bluetooth")], message: items.isEmpty ? "No connected paired Bluetooth devices found." : nil))
    }
    private func scanWiFi() {
        if let cache, Date().timeIntervalSince(cacheDate) < 15 { pendingWiFi?(cache); return }
        pendingWiFi?(ConnectivitySnapshot(items: [], message: "Scanning nearby Wi-Fi networks…"))
        guard !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot: ConnectivitySnapshot
            do {
                guard let interface = CWWiFiClient.shared().interface() else { throw VolumeFailure(message: "No Wi-Fi interface is available.") }
                guard interface.powerOn() else { throw VolumeFailure(message: "Wi-Fi is turned off. Open Wi-Fi Settings to enable it.") }
                let networks = try interface.scanForNetworks(withSSID: nil)
                let current = interface.ssidData()
                var choices: [String: WiFiChoice] = [:]
                for network in networks {
                    guard let ssid = network.ssidData, let name = network.ssid, !name.isEmpty else { continue }
                    let security = Self.security(network)
                    let choice = WiFiChoice(ssid: ssid, name: name, security: security, signal: network.rssiValue, current: ssid == current)
                    if let previous = choices[choice.id], previous.signal >= choice.signal { continue }
                    choices[choice.id] = choice
                }
                let sorted = choices.values.sorted {
                    if $0.current != $1.current { return $0.current }
                    if $0.signal != $1.signal { return $0.signal > $1.signal }
                    return $0.id < $1.id
                }
                let emptyMessage = networks.isEmpty
                    ? "No visible Wi-Fi networks found. Hidden networks can be joined in System Settings."
                    : "macOS returned networks without names. Check Volant’s Location access in Privacy & Security, then quit and reopen Volant."
                snapshot = ConnectivitySnapshot(items: sorted.map(ConnectivityItem.wifi) + [.refresh("wifi"), .settings("wifi")], message: sorted.isEmpty ? emptyMessage : nil)
            } catch { snapshot = ConnectivitySnapshot(items: [.refresh("wifi"), .settings("wifi")], message: error.localizedDescription) }
            DispatchQueue.main.async {
                self.scanning = false
                self.cache = snapshot; self.cacheDate = Date()
                self.pendingWiFi?(snapshot)
            }
        }
    }
    private static func security(_ network: CWNetwork) -> String {
        if network.supportsSecurity(.none) { return "Open" }
        if network.supportsSecurity(.wpa3Personal) { return "WPA3 Personal" }
        if network.supportsSecurity(.wpa2Personal) { return "WPA2 Personal" }
        if network.supportsSecurity(.wpaPersonal) { return "WPA Personal" }
        return "Managed / Other"
    }
    func join(_ network: WiFiChoice, password: String?, useSaved: Bool, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var failure: String?
            do {
                guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { throw VolumeFailure(message: "Wi-Fi is unavailable.") }
                if interface.ssidData() != network.ssid {
                    // Rescan the selected SSID only; never reuse a stale access point or downgrade its security.
                    let fresh = try interface.scanForNetworks(withSSID: network.ssid).filter { Self.security($0) == network.security }.max { $0.rssiValue < $1.rssiValue }
                    guard let fresh else { throw VolumeFailure(message: "This network is no longer available. Refresh and try again.") }
                    guard network.security != "Managed / Other" else { throw VolumeFailure(message: "Join this network in Wi-Fi Settings; it needs additional configuration.") }
                    var credential = password
                    if useSaved {
                        var saved: NSString?
                        var status = CWKeychainFindWiFiPassword(.user, network.ssid, &saved)
                        if status == errSecItemNotFound { status = CWKeychainFindWiFiPassword(.system, network.ssid, &saved) }
                        guard status == noErr, let saved else { throw VolumeFailure(message: "No accessible saved password. Enter the network password or use Wi-Fi Settings.") }
                        credential = saved as String
                    }
                    guard network.security == "Open" || credential?.isEmpty == false else { throw VolumeFailure(message: "Enter a password for this network.") }
                    try interface.associate(to: fresh, password: credential)
                    guard interface.ssidData() == network.ssid else { throw VolumeFailure(message: "macOS hasn’t confirmed this connection yet. Refresh to check the current network.") }
                }
            } catch { failure = error.localizedDescription }
            DispatchQueue.main.async { self.cache = nil; completion(failure) }
        }
    }
    static func openSettings(_ source: String) {
        let pane = source == "wifi" ? "com.apple.wifi-settings-extension" : "com.apple.BluetoothSettings"
        if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
    }
}
