// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

import Foundation

/// What the PC's /serverinfo says it can do beyond Sunshine. Stock Sunshine and GFE send none of these
/// fields, so every capability is off for them and the launch query is unchanged.
package struct HostExtensions: Sendable, Equatable {
    /// `RustHostVersion`: present only on Rubylight.
    package var rubylightVersion: String?
    package var virtualDisplayCapable: Bool?
    package var virtualDisplayDriverReady: Bool?
    /// `FrameLimiterSupported`, which Vibepollo and Rubylight send.
    package var frameLimiterSupported: Bool?
    /// `Permission`, which Apollo and its descendants send.
    package var reportsPermissions = false

    package init() {}

    package var isRubylight: Bool { rubylightVersion != nil }

    package var virtualDisplayAvailable: Bool {
        virtualDisplayCapable == true && virtualDisplayDriverReady != false
    }

    /// Rubylight 2.2.1 or later with a virtual display to place the stream on.
    package var offersHostDisplayModes: Bool {
        guard let version = rubylightVersion, Self.isRelease(version, atLeast: (2, 2, 1)) else { return false }
        return virtualDisplayAvailable
    }

    /// Hosts that read "59.94" in the launch mode; Sunshine would truncate it to 59.
    package var readsFractionalRefresh: Bool {
        isRubylight || frameLimiterSupported != nil || reportsPermissions
    }

    /// Fields the reply leaves out keep their earlier value, like the rest of the /serverinfo state.
    package mutating func merge(from xml: XMLNode) {
        if let version = xml.string(forChild: "RustHostVersion") {
            rubylightVersion = version.isEmpty ? nil : version
        }
        if let flag = Self.flag(xml.string(forChild: "VirtualDisplayCapable")) { virtualDisplayCapable = flag }
        if let flag = Self.flag(xml.string(forChild: "VirtualDisplayDriverReady")) { virtualDisplayDriverReady = flag }
        if let flag = Self.flag(xml.string(forChild: "FrameLimiterSupported")) { frameLimiterSupported = flag }
        if xml.string(forChild: "Permission") != nil { reportsPermissions = true }
    }

    private static func flag(_ text: String?) -> Bool? {
        switch text?.lowercased() {
        case "1", "true": return true
        case "0", "false": return false
        default: return nil
        }
    }

    /// "2.2.1", "2.2.1+build" or "3.0.0-beta.1": a pre-release ranks below its release.
    static func isRelease(_ version: String, atLeast minimum: (Int, Int, Int)) -> Bool {
        let core = version.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.allSatisfy(\.isNumber) && !$0.isEmpty ? Int($0) : nil }
        guard numbers.count == 3, let major = numbers[0], let minor = numbers[1], let patch = numbers[2] else {
            return false
        }
        let preRelease = parts.count > 1
        if preRelease, !["alpha.", "beta.", "rc."].contains(where: { parts[1].hasPrefix($0) }) { return false }
        if (major, minor, patch) == minimum { return !preRelease }
        return (major, minor, patch) > minimum
    }
}

/// What the PC does with its displays during a stream (Rubylight's `hostDisplay`).
public enum HostDisplay: String, Sendable, CaseIterable {
    case hostDefault = "default"
    case exclusive
    case extendedPrimary = "extended_primary"
    case extended
    case extendedIsolated = "extended_isolated"
    case extendedPrimaryIsolated = "extended_primary_isolated"
    case physical

    /// The query value; the PC's own setting decides when nothing is sent.
    package var wireValue: String? { self == .hostDefault ? nil : rawValue }

    /// The PC builds a virtual display for every choice but its own setting and the physical one.
    package func requestsVirtualDisplay(setting: Bool) -> Bool {
        switch self {
        case .hostDefault: return setting
        case .physical: return false
        default: return true
        }
    }
}
