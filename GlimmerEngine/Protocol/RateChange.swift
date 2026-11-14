// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

import Foundation

/// Rubylight's mid-stream rate change (control message 0x553C), for a stream launched with `rlRateChange=1`.
package enum RateChange {
    package static let messageType: UInt16 = 0x553C
    package static let launchParameter = "rlRateChange"
    package static let requestBytes = 16
    package static let resultBytes = 20
    /// Longest result payload read; a newer PC may append fields.
    package static let maxResultBytes = 256
    private static let version: UInt8 = 1

    /// Little-endian: version, 3 reserved, serial, bitrate in kbps, frame rate in mHz; 0 keeps a value.
    package struct Request: Equatable, Sendable {
        package var serial: UInt32
        package var bitrateKbps: UInt32
        package var fpsMillihz: UInt32

        package func encode() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: RateChange.requestBytes)
            out[0] = RateChange.version
            RateChange.put(serial, into: &out, at: 4)
            RateChange.put(bitrateKbps, into: &out, at: 8)
            RateChange.put(fpsMillihz, into: &out, at: 12)
            return out
        }
    }

    package enum Status: UInt8, Sendable {
        case unchanged = 0, applied, clamped, refused
    }

    package enum Reason: Sendable, Equatable {
        case none, invalid, disabled, codec, hostLimit, encoderLimit, encoderFailed, superseded, other

        init(wire: UInt8) {
            let known: [Reason] = [.none, .invalid, .disabled, .codec, .hostLimit, .encoderLimit,
                                   .encoderFailed, .superseded]
            self = Int(wire) < known.count ? known[Int(wire)] : .other
        }
    }

    package struct Outcome: Equatable, Sendable {
        package var status: Status
        package var reason: Reason
    }

    /// What became of the request with `serial`, and the stream's bitrate and rate after it.
    package struct Result: Equatable, Sendable {
        package var serial: UInt32
        package var bitrateKbps: UInt32
        package var fpsMillihz: UInt32
        package var bitrate: Outcome
        package var fps: Outcome

        /// Rejects version 0, a short payload and an unknown status; bytes past 20 are ignored.
        package static func decode(_ data: [UInt8]) -> Result? {
            guard data.count >= RateChange.resultBytes, data[0] != 0,
                  let bitrate = outcome(data, at: 16), let fps = outcome(data, at: 18) else { return nil }
            return Result(serial: RateChange.read(data, at: 4), bitrateKbps: RateChange.read(data, at: 8),
                          fpsMillihz: RateChange.read(data, at: 12), bitrate: bitrate, fps: fps)
        }

        private static func outcome(_ data: [UInt8], at index: Int) -> Outcome? {
            Status(rawValue: data[index]).map { Outcome(status: $0, reason: Reason(wire: data[index + 1])) }
        }
    }

    /// Hands out serials and keeps a result from an older request from replacing a newer one's.
    package struct Serials: Sendable {
        private var issued: UInt32 = 0
        private var lastTaken: UInt32 = 0

        package init() {}

        package mutating func next() -> UInt32 {
            issued &+= 1
            return issued
        }

        /// True when no result for a later serial was taken before this one.
        package mutating func take(_ serial: UInt32) -> Bool {
            guard serial > lastTaken else { return false }
            lastTaken = serial
            return true
        }
    }

    private static func put(_ value: UInt32, into out: inout [UInt8], at index: Int) {
        for shift in 0..<4 { out[index + shift] = UInt8(truncatingIfNeeded: value >> (8 * UInt32(shift))) }
    }

    private static func read(_ data: [UInt8], at index: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[index + $1]) << (8 * UInt32($1)) }
    }
}
