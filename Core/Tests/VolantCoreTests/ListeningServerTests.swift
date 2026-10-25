import Darwin
import XCTest

@testable import VolantCore

final class ListeningServerTests: XCTestCase {
    private func server(_ port: Int, _ process: String, _ executable: String? = nil, pid: Int32 = 100, directory: String? = nil) -> ListeningServer {
        ListeningServer(pid: pid, port: port, process: process, executable: executable, directory: directory, exposed: false)
    }

    func testRuntimesAreRecognizedFromTheExecutableName() {
        XCTAssertEqual(server(3000, "node", "/opt/homebrew/bin/node").kind, .runtime("Node.js"))
        XCTAssertEqual(server(8000, "python3.12", "/opt/homebrew/Cellar/python@3.12/3.12.7/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python").kind, .runtime("Python"))
        XCTAssertEqual(server(8080, "java", "/Library/Java/JavaVirtualMachines/fictional.jdk/Contents/Home/bin/java").kind, .runtime("Java"))
        XCTAssertEqual(server(5432, "postgres").kind, .runtime("PostgreSQL"))
        XCTAssertEqual(server(3000, "node").displayName, "Node.js")
    }

    func testRuntimesCarryTheirLogo() {
        XCTAssertEqual(server(3000, "node").kind.logo?.asset, "nodedotjs")
        XCTAssertEqual(server(8000, "python3").kind.logo?.hex, "3776AB")
        XCTAssertNil(server(8080, "java").kind.logo, "Java has no logo and keeps the generic tile")
        XCTAssertNil(server(6463, "Fictional").kind.logo)
        for name in ListeningServer.Kind.runtimes.map(\.name) where !["Java", "Memcached"].contains(name) {
            XCTAssertNotNil(ListeningServer.Kind.logos[name], "\(name) has a logo")
        }
        for logo in ListeningServer.Kind.logos.values {
            XCTAssertEqual(logo.hex.count, 6); XCTAssertNotNil(UInt32(logo.hex, radix: 16))
        }
    }

    func testMacOSServicesAndOtherProcessesAreSeparated() {
        XCTAssertEqual(server(5000, "ControlCenter", "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter").kind, .system)
        XCTAssertEqual(server(49152, "rapportd", "/usr/libexec/rapportd").kind, .system)
        XCTAssertEqual(server(6463, "Fictional", "/Applications/Fictional.app/Contents/MacOS/Fictional").kind, .other)
        XCTAssertEqual(server(4000, "fictional-api", "/Users/fictional/project/target/debug/fictional-api").displayName, "fictional-api")
    }

    func testQueryWordsAndAll() {
        XCTAssertEqual(ListeningServers.queryTerm("servers")?.text, "")
        XCTAssertEqual(ListeningServers.queryTerm("Ports 30")?.text, "30")
        XCTAssertEqual(ListeningServers.queryTerm("server all")?.all, true)
        XCTAssertEqual(ListeningServers.queryTerm("servers all node")?.text, "node")
        XCTAssertEqual(ListeningServers.queryTerm("servers allure")?.all, false)
        XCTAssertNil(ListeningServers.queryTerm("serverless"))
        XCTAssertNil(ListeningServers.queryTerm("port"))
    }

    func testRuntimesComeFirstAndServicesNeedAll() {
        let servers = [
            server(7000, "ControlCenter", "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"),
            server(6463, "Fictional", "/Applications/Fictional.app/Contents/MacOS/Fictional"),
            server(8080, "node", pid: 2),
            server(3000, "node", pid: 1),
        ]
        XCTAssertEqual(ListeningServers.arrange(servers).map(\.port), [3000, 8080, 6463])
        XCTAssertEqual(ListeningServers.arrange(servers, all: true).map(\.port), [3000, 8080, 6463, 7000])
    }

