// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

@testable import GlimmerEngine
import Foundation
import Testing
@testable import Glimmer

/// Callbacks run synchronously on the test's thread, so plain storage is enough.
private final class Results {
    var values: [RateChange.Result] = []
}

struct EnetRateChangeTests {
    private static let answer: [UInt8] = [1, 0, 0, 0, 7, 0, 0, 0, 0x30, 0x75, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0]

    private static func channel(negotiated: Bool) throws -> (EnetControlChannel, Results) {
        let channel = EnetControlChannel(host: .ipv4(.loopback), port: 0, controlConnectData: 0,
                                         crypto: try ControlCrypto(rikey: EnetFixture.key), rateChangeNegotiated: negotiated)
        EnetFixture.connect(channel)
        let results = Results()
        channel.onRateChange = { results.values.append($0) }
        return (channel, results)
    }

    @Test func aNegotiatedChannelPassesResultsOn() throws {
        let (channel, results) = try Self.channel(negotiated: true)
        try EnetFixture.deliver(RateChange.messageType, Self.answer, to: channel)
        #expect(results.values.map(\.serial) == [7])
        #expect(results.values.first?.bitrateKbps == 30_000)
        #expect(results.values.first?.bitrate == .init(status: .applied, reason: .none))
    }

    @Test func anUnnegotiatedChannelIgnoresResults() throws {
        let (channel, results) = try Self.channel(negotiated: false)
        try EnetFixture.deliver(RateChange.messageType, Self.answer, to: channel)
        #expect(results.values.isEmpty)
    }

    @Test func malformedResultsAreDroppedAndTheNextGoodOneStillArrives() throws {
        let (channel, results) = try Self.channel(negotiated: true)
        var wrongVersion = Self.answer
        wrongVersion[0] = 0
        var unknownStatus = Self.answer
        unknownStatus[16] = 9
        let oversize = Self.answer + [UInt8](repeating: 0, count: RateChange.maxResultBytes)
        let payloads = [Array(Self.answer.dropLast()), wrongVersion, unknownStatus, oversize, Self.answer]
        for (index, payload) in payloads.enumerated() {
            channel.onDatagram(EnetFixture.datagram([EnetFixture.reliable(
                relSeq: UInt16(index + 1), try EnetFixture.sealed(RateChange.messageType, payload, seq: UInt32(index)))]))
        }
        #expect(results.values.map(\.serial) == [7])
    }

    @Test func aRequestGoesOutReliablyOnTheGenericChannel() throws {
        let (channel, _) = try Self.channel(negotiated: true)
        #expect(channel.sendRateChange(.init(serial: 7, bitrateKbps: 40_000, fpsMillihz: 0)))
        let sent = try #require(channel.withState { channel.sentReliable.first })
        #expect(sent.channelID == Enet.ctrlChannelGeneric)
        let command = sent.commandBytes
        #expect(command[0] == Enet.cmdSendReliable | Enet.flagAcknowledge)
        let inner = try EnetFixture.openClient(Array(command[6...]))
        #expect(inner == [0x3C, 0x55, 16, 0, 1, 0, 0, 0, 7, 0, 0, 0, 0x40, 0x9C, 0, 0, 0, 0, 0, 0])
    }

    @Test func nothingIsSentWithoutNegotiationOrAConnection() throws {
        let (plain, _) = try Self.channel(negotiated: false)
        #expect(!plain.sendRateChange(.init(serial: 1, bitrateKbps: 40_000, fpsMillihz: 0)))
        #expect(plain.withState { plain.sentReliable.isEmpty })
        let bare = EnetControlChannel(host: .ipv4(.loopback), port: 0, controlConnectData: 0,
                                      crypto: try ControlCrypto(rikey: EnetFixture.key), rateChangeNegotiated: true)
        #expect(!bare.sendRateChange(.init(serial: 1, bitrateKbps: 40_000, fpsMillihz: 0)))
        #expect(bare.withState { bare.sentReliable.isEmpty })
    }
}
