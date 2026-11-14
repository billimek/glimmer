// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

import Foundation

/// Pairs each rate change result with the request waiting on it; an answer after the deadline is dropped.
final class RateChangeExchange: @unchecked Sendable {
    private let lock = NSLock()
    private var serials = RateChange.Serials()
    private var waiting: [UInt32: CheckedContinuation<RateChange.Result?, Never>] = [:]

    func exchange(timeout: Duration, send: @Sendable (UInt32) -> Bool) async -> RateChange.Result? {
        await withCheckedContinuation { continuation in
            let serial = locked {
                let serial = serials.next()
                waiting[serial] = continuation
                return serial
            }
            guard send(serial) else { return finish(serial, with: nil) }
            Task {
                try? await Task.sleep(for: timeout)
                finish(serial, with: nil)
            }
        }
    }

    func deliver(_ result: RateChange.Result) {
        let continuation = locked { serials.take(result.serial) ? waiting.removeValue(forKey: result.serial) : nil }
        continuation?.resume(returning: result)
    }

    private func finish(_ serial: UInt32, with result: RateChange.Result?) {
        locked { waiting.removeValue(forKey: serial) }?.resume(returning: result)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

extension NativeBackend {
    static let rateChangeTimeout = Duration.seconds(2)

    package var supportsRateChange: Bool { withState { enetChannel?.rateChangeNegotiated ?? false } }

    package func changeBitrate(toKbps kbps: Int) async -> RateChange.Result? {
        guard let enet = withState({ enetChannel }), enet.rateChangeNegotiated,
              let target = UInt32(exactly: kbps), target > 0 else { return nil }
        return await rateChanges.exchange(timeout: Self.rateChangeTimeout) { serial in
            enet.sendRateChange(.init(serial: serial, bitrateKbps: target, fpsMillihz: 0))
        }
    }
}
