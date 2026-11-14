// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

@testable import GlimmerEngine
import Foundation
import os
import Testing
@testable import Glimmer

struct RateChangeExchangeTests {
    private static func answer(_ serial: UInt32, kbps: UInt32 = 30_000) -> RateChange.Result {
        RateChange.Result(serial: serial, bitrateKbps: kbps, fpsMillihz: 0,
                          bitrate: .init(status: .applied, reason: .none), fps: .init(status: .unchanged, reason: .none))
    }

    @Test func aMatchingAnswerResolvesTheRequest() async {
        let exchange = RateChangeExchange()
        let result = await exchange.exchange(timeout: .seconds(5)) { serial in
            exchange.deliver(Self.answer(serial))
            return true
        }
        #expect(result?.bitrateKbps == 30_000)
    }

    @Test func anUnsentRequestResolvesAtOnceWithNothing() async {
        let exchange = RateChangeExchange()
        #expect(await exchange.exchange(timeout: .seconds(5)) { _ in false } == nil)
    }

    @Test func silenceEndsAtTheDeadlineAndALateAnswerIsDropped() async {
        let exchange = RateChangeExchange()
        let sent = OSAllocatedUnfairLock<UInt32>(initialState: 0)
        let result = await exchange.exchange(timeout: .milliseconds(50)) { serial in
            sent.withLock { $0 = serial }
            return true
        }
        #expect(result == nil)
        exchange.deliver(Self.answer(sent.withLock { $0 }))
        let next = await exchange.exchange(timeout: .seconds(5)) { serial in
            exchange.deliver(Self.answer(serial, kbps: 20_000))
            return true
        }
        #expect(next?.bitrateKbps == 20_000)
    }

    @Test func anAnswerForAnotherSerialDoesNotResolveTheRequest() async {
        let exchange = RateChangeExchange()
        let result = await exchange.exchange(timeout: .milliseconds(50)) { serial in
            exchange.deliver(Self.answer(serial + 10))
            return true
        }
        #expect(result == nil)
    }

    @Test func anOlderAnswerArrivingAfterANewerOneIsNotTaken() async {
        let exchange = RateChangeExchange()
        let serials = OSAllocatedUnfairLock<[UInt32]>(initialState: [])
        async let older = exchange.exchange(timeout: .milliseconds(400)) { serial in
            serials.withLock { $0.append(serial) }
            return true
        }
        while serials.withLock({ $0.count }) < 1 { await Task.yield() }
        async let newer = exchange.exchange(timeout: .seconds(5)) { serial in
            serials.withLock { $0.append(serial) }
            return true
        }
        while serials.withLock({ $0.count }) < 2 { await Task.yield() }
        let sent = serials.withLock { $0 }
        exchange.deliver(Self.answer(sent[1], kbps: 25_000))
        exchange.deliver(Self.answer(sent[0], kbps: 35_000))
        #expect(await newer?.bitrateKbps == 25_000)
        #expect(await older == nil)
    }
}