    func testTextMatchesPortNameRuntimeAndFolder() {
        let servers = [server(3000, "node", directory: "/Users/fictional/site"), server(8000, "python3", directory: "/Users/fictional/api")]
        XCTAssertEqual(ListeningServers.arrange(servers, matching: "30").map(\.port), [3000])
        XCTAssertEqual(ListeningServers.arrange(servers, matching: "python").map(\.port), [8000])
        XCTAssertEqual(ListeningServers.arrange(servers, matching: "node.js").map(\.port), [3000])
        XCTAssertEqual(ListeningServers.arrange(servers, matching: "api").map(\.port), [8000])
    }

    func testAgeAndDetail() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var node = server(3000, "node", pid: 41, directory: "/Users/fictional/site")
        XCTAssertNil(node.age(now: now))
        XCTAssertEqual(node.detail(home: "/Users/fictional", now: now), "node · ~/site · pid 41")
        node.started = now.addingTimeInterval(-45); XCTAssertEqual(node.age(now: now), "45s")
        node.started = now.addingTimeInterval(-750); XCTAssertEqual(node.age(now: now), "12m")
        node.started = now.addingTimeInterval(-3 * 3600 - 5); XCTAssertEqual(node.age(now: now), "3h")
        node.started = now.addingTimeInterval(-2 * 86400); XCTAssertEqual(node.age(now: now), "2d")
        XCTAssertEqual(server(6463, "Fictional", pid: 7).detail(home: "/Users/fictional", now: now), "pid 7", "No process name repeated when it is already the title")
    }

    func testCommandIsDiscoverableAndItsWordsAreReserved() {
        XCTAssertTrue(CoreCommand.search("serv").contains(.servers))
        XCTAssertTrue(CoreCommand.search("localhost").contains(.servers))
        XCTAssertEqual(CoreCommand.servers.query, "servers")
        for word in ["servers", "server 3000", "ports", "listening all"] { XCTAssertTrue(LauncherRouting.isReserved(word), word) }
    }

    func testFolderLabels() {
        let inHome = server(3000, "node", directory: "/Users/fictional/work/site")
        XCTAssertEqual(inHome.folderName, "site")
        XCTAssertEqual(inHome.abbreviatedDirectory(home: "/Users/fictional"), "~/work/site")
        XCTAssertEqual(inHome.abbreviatedDirectory(home: "/Users/fictional/"), "~/work/site")
        XCTAssertEqual(server(1, "x", directory: "/Users/fictionalother/a").abbreviatedDirectory(home: "/Users/fictional"), "/Users/fictionalother/a")
        XCTAssertNil(server(1, "x").folderName)
        XCTAssertEqual(server(3000, "node").url.absoluteString, "http://localhost:3000")
    }

    /// Opens a listening socket on `address` and returns it with its port.
    private func listen(on address: String) throws -> (socket: Int32, port: Int) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        inet_pton(AF_INET, address, &addr.sin_addr)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else { close(fd); throw XCTSkip("Couldn't open a test socket on \(address)") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        return (fd, Int(UInt16(bigEndian: addr.sin_port)))
    }

    func testScanFindsThisProcessesSocketsAndTheirReach() throws {
        let local = try listen(on: "127.0.0.1")
        defer { close(local.socket) }
        let wide = try listen(on: "0.0.0.0")
        defer { close(wide.socket) }
        let mine = ListeningServers.scan().filter { $0.pid == getpid() }
        let localEntry = try XCTUnwrap(mine.first { $0.port == local.port })
        XCTAssertFalse(localEntry.exposed, "127.0.0.1 is loopback only")
        XCTAssertNotNil(localEntry.executable)
        XCTAssertEqual(mine.first { $0.port == wide.port }?.exposed, true, "0.0.0.0 accepts connections from other machines")
        close(local.socket)
        XCTAssertNil(ListeningServers.scan().first { $0.pid == getpid() && $0.port == local.port }, "A closed socket is gone on the next scan")
    }
}
