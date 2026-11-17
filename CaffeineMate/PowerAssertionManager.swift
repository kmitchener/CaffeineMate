//
//  PowerAssertionManager.swift
//  CaffeineMate
//
//  Created by Edd on 07/10/2025.
//

import Darwin
import Foundation
import IOKit.pwr_mgt

@MainActor
class PowerAssertionManager {
    static let shared = PowerAssertionManager()

    private var displayAssertionID: IOPMAssertionID?
    private var systemAssertionID: IOPMAssertionID?
    private var deadline: TimeInterval?
    private var durationTimer: Timer?

    var isActive: Bool { systemAssertionID != nil }
    var keepDisplayAwake: Bool { displayAssertionID != nil }

    // A nil countdown means the session is inactive or indefinite.
    var onStatusChanged: ((Int?) -> Void)?

    private init() {}

    func activate(keepDisplayAwake: Bool, durationMinutes: Int) throws {
        var newSystemAssertion: IOPMAssertionID?
        if !isActive {
            newSystemAssertion = try createAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                name: "CaffeineMate: Preventing System Sleep"
            )
        }

        do {
            if keepDisplayAwake && !self.keepDisplayAwake {
                displayAssertionID = try createAssertion(
                    type: kIOPMAssertionTypeNoDisplaySleep,
                    name: "CaffeineMate: Preventing Display Sleep"
                )
            }
        } catch {
            // Roll back a partial activation without interrupting an existing session.
            Self.releaseAssertion(&newSystemAssertion)
            throw error
        }

        if let newSystemAssertion {
            systemAssertionID = newSystemAssertion
        }
        if !keepDisplayAwake {
            Self.releaseAssertion(&displayAssertionID)
        }

        setCountdown(durationMinutes: durationMinutes)
        onStatusChanged?(remainingSeconds)
    }

    func deactivate() {
        Self.releaseAssertion(&displayAssertionID)
        Self.releaseAssertion(&systemAssertionID)
        setCountdown(durationMinutes: 0)
        onStatusChanged?(nil)
    }

    func toggle(keepDisplayAwake: Bool, durationMinutes: Int) throws {
        if isActive {
            deactivate()
        } else {
            try activate(keepDisplayAwake: keepDisplayAwake, durationMinutes: durationMinutes)
        }
    }

    private func createAssertion(type: String, name: String) throws -> IOPMAssertionID {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            throw PowerAssertionError(message: "\(name) failed (IOKit error \(result)).")
        }
        return assertionID
    }

    private static func releaseAssertion(_ id: inout IOPMAssertionID?) {
        guard let assertionID = id else { return }
        IOPMAssertionRelease(assertionID)
        id = nil
    }

    private func setCountdown(durationMinutes: Int) {
        durationTimer?.invalidate()
        durationTimer = nil
        deadline = nil
        guard durationMinutes > 0 else { return }

        deadline = monotonicTime + TimeInterval(durationMinutes) * 60
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // The timer is installed on the main run loop.
            MainActor.assumeIsolated {
                self?.updateCountdown()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private var monotonicTime: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    private var remainingSeconds: Int? {
        guard let deadline else { return nil }
        let seconds = max(0, (deadline - monotonicTime).rounded(.up))
        return Int(exactly: seconds) ?? Int.max
    }

    private func updateCountdown() {
        if let remainingSeconds, remainingSeconds > 0 {
            onStatusChanged?(remainingSeconds)
        } else {
            deactivate()
        }
    }
}

private struct PowerAssertionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
