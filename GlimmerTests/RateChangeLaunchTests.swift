// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

@testable import GlimmerEngine
import Foundation
import Testing
@testable import Glimmer

struct RateChangeLaunchTests {
    private static let rubylight = """
        <root status_code="200"><hostname>DEN</hostname><RustHostVersion>4.4.0</RustHostVersion>
        <RustHostEncoderBitrateKbps>40000</RustHostEncoderBitrateKbps>
        <RustHostInitialEncoderBitrateKbps>40000</RustHostInitialEncoderBitrateKbps></root>
        """

    private static var config: StreamRequest {
        StreamConnection.Configuration(width: 3840, height: 2160, fps: 60, bitrateKbps: 40_000, videoFormats: .h264).request
    }

    private static func supports(_ reply: String, paired: Bool = true, seed: Bool = false) async throws -> Bool {
        var server = ServerInfo(address: "192.0.2.10", uniqueId: "", serverName: "")
        server.supportsRateChange = seed
        let client = NetworkClient(server: server)
        await client.hydrateServerInfo(from: try XMLTreeBuilder.parse(data: Data(reply.utf8)), fetchedOverPaired: paired)
        return await client.server.supportsRateChange
    }

    @Test func aStockSunshineQueryHasExactlyTodaysKeys() {
        let config = Self.config
        let keys = Set(NetworkClient.launchQuery(config: config, riKeyHex: "00", riKeyID: 0, appID: 1).keys)
        #expect(keys == ["mode", "additionalStates", "sops", "rikey", "rikeyid", "localAudioPlayMode",
                         "surroundAudioInfo", "remoteControllersBitmap", "gcmap", "gcpersist", "corever", "appid"])
    }

    @Test func theRequestAddsOnlyTheRateChangeKey() {
        let config = Self.config
        let plain = NetworkClient.launchQuery(config: config, riKeyHex: "00", riKeyID: 0, appID: nil)
        var asked = NetworkClient.launchQuery(config: config, riKeyHex: "00", riKeyID: 0, appID: nil,
                                              requestRateChange: true)
        #expect(asked["rlRateChange"] == "1")
        asked["rlRateChange"] = nil
        #expect(asked == plain)
    }

    @Test func onlyAPairedRubylightWithBothEncoderFieldsIsCapable() async throws {
        #expect(try await Self.supports(Self.rubylight))
        #expect(try await !Self.supports(Self.rubylight, paired: false))
        let noInitial = Self.rubylight.replacingOccurrences(of: "RustHostInitialEncoderBitrateKbps", with: "Other")
        #expect(try await !Self.supports(noInitial))
        let noVersion = Self.rubylight.replacingOccurrences(of: "<RustHostVersion>4.4.0</RustHostVersion>", with: "")
        #expect(try await !Self.supports(noVersion))
        let emptyVersion = Self.rubylight.replacingOccurrences(of: "4.4.0", with: "")
        #expect(try await !Self.supports(emptyVersion))
        let vibepollo = #"<root status_code="200"><FrameLimiterSupported>1</FrameLimiterSupported></root>"#
        #expect(try await !Self.supports(vibepollo))
        let sunshine = #"<root status_code="200"><appversion>7.1.431.-1</appversion></root>"#
        #expect(try await !Self.supports(sunshine))
    }

    @Test func aPairedReplyWithoutTheFieldsClearsAnEarlierYes() async throws {
        let sunshine = #"<root status_code="200"><appversion>7.1.431.-1</appversion></root>"#
        #expect(try await !Self.supports(sunshine, seed: true))
        #expect(try await Self.supports(sunshine, paired: false, seed: true))
    }

    @Test(arguments: [false, true])
    func resumeCarriesTheKeyOnlyForACapablePC(capable: Bool) async throws {
        let pc = FakeSunshine.scripted([
            "resume": [.success(FakeSunshine.xml("<resume>1</resume><sessionUrl0>rtsp://192.0.2.10:48010</sessionUrl0>"))]
        ])
        var server = FakeSunshine.server(pin: "host-pin")
        server.supportsRateChange = capable
        let config = Self.config
        _ = try await pc.client(server).resume(config: config)
        let query = try #require(pc.requests.first { $0.path == "/resume" }).query
        #expect(query["rlRateChange"] == (capable ? "1" : nil))
    }
}
