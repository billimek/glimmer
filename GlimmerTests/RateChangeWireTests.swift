// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

@testable import GlimmerEngine
import Foundation
import Testing
@testable import Glimmer

struct RateChangeWireTests {
    private static let answer: [UInt8] = [1, 0, 0, 0, 0xD0, 0xC0, 0xB0, 0xA0, 0xF0, 0x49, 0x02, 0x00,
                                          0x60, 0xEA, 0x00, 0x00, 2, 4, 3, 3]

    @Test func requestEncodesLittleEndian() {
        let request = RateChange.Request(serial: 7, bitrateKbps: 40_000, fpsMillihz: 120_000)
        #expect(request.encode() == [1, 0, 0, 0, 7, 0, 0, 0, 0x40, 0x9C, 0, 0, 0xC0, 0xD4, 0x01, 0])
        let bitrateOnly = RateChange.Request(serial: 1, bitrateKbps: 30_000, fpsMillihz: 0)
        #expect(bitrateOnly.encode() == [1, 0, 0, 0, 1, 0, 0, 0, 0x30, 0x75, 0, 0, 0, 0, 0, 0])
    }

    @Test func resultDecodesBothOutcomes() throws {
        let result = try #require(RateChange.Result.decode(Self.answer))
        #expect(result.serial == 0xA0B0_C0D0)
        #expect(result.bitrateKbps == 150_000 && result.fpsMillihz == 60_000)
        #expect(result.bitrate == .init(status: .clamped, reason: .hostLimit))
        #expect(result.fps == .init(status: .refused, reason: .codec))
    }

    @Test func resultIgnoresBytesPastTheTwentyAndNamesUnknownReasons() throws {
        var longer = Self.answer
        longer[0] = 3
        longer += [9, 9, 9]
        #expect(RateChange.Result.decode(longer)?.serial == 0xA0B0_C0D0)
        var odd = Self.answer
        odd[19] = 99
        odd[17] = 255
        let decoded = try #require(RateChange.Result.decode(odd))
        #expect(decoded.fps.reason == .other && decoded.bitrate.reason == .other)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 6, 7])
    func everyKnownReasonByteDecodes(reason: Int) throws {
        var wire = Self.answer
        wire[17] = UInt8(reason)
        let decoded = try #require(RateChange.Result.decode(wire))
        #expect(decoded.bitrate.reason != .other)
    }

    @Test func resultRejectsVersionZeroShortPayloadsAndUnknownStatus() {
        var versionZero = Self.answer
        versionZero[0] = 0
        #expect(RateChange.Result.decode(versionZero) == nil)
        #expect(RateChange.Result.decode(Array(Self.answer.dropLast())) == nil)
        for index in [16, 18] {
            var bad = Self.answer
            bad[index] = 4
            #expect(RateChange.Result.decode(bad) == nil)
        }
    }

    @Test func aLaterSerialBeatsAnEarlierOneThatArrivesAfterIt() {
        var serials = RateChange.Serials()
        let issued = [serials.next(), serials.next(), serials.next()]
        let taken = [serials.take(2), serials.take(1), serials.take(2), serials.take(3)]
        #expect(issued == [1, 2, 3])
        #expect(taken == [true, false, false, true])
    }

    @Test func controlMessageListParsesHexDecimalAndSkipsJunk() {
        let sdp = "v=0\r\na=x-rl-control:0x5530, 0x5531,21810\r\na=x-other:1\n"
            + "a=x-rl-control:0x5530,bogus,0x10000,0x,,0X5540,+5,-1\n"
        #expect(SdpScan.controlMessages(sdp) == [0x5530, 0x5531, 0x5532, 0x5540])
        #expect(SdpScan.controlMessages("v=0\r\n").isEmpty)
        #expect(SdpScan.controlMessages("a=x-rl-control:").isEmpty)
        #expect(SdpScan.controlMessages("a=x-rl-control:0x553c").contains(RateChange.messageType))
        #expect(SdpScan.controlMessages("a=x-rl-control:21820").contains(RateChange.messageType))
        #expect(!SdpScan.controlMessages("a=x-rl-control:0x5530,0x5531").contains(RateChange.messageType))
    }

    @Test func controlMessageListIsCapped() {
        let many = (0..<40).map { String(0x5500 + $0) }.joined(separator: ",")
        #expect(SdpScan.controlMessages("a=x-rl-control:" + many).count == SdpScan.maxControlMessages)
    }
}
