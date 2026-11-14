// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: 2026 ugfugl.io

import Foundation

extension EnetControlChannel {
    func handleRateChange(_ payload: [UInt8]) {
        guard payload.count <= RateChange.maxResultBytes, let result = RateChange.Result.decode(payload) else { return }
        onRateChange?(result)
    }

    /// Reliable, on the generic channel like every other 0x55xx request; false when not negotiated or unsent.
    @discardableResult
    func sendRateChange(_ request: RateChange.Request) -> Bool {
        guard rateChangeNegotiated else { return false }
        do {
            try sendEncryptedControl(type: RateChange.messageType, payload: request.encode(),
                                     channel: Enet.ctrlChannelGeneric, label: "rate change", requireConnection: true)
            return true
        } catch {
            Diag.error("ENet rate change request failed: \(error, privacy: .private)", Self.logCategory)
            return false
        }
    }
}
