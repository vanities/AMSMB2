import Foundation
import XCTest
@testable import AMSMB2

final class TimeoutRecoveryTests: XCTestCase, @unchecked Sendable {
    func testDelayedEchoAfterTimeoutReconnectsWithoutUsingExpiredCallback() async throws {
        try await checkRecovery(read: false)
    }

    func testDelayedFileOpenAfterTimeoutReconnectsWithoutUsingExpiredCallback() async throws {
        try await checkRecovery(read: true)
    }

    private func checkRecovery(read: Bool) async throws {
        #if os(macOS)
        guard let container = ProcessInfo.processInfo.environment["SMB_TIMEOUT_TEST_CONTAINER"],
              container.hasPrefix("library-endurance-qa-") else {
            throw XCTSkip("Requires an explicitly named disposable SMB fixture container")
        }
        let manager = try XCTUnwrap(SMB2Manager(url: URL(string: "smb://127.0.0.1:1446")!,
            credential: URLCredential(user: "qa", password: "fixture-only", persistence: .forSession)))
        manager.timeout = 1
        try await manager.connectShare(name: "qa")
        let baseline = try await manager.contentsOfDirectory(atPath: "AudioMoved")
        XCTAssertFalse(baseline.isEmpty)
        try docker("pause", container)
        var paused = true
        defer { if paused { try? docker("unpause", container) } }
        do {
            if read {
                _ = try await manager.contents(atPath: "AudioMoved/Network Endurance.wav", range: 0..<64)
            } else {
                try await manager.echo()
            }
            XCTFail("Paused server must time out")
        } catch { XCTAssertEqual((error as NSError).code, Int(ETIMEDOUT)) }
        try docker("unpause", container)
        paused = false
        // Reusing the manager used to dispatch the delayed response into expired stack storage.
        try await manager.connectShare(name: "qa")
        try await manager.echo()
        let entries = try await manager.contentsOfDirectory(atPath: "AudioMoved")
        XCTAssertFalse(entries.isEmpty)
        let header = try await manager.contents(atPath: "AudioMoved/Network Endurance.wav", range: 0..<64)
        XCTAssertEqual(header.prefix(4), Data("RIFF".utf8))
        try? await manager.disconnectShare(gracefully: true)
        #else
        throw XCTSkip("Docker outage fixture runs on macOS")
        #endif
    }

    #if os(macOS)
    private func docker(_ operation: String, _ container: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", operation, container]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
    #endif
}
