// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

@testable import GlimmerEngine
import Foundation
import Testing

struct HostExtensionsTests {

    private static func extensions(_ fields: String, from start: HostExtensions = HostExtensions()) throws -> HostExtensions {
        let node = try XMLTreeBuilder.parse(data: Data("<root status_code=\"200\">\(fields)</root>".utf8))
        var result = start
        result.merge(from: node)
        return result
    }

    @Test func stockSunshineReportsNoExtensions() throws {
        let stock = try Self.extensions("""
            <hostname>TOWER</hostname><appversion>7.1.431.-1</appversion><GfeVersion>3.23.0.74</GfeVersion>
            <ServerCodecModeSupport>197377</ServerCodecModeSupport><state>SUNSHINE_SERVER_FREE</state>
            """)
        #expect(stock == HostExtensions())
        #expect(!stock.virtualDisplayAvailable && !stock.offersHostDisplayModes && !stock.readsFractionalRefresh)
    }

    @Test func rubylightFieldsEnableEveryExtension() throws {
        let info = try Self.extensions("""
            <RustHostVersion>4.4.0</RustHostVersion><VirtualDisplayCapable>1</VirtualDisplayCapable>
            <VirtualDisplayDriverReady>1</VirtualDisplayDriverReady><FrameLimiterSupported>1</FrameLimiterSupported>
            """)
        #expect(info.isRubylight && info.virtualDisplayAvailable)
        #expect(info.offersHostDisplayModes && info.readsFractionalRefresh)
    }

    @Test func apolloStyleFieldsAllowVirtualDisplayAndFractionalRefreshOnly() throws {
        let info = try Self.extensions("<Permission>4294967295</Permission><VirtualDisplayCapable>1</VirtualDisplayCapable>")
        #expect(info.virtualDisplayAvailable && info.readsFractionalRefresh)
        #expect(!info.isRubylight && !info.offersHostDisplayModes)
    }

    @Test func aVirtualDisplayNeedsItsDriverReady() throws {
        let broken = try Self.extensions("""
            <VirtualDisplayCapable>1</VirtualDisplayCapable><VirtualDisplayDriverReady>0</VirtualDisplayDriverReady>
            """)
        #expect(!broken.virtualDisplayAvailable)
        #expect(try !Self.extensions("<VirtualDisplayCapable>0</VirtualDisplayCapable>").virtualDisplayAvailable)
    }

    @Test func aPartialReplyKeepsEarlierValuesAndAnEmptyVersionClearsRubylight() throws {
        let first = try Self.extensions("<RustHostVersion>4.4.0</RustHostVersion><VirtualDisplayCapable>1</VirtualDisplayCapable>")
        let partial = try Self.extensions("<hostname>TOWER</hostname>", from: first)
        #expect(partial == first)
        let cleared = try Self.extensions("<RustHostVersion></RustHostVersion>", from: first)
        #expect(!cleared.isRubylight)
    }

    @Test(arguments: [
        ("2.2.1", true), ("2.2.2", true), ("2.3.0", true), ("3.0.0", true), ("4.4.0+abc.1", true),
        ("2.2.0", false), ("2.1.9", false), ("1.9.9", false), ("2.2.1-rc.3", false), ("3.0.0-beta.1", true),
        ("2.2", false), ("2.2.1.4", false), ("x.y.z", false), ("", false), ("2.2.1-nightly.1", false)
    ])
    func hostDisplayModesNeedRubylight221OrLater(version: String, expected: Bool) throws {
        var info = try Self.extensions("<VirtualDisplayCapable>1</VirtualDisplayCapable>")
        info.rubylightVersion = version
        #expect(info.offersHostDisplayModes == expected)
    }

    @Test func hostDisplayWireValuesAndVirtualDisplayRequests() {
        let wire = HostDisplay.allCases.map(\.wireValue)
        #expect(wire == [nil, "exclusive", "extended_primary", "extended", "extended_isolated",
                         "extended_primary_isolated", "physical"])
        #expect(HostDisplay.hostDefault.requestsVirtualDisplay(setting: true))
        #expect(!HostDisplay.hostDefault.requestsVirtualDisplay(setting: false))
        #expect(!HostDisplay.physical.requestsVirtualDisplay(setting: true))
        #expect(HostDisplay.extended.requestsVirtualDisplay(setting: false))
    }
}
