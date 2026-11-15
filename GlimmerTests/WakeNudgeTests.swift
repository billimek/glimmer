// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

//
//  WakeNudgeTests.swift
//
//  Only a Rubylight PC gets the 1 px mouse move after connecting: its /serverinfo parse, the gate
//  that reaches the backend, and the two moves themselves.
//

@testable import GlimmerEngine
import Foundation
import Testing
@testable import Glimmer

struct WakeNudgeTests {

    private static func hydrate(_ body: String, into server: ServerInfo? = nil) async throws -> ServerInfo {
        let client = NetworkClient(server: server ?? ServerInfo(address: "192.0.2.1", uniqueId: "x", serverName: "x"))
        let xml = try XMLTreeBuilder.parse(data: Data(#"<root status_code="200">\#(body)</root>"#.utf8))
        await client.hydrateServerInfo(from: xml, fetchedOverPaired: true)
        return await client.server
    }

    @Test func rubylightVersionMarksThePCForTheNudge() async throws {
        let server = try await Self.hydrate("<RustHostVersion>4.4.0</RustHostVersion>")
        #expect(server.rustHostVersion == "4.4.0")
        #expect(server.wakeNudge)
    }

    @Test func aReplyWithoutTheVersionIsNotRubylight() async throws {
        let server = try await Self.hydrate("<appversion>7.1.431.-1</appversion>")
        #expect(server.rustHostVersion == nil)
        #expect(!server.wakeNudge)
    }

    @Test func anEmptyVersionClearsTheNudge() async throws {
        let known = try await Self.hydrate("<RustHostVersion>4.4.0</RustHostVersion>")
        let server = try await Self.hydrate("<RustHostVersion></RustHostVersion>", into: known)
        #expect(!server.wakeNudge)
    }

    @Test func aPartialReplyKeepsTheKnownVersion() async throws {
        let known = try await Self.hydrate("<RustHostVersion>4.4.0</RustHostVersion>")
        let server = try await Self.hydrate("<hostname>TOWER</hostname>", into: known)
        #expect(server.rustHostVersion == "4.4.0")
    }

    @Test func theBackendInfoCarriesTheGate() {
        let plain = BackendServerInfo(address: "192.0.2.1", appVersion: "7", rtspSessionUrl: "rtsp://x", serverCodecModeRaw: 0)
        #expect(!plain.wakeNudge)
    }

    @Test func theNudgeIsOnePixelOutAndBack() async {
        let log = MoveLog()
        await NativeConnectionEvents.wakeNudge(send: { log.add($0, $1); return 0 }, pause: { log.pause() })
        #expect(log.events == ["1,1", "pause", "-1,-1"])
    }

    @Test func connectingWithTheNudgeOnDoesNotDeadlock() async {
        let session = StreamSession(hostDisposition: .cancelOwnedHostSession)
        let bridge = StreamBridgeContext(session: session, videoDecoder: await VideoDecoder(),
                                         audioDecoder: AudioDecoder(defaults: UserDefaults(suiteName: "WakeNudgeTests") ?? .standard))
        let backend = NativeBackend()
        backend.withState { backend.wakeNudge = true }
        bridge.setEventSource(backend, attempt: bridge.currentAttempt)
        let events = NativeConnectionEvents(bridge: bridge, backend: backend)
        let done = AsyncStream<Void>.makeStream()
        DispatchQueue.global().async {
            _ = backend.adoptWhileConnecting { events.connectionStarted() }
            done.continuation.yield()
        }
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in done.stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(finished)
        await events.drainSessionEvents()
    }
}

private final class MoveLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    func add(_ dx: Int16, _ dy: Int16) { record("\(dx),\(dy)") }
    func pause() { record("pause") }
    private func record(_ entry: String) { lock.lock(); log.append(entry); lock.unlock() }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return log }
}
