// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

@testable import GlimmerEngine
import Foundation
import Testing

struct LaunchQueryExtensionsTests {

    private static let rubylight = """
        <RustHostVersion>4.4.0</RustHostVersion><VirtualDisplayCapable>1</VirtualDisplayCapable>
        <VirtualDisplayDriverReady>1</VirtualDisplayDriverReady><FrameLimiterSupported>1</FrameLimiterSupported>
        """
    private static let apollo = "<Permission>4294967295</Permission><VirtualDisplayCapable>1</VirtualDisplayCapable>"

    private static func request(fps: Int = 60, refreshX100: Int = 0, virtualDisplay: Bool = false,
                                hostDisplay: HostDisplay = .hostDefault) -> StreamRequest {
        var request = StreamRequest(width: 3840, height: 2160, fps: fps, bitrateKbps: 80_000, videoFormats: [.h264])
        request.virtualDisplay = virtualDisplay
        request.hostDisplay = hostDisplay
        request.displayRefreshX100 = refreshX100
        return request
    }

    private static func query(_ request: StreamRequest, _ fields: String, appID: Int? = 1) throws -> [String: String] {
        NetworkClient.launchQuery(config: request, riKeyHex: "00", riKeyID: 0, appID: appID,
                                  extensions: try HostExtensionsTests.extensions(fields))
    }

    private static let keysToday: Set<String> = [
        "mode", "additionalStates", "sops", "rikey", "rikeyid", "localAudioPlayMode", "surroundAudioInfo",
        "remoteControllersBitmap", "gcmap", "gcpersist", "corever", "appid"
    ]

    // MARK: - Hosts that report nothing

    @Test func stockSunshineGetsExactlyTheQueryItGetsToday() throws {
        let stock = "<appversion>7.1.431.-1</appversion><state>SUNSHINE_SERVER_FREE</state>"
        let asked = Self.request(refreshX100: 5994, virtualDisplay: true, hostDisplay: .extended)
        let plain = NetworkClient.launchQuery(config: Self.request(), riKeyHex: "00", riKeyID: 0, appID: 1)
        let query = try Self.query(asked, stock)
        #expect(Set(query.keys) == Self.keysToday)
        #expect(query == plain)
        #expect(query["mode"] == "3840x2160x60")
    }

    @Test func aHostThatReportsNothingIgnoresEveryNewSetting() throws {
        let query = try Self.query(Self.request(refreshX100: 5994, virtualDisplay: true, hostDisplay: .physical), "")
        #expect(Set(query.keys) == Self.keysToday)
    }

    // MARK: - virtualDisplay and scaleFactor

    @Test func virtualDisplayNeedsTheCapabilityAndTheSetting() throws {
        let on = try Self.query(Self.request(virtualDisplay: true), Self.apollo)
        #expect(on["virtualDisplay"] == "1")
        #expect(on["scaleFactor"] == "100")
        #expect(Set(on.keys).subtracting(Self.keysToday) == ["virtualDisplay", "scaleFactor"])
        #expect(try Set(Self.query(Self.request(virtualDisplay: false), Self.apollo).keys) == Self.keysToday)
        #expect(try Self.query(Self.request(virtualDisplay: true), "<Permission>1</Permission>")["virtualDisplay"] == nil)
    }

    @Test func aVirtualDisplayWithoutItsDriverIsNotRequested() throws {
        let fields = "<VirtualDisplayCapable>1</VirtualDisplayCapable><VirtualDisplayDriverReady>0</VirtualDisplayDriverReady>"
        #expect(try Self.query(Self.request(virtualDisplay: true), fields)["virtualDisplay"] == nil)
    }

    @Test func resumeCarriesTheSameDisplayKeysAsLaunch() throws {
        let launch = try Self.query(Self.request(virtualDisplay: true), Self.apollo)
        let resume = try Self.query(Self.request(virtualDisplay: true), Self.apollo, appID: nil)
        #expect(Set(launch.keys).subtracting(resume.keys) == ["appid"])
        #expect(resume["virtualDisplay"] == "1" && resume["scaleFactor"] == "100")
    }

    // MARK: - hostDisplay

    @Test func hostDisplayIsSentOnlyToRubylightWithAVirtualDisplay() throws {
        let extended = try Self.query(Self.request(hostDisplay: .extended), Self.rubylight)
        #expect(extended["hostDisplay"] == "extended")
        #expect(extended["virtualDisplay"] == "1")
        #expect(try Self.query(Self.request(hostDisplay: .extended), Self.apollo)["hostDisplay"] == nil)
        let old = Self.rubylight.replacingOccurrences(of: "4.4.0", with: "2.2.0")
        #expect(try Self.query(Self.request(hostDisplay: .extended), old)["hostDisplay"] == nil)
        let noDisplay = "<RustHostVersion>4.4.0</RustHostVersion>"
        #expect(try Self.query(Self.request(hostDisplay: .extended), noDisplay)["hostDisplay"] == nil)
    }

    @Test func thePhysicalChoiceNamesItselfAndAsksForNoVirtualDisplay() throws {
        let query = try Self.query(Self.request(virtualDisplay: true, hostDisplay: .physical), Self.rubylight)
        #expect(query["hostDisplay"] == "physical")
        #expect(query["virtualDisplay"] == nil && query["scaleFactor"] == nil)
    }

    @Test func theHostDefaultSendsNoHostDisplayAndFollowsTheToggle() throws {
        let off = try Self.query(Self.request(), Self.rubylight)
        #expect(Set(off.keys) == Self.keysToday)
        #expect(try Self.query(Self.request(virtualDisplay: true), Self.rubylight)["hostDisplay"] == nil)
    }

    // MARK: - Fractional refresh

    @Test(arguments: [
        (60, 5994, "59.94"), (120, 11988, "119.88"), (30, 2997, "29.97"), (60, 5995, "59.95"),
        (60, 6000, "60"), (60, 0, "60"), (120, 5994, "120"), (60, 5949, "60"), (60, 50, "60"), (60, 100_001, "60")
    ])
    func rubylightGetsTheDisplaysFractionalRateOnlyWhenItRoundsToTheStreams(fps: Int, x100: Int, rate: String) throws {
        let query = try Self.query(Self.request(fps: fps, refreshX100: x100), Self.rubylight)
        #expect(query["mode"] == "3840x2160x\(rate)")
    }

    @Test func eachHostFamilyThatReadsFractionsGetsThem() throws {
        let request = Self.request(refreshX100: 5994)
        for fields in [Self.rubylight, Self.apollo, "<FrameLimiterSupported>0</FrameLimiterSupported>"] {
            #expect(try Self.query(request, fields)["mode"] == "3840x2160x59.94")
        }
        #expect(try Self.query(request, "<GfeVersion>3.23.0.74</GfeVersion>")["mode"] == "3840x2160x60")
    }
}
