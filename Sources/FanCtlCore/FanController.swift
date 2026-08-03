import Dispatch
import Foundation

public enum FanControlStrategy: Equatable, Sendable {
    case directModeWrite
    case forceTestUnlock
}

public enum ObservedFanMode: Equatable, Sendable {
    case automatic
    case manual
    case systemManaged
    case unknown(Int)

    public init(rawValue: Int) {
        switch rawValue {
        case 0:
            self = .automatic
        case 1:
            self = .manual
        case 3:
            self = .systemManaged
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .automatic: 0
        case .manual: 1
        case .systemManaged: 3
        case .unknown(let rawValue): rawValue
        }
    }

    public var isSystemControlled: Bool {
        self == .automatic || self == .systemManaged
    }
}

public struct FanModeState: Equatable, Sendable {
    public let fanIndex: Int
    public let mode: ObservedFanMode

    public init(fanIndex: Int, mode: ObservedFanMode) {
        self.fanIndex = fanIndex
        self.mode = mode
    }
}

public struct FanAutomaticControlStatus: Equatable, Sendable {
    public let fans: [FanModeState]
    public let forceTestMode: Int?

    public init(fans: [FanModeState], forceTestMode: Int?) {
        self.fans = fans
        self.forceTestMode = forceTestMode
    }

    public var isFullyAutomatic: Bool {
        !fans.isEmpty &&
            fans.allSatisfy(\.mode.isSystemControlled) &&
            (forceTestMode == nil || forceTestMode == 0)
    }
}

public struct FanControlResult: Sendable {
    public let fanIndex: Int
    public let requestedRPM: Double
    public let appliedRPM: Double
    public let strategy: FanControlStrategy
}

public enum FanControlError: Error, LocalizedError, Sendable {
    case invalidFanCount(Double)
    case invalidFanIndex(index: Int, fanCount: Int)
    case invalidRPM(Double)
    case invalidRPMRange(fanIndex: Int, minimum: Double, maximum: Double)
    case unsupportedSMCEncoding(key: String, dataType: String, dataSize: UInt32)
    case modeVerificationFailed(fanIndex: Int, expected: String, actual: Int)
    case valueVerificationFailed(key: String, expected: Int, actual: Int)
    case targetVerificationFailed(fanIndex: Int, expected: Double, actual: Double)
    case automaticBatchFailed(failures: [String])
    case rollbackFailed(originalError: String, rollbackError: String)
    case operationSuperseded

    public var errorDescription: String? {
        switch self {
        case .invalidFanCount(let value):
            "FNum returned an invalid fan count: \(value)."
        case .invalidFanIndex(let index, let fanCount):
            "Fan index \(index) is outside the available range 0..<\(fanCount)."
        case .invalidRPM(let rpm):
            "The requested fan speed must be a finite, nonnegative RPM value; received \(rpm)."
        case .invalidRPMRange(let fanIndex, let minimum, let maximum):
            "Fan \(fanIndex) returned an invalid RPM range \(minimum)...\(maximum)."
        case .unsupportedSMCEncoding(let key, let dataType, let dataSize):
            "SMC key \(key) uses unsupported encoding \(dataType) (\(dataSize) bytes)."
        case .modeVerificationFailed(let fanIndex, let expected, let actual):
            "Fan \(fanIndex) mode verification failed: expected \(expected), received raw mode \(actual)."
        case .valueVerificationFailed(let key, let expected, let actual):
            "SMC key \(key) verification failed: expected \(expected), received \(actual)."
        case .targetVerificationFailed(let fanIndex, let expected, let actual):
            "Fan \(fanIndex) target verification failed: expected \(expected) RPM, received \(actual) RPM."
        case .automaticBatchFailed(let failures):
            "Restoring automatic fan control failed: \(failures.joined(separator: "; "))."
        case .rollbackFailed(let originalError, let rollbackError):
            "Fan control failed (\(originalError)), and restoring the previous safe state also failed (\(rollbackError))."
        case .operationSuperseded:
            "The fan control operation was superseded by a newer request."
        }
    }
}

struct FanControlTiming: Sendable {
    let forceTestWriteAttempts: Int
    let forceTestWriteDelay: TimeInterval
    let forceTestActivationDelay: TimeInterval
    let manualModeWriteAttempts: Int
    let manualModeWriteDelay: TimeInterval
    let targetWriteAttempts: Int
    let targetWriteDelay: TimeInterval
    let automaticModeWriteAttempts: Int
    let automaticModeWriteDelay: TimeInterval
    let forceTestClearAttempts: Int
    let forceTestClearDelay: TimeInterval
    let maximumRetryDuration: TimeInterval
    let maximumRetryDelay: TimeInterval

    init(
        forceTestWriteAttempts: Int,
        forceTestWriteDelay: TimeInterval,
        forceTestActivationDelay: TimeInterval,
        manualModeWriteAttempts: Int,
        manualModeWriteDelay: TimeInterval,
        targetWriteAttempts: Int = 2,
        targetWriteDelay: TimeInterval = 0,
        automaticModeWriteAttempts: Int = 2,
        automaticModeWriteDelay: TimeInterval = 0,
        forceTestClearAttempts: Int = 2,
        forceTestClearDelay: TimeInterval = 0,
        maximumRetryDuration: TimeInterval = 5,
        maximumRetryDelay: TimeInterval = 0.25
    ) {
        let attempts = [
            forceTestWriteAttempts,
            manualModeWriteAttempts,
            targetWriteAttempts,
            automaticModeWriteAttempts,
            forceTestClearAttempts
        ]
        precondition(attempts.allSatisfy { $0 > 0 }, "Fan control retry attempts must be positive")

        let delays = [
            forceTestWriteDelay,
            forceTestActivationDelay,
            manualModeWriteDelay,
            targetWriteDelay,
            automaticModeWriteDelay,
            forceTestClearDelay,
            maximumRetryDuration,
            maximumRetryDelay
        ]
        precondition(
            delays.allSatisfy { $0.isFinite && $0 >= 0 },
            "Fan control retry delays must be finite and nonnegative"
        )

        self.forceTestWriteAttempts = forceTestWriteAttempts
        self.forceTestWriteDelay = forceTestWriteDelay
        self.forceTestActivationDelay = forceTestActivationDelay
        self.manualModeWriteAttempts = manualModeWriteAttempts
        self.manualModeWriteDelay = manualModeWriteDelay
        self.targetWriteAttempts = targetWriteAttempts
        self.targetWriteDelay = targetWriteDelay
        self.automaticModeWriteAttempts = automaticModeWriteAttempts
        self.automaticModeWriteDelay = automaticModeWriteDelay
        self.forceTestClearAttempts = forceTestClearAttempts
        self.forceTestClearDelay = forceTestClearDelay
        self.maximumRetryDuration = maximumRetryDuration
        self.maximumRetryDelay = maximumRetryDelay
    }

    static let production = FanControlTiming(
        // Enabling Ftst normally acknowledges quickly. Clearing it can lag
        // behind the per-fan mode transition on Apple Silicon, so Automatic
        // gets a separate bounded settle window below.
        forceTestWriteAttempts: 40,
        forceTestWriteDelay: 0.05,
        forceTestActivationDelay: 0.5,
        manualModeWriteAttempts: 150,
        manualModeWriteDelay: 0.1,
        targetWriteAttempts: 20,
        targetWriteDelay: 0.05,
        automaticModeWriteAttempts: 12,
        automaticModeWriteDelay: 0.05,
        forceTestClearAttempts: 50,
        forceTestClearDelay: 0.1,
        // This is a failure deadline, not a fixed delay. Successful mode
        // writes return immediately; transient firmware rejections can retry
        // for the full bounded window.
        maximumRetryDuration: 15,
        maximumRetryDelay: 0.1
    )

    static let immediate = FanControlTiming(
        forceTestWriteAttempts: 2,
        forceTestWriteDelay: 0,
        forceTestActivationDelay: 0,
        manualModeWriteAttempts: 2,
        manualModeWriteDelay: 0,
        targetWriteAttempts: 2,
        targetWriteDelay: 0,
        automaticModeWriteAttempts: 2,
        automaticModeWriteDelay: 0,
        forceTestClearAttempts: 2,
        forceTestClearDelay: 0,
        maximumRetryDuration: 1,
        maximumRetryDelay: 0
    )
}

// Every public operation is serialized by `controlLock`, including the
// transaction-local Ftst state below.
public final class FanController: @unchecked Sendable {
    private struct ManualPreflight {
        let fanIndex: Int
        let modeKey: String
        let modeValue: SMCValue
        let initialMode: ObservedFanMode
        let targetValue: SMCValue
        let initialTargetRPM: Double
    }

    private let smc: any SMCClient
    private let timing: FanControlTiming
    private let cancellationRequested: @Sendable () -> Bool
    private let controlLock = NSRecursiveLock()

    public init(smc: any SMCClient) {
        self.smc = smc
        self.timing = .production
        self.cancellationRequested = { false }
    }

    public init(
        smc: any SMCClient,
        cancellationRequested: @escaping @Sendable () -> Bool
    ) {
        self.smc = smc
        self.timing = .production
        self.cancellationRequested = cancellationRequested
    }

    convenience init(smc: any SMCClient, timing: FanControlTiming) {
        self.init(
            smc: smc,
            timing: timing,
            cancellationRequested: { false }
        )
    }

    init(
        smc: any SMCClient,
        timing: FanControlTiming,
        cancellationRequested: @escaping @Sendable () -> Bool
    ) {
        self.smc = smc
        self.timing = timing
        self.cancellationRequested = cancellationRequested
    }

    public convenience init() throws {
        try self.init(smc: SMCConnection())
    }

    public func fanCount() throws -> Int {
        controlLock.lock()
        defer { controlLock.unlock() }

        let rawCount = try readNumeric("FNum")
        guard rawCount >= 0,
              rawCount <= 10,
              rawCount.rounded(.towardZero) == rawCount else {
            throw FanControlError.invalidFanCount(rawCount)
        }
        return Int(rawCount)
    }

    public func automaticControlStatus() throws -> FanAutomaticControlStatus {
        controlLock.lock()
        defer { controlLock.unlock() }

        let count = try fanCount()
        let fans = try (0..<count).map { index in
            let resolved = try resolveFanMode(fanIndex: index)
            return FanModeState(fanIndex: index, mode: resolved.mode)
        }
        let forceTest = try readOptionalValue("Ftst").map { value in
            try integerValue(value, key: "Ftst")
        }
        return FanAutomaticControlStatus(fans: fans, forceTestMode: forceTest)
    }

    public func setManual(fanIndex: Int, rpm requestedRPM: Double) throws -> FanControlResult {
        controlLock.lock()
        defer { controlLock.unlock() }
        try throwIfCancellationRequested()

        guard requestedRPM.isFinite, requestedRPM >= 0 else {
            throw FanControlError.invalidRPM(requestedRPM)
        }
        try validateFanIndex(fanIndex)

        let resolvedMode = try resolveFanMode(fanIndex: fanIndex)
        let minimum = try readNumeric("F\(fanIndex)Mn")
        let maximum = try readNumeric("F\(fanIndex)Mx")
        guard minimum >= 0, maximum >= minimum else {
            throw FanControlError.invalidRPMRange(
                fanIndex: fanIndex,
                minimum: minimum,
                maximum: maximum
            )
        }

        let targetKey = "F\(fanIndex)Tg"
        let targetValue = try smc.read(targetKey)
        let initialTargetRPM = try numericValue(targetValue, key: targetKey)
        let appliedRPM = min(max(requestedRPM, minimum), maximum)
        _ = try encodeRPM(appliedRPM, for: targetValue)

        let preflight = ManualPreflight(
            fanIndex: fanIndex,
            modeKey: resolvedMode.key,
            modeValue: resolvedMode.value,
            initialMode: resolvedMode.mode,
            targetValue: targetValue,
            initialTargetRPM: initialTargetRPM
        )

        do {
            let strategy = try enableManualMode(
                preflight: preflight,
                deadline: retryDeadline()
            )
            try throwIfCancellationRequested()
            let verifiedRPM = try writeRPMWithRetry(
                preflight: preflight,
                rpm: appliedRPM,
                targetValue: targetValue,
                deadline: targetRetryDeadline()
            )

            return FanControlResult(
                fanIndex: fanIndex,
                requestedRPM: requestedRPM,
                appliedRPM: verifiedRPM,
                strategy: strategy
            )
        } catch {
            do {
                // Safety recovery gets a fresh bounded window even if the
                // primary operation exhausted its deadline.
                try rollback(
                    preflight,
                    deadline: retryDeadline(
                        maximumDuration: min(timing.maximumRetryDuration, 5)
                    )
                )
            } catch let rollbackError {
                throw FanControlError.rollbackFailed(
                    originalError: error.localizedDescription,
                    rollbackError: rollbackError.localizedDescription
                )
            }
            throw error
        }
    }

    public func setAutomatic(fanIndex: Int) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        let modeDeadline = retryDeadline()

        try validateFanIndex(fanIndex)
        let resolved = try resolveFanMode(fanIndex: fanIndex)
        try restoreSystemControl(
            fanIndex: fanIndex,
            modeKey: resolved.key,
            modeValue: resolved.value,
            deadline: modeDeadline
        )
    }

    /// Restores every fan in one transaction-like pass. This avoids repeating
    /// fan-count, all-fan safety, and Ftst verification for each individual fan.
    public func setAutomatic() throws {
        controlLock.lock()
        defer { controlLock.unlock() }

        let modeDeadline = retryDeadline()
        let count = try fanCount()
        guard count > 0 else {
            throw FanControlError.invalidFanCount(Double(count))
        }
        var failures: [String] = []

        for fanIndex in 0..<count {
            do {
                let resolved = try resolveFanMode(fanIndex: fanIndex)
                if !resolved.mode.isSystemControlled {
                    _ = try writeSystemModeWithRetry(
                        fanIndex: fanIndex,
                        modeKey: resolved.key,
                        reference: resolved.value,
                        deadline: modeDeadline
                    )
                }
            } catch {
                failures.append("fan \(fanIndex): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            // A reported write/read failure can still leave every fan in a
            // system-controlled mode. Re-check the complete set and clear Ftst
            // only when that is demonstrably safe.
            do {
                if try clearForceTestModeWhenSafe(deadline: forceTestClearRetryDeadline()) {
                    return
                }
            } catch {
                failures.append("final recovery: \(error.localizedDescription)")
            }
            throw FanControlError.automaticBatchFailed(failures: failures)
        }

        do {
            try clearForceTestModeAfterBatch(
                fanCount: count,
                deadline: forceTestClearRetryDeadline()
            )
        } catch {
            throw FanControlError.automaticBatchFailed(
                failures: ["final verification: \(error.localizedDescription)"]
            )
        }
    }

    private func validateFanIndex(_ fanIndex: Int) throws {
        let count = try fanCount()
        guard fanIndex >= 0, fanIndex < count else {
            throw FanControlError.invalidFanIndex(index: fanIndex, fanCount: count)
        }
    }

    private func enableManualMode(
        preflight: ManualPreflight,
        deadline: UInt64
    ) throws -> FanControlStrategy {
        try throwIfCancellationRequested()
        if preflight.initialMode == .manual {
            return .directModeWrite
        }

        var directWriteError: Error?
        let directWriteAttempts = 3
        for attempt in 0..<directWriteAttempts {
            try throwIfCancellationRequested()
            do {
                try writeInteger(1, key: preflight.modeKey, reference: preflight.modeValue)
                // A successful write can lead its readback by a few hundred
                // milliseconds. Wait briefly before deciding it was ignored;
                // this keeps later fans on the direct fast path without
                // trusting an acknowledged-but-unapplied write indefinitely.
                if try waitForManualModeReadback(
                    fanIndex: preflight.fanIndex,
                    modeKey: preflight.modeKey
                ) {
                    return .directModeWrite
                }
                directWriteError = FanControlError.modeVerificationFailed(
                    fanIndex: preflight.fanIndex,
                    expected: "manual (raw mode 1)",
                    actual: preflight.initialMode.rawValue
                )
                break
            } catch {
                if let observed = try? readMode(key: preflight.modeKey), observed == .manual {
                    return .directModeWrite
                }
                directWriteError = error
                if let code = firmwareResultCode(error), code == 0x80 || code == 0x81 {
                    guard waitBeforeRetry(
                        after: attempt,
                        maxAttempts: directWriteAttempts,
                        initialDelay: 0.05,
                        maximumDelay: min(0.05, timing.maximumRetryDelay),
                        deadline: deadline
                    ) else {
                        break
                    }
                    continue
                }
                break
            }
        }
        if let directWriteError, !isManualUnlockCandidate(directWriteError) {
            throw directWriteError
        }

        guard let forceTestValue = try readOptionalValue("Ftst") else {
            throw directWriteError ?? FanControlError.modeVerificationFailed(
                fanIndex: preflight.fanIndex,
                expected: "manual (raw mode 1)",
                actual: preflight.initialMode.rawValue
            )
        }

        var modeDeadline = deadline
        if try integerValue(forceTestValue, key: "Ftst") == 1 {
            // Ftst=1 inherited from an earlier command is not necessarily an
            // active hand-off when every fan is already system controlled.
            // Normalize that stale state to zero before creating a fresh edge.
            // If another fan is manual, clearing is unsafe and this returns
            // false; the same-value Ftst reassert below refreshes the unlock.
            if try clearForceTestModeWhenSafe(deadline: forceTestClearRetryDeadline()) {
                modeDeadline = retryDeadline()
            }
        }

        // The reference M3/M4 sequence reasserts Ftst whenever a direct mode
        // write is rejected, even if Ftst already reads as one. This avoids
        // carrying an expired diagnostic hand-off from another fan/request.
        try writeIntegerWithRetry(
            1,
            key: "Ftst",
            reference: forceTestValue,
            maxAttempts: timing.forceTestWriteAttempts,
            delay: timing.forceTestWriteDelay,
            acceptsMatchingReadbackAfterWriteError: false,
            checksCancellation: true,
            deadline: modeDeadline
        )
        try throwIfCancellationRequested()
        if timing.forceTestActivationDelay > 0 {
            waitForActivation(
                timing.forceTestActivationDelay,
                deadline: deadline
            )
        }

        // Ftst activation and the per-fan firmware hand-off are separate
        // phases. Give the mode transition its complete bounded window only
        // after thermalmonitord has had the activation grace period.
        modeDeadline = retryDeadline()
        try writeModeWithRetry(
            fanIndex: preflight.fanIndex,
            modeKey: preflight.modeKey,
            reference: preflight.modeValue,
            maxAttempts: timing.manualModeWriteAttempts,
            delay: timing.manualModeWriteDelay,
            deadline: modeDeadline
        )
        return .forceTestUnlock
    }

    private func rollback(_ preflight: ManualPreflight, deadline: UInt64) throws {
        if preflight.initialMode == .manual {
            _ = try writeRPMWithRetry(
                preflight: preflight,
                rpm: preflight.initialTargetRPM,
                targetValue: preflight.targetValue,
                checksCancellation: false,
                deadline: deadline
            )
            let mode = try readMode(key: preflight.modeKey)
            guard mode == .manual else {
                throw FanControlError.modeVerificationFailed(
                    fanIndex: preflight.fanIndex,
                    expected: "the previous manual state (raw mode 1)",
                    actual: mode.rawValue
                )
            }
            return
        }

        try restoreSystemControl(
            fanIndex: preflight.fanIndex,
            modeKey: preflight.modeKey,
            modeValue: preflight.modeValue,
            deadline: deadline
        )
    }

    private func restoreSystemControl(
        fanIndex: Int,
        modeKey: String,
        modeValue: SMCValue,
        deadline: UInt64
    ) throws {
        var observed = try readMode(key: modeKey)
        if !observed.isSystemControlled {
            observed = try writeSystemModeWithRetry(
                fanIndex: fanIndex,
                modeKey: modeKey,
                reference: modeValue,
                deadline: deadline
            )
        }

        _ = try clearForceTestModeWhenSafe(deadline: forceTestClearRetryDeadline())

        observed = try readMode(key: modeKey)
        guard observed.isSystemControlled else {
            throw FanControlError.modeVerificationFailed(
                fanIndex: fanIndex,
                expected: "automatic or system-managed (raw mode 0 or 3)",
                actual: observed.rawValue
            )
        }
    }

    private func clearForceTestModeWhenSafe(deadline: UInt64) throws -> Bool {
        let count = try fanCount()
        for index in 0..<count {
            guard try resolveFanMode(fanIndex: index).mode.isSystemControlled else {
                return false
            }
        }

        guard let forceTestValue = try readOptionalValue("Ftst") else {
            return true
        }
        let current = try integerValue(forceTestValue, key: "Ftst")
        guard current != 0 else {
            return true
        }

        try writeIntegerWithRetry(
            0,
            key: "Ftst",
            reference: forceTestValue,
            maxAttempts: timing.forceTestClearAttempts,
            delay: timing.forceTestClearDelay,
            acknowledgedWriteSettleAttempts: forceTestClearSettlePollAttempts(),
            deadline: deadline
        )

        try verifySystemControlAfterClearingForceTest(
            fanCount: count,
            deadline: deadline
        )
        return true
    }

    private func clearForceTestModeAfterBatch(
        fanCount: Int,
        deadline: UInt64
    ) throws {
        if let forceTestValue = try readOptionalValue("Ftst"),
           try integerValue(forceTestValue, key: "Ftst") != 0 {
            try writeIntegerWithRetry(
                0,
                key: "Ftst",
                reference: forceTestValue,
                maxAttempts: timing.forceTestClearAttempts,
                delay: timing.forceTestClearDelay,
                acknowledgedWriteSettleAttempts: forceTestClearSettlePollAttempts(),
                deadline: deadline
            )
        }

        try verifySystemControlAfterClearingForceTest(
            fanCount: fanCount,
            deadline: deadline
        )
    }

    private func writeRPM(fanIndex: Int, rpm: Double, targetValue: SMCValue) throws {
        let targetKey = "F\(fanIndex)Tg"
        try smc.write(
            targetKey,
            bytes: encodeRPM(rpm, for: targetValue),
            expectedDataSize: targetValue.dataSize
        )
    }

    private func writeRPMWithRetry(
        preflight: ManualPreflight,
        rpm: Double,
        targetValue: SMCValue,
        checksCancellation: Bool = true,
        deadline: UInt64
    ) throws -> Double {
        if checksCancellation {
            try throwIfCancellationRequested()
        }
        let targetKey = "F\(preflight.fanIndex)Tg"

        var needsWrite = true
        var lastWriteError: Error?
        var lastObservedRPM: Double?
        var lastReadError: Error?
        let reassertAttempt = timing.targetWriteAttempts >= 8
            ? (timing.targetWriteAttempts * 3) / 4
            : nil
        for attempt in 0..<timing.targetWriteAttempts {
            if checksCancellation {
                try throwIfCancellationRequested()
            }
            var wroteThisAttempt = false

            if needsWrite {
                do {
                    if checksCancellation {
                        try throwIfCancellationRequested()
                    }
                    wroteThisAttempt = true
                    try writeRPM(
                        fanIndex: preflight.fanIndex,
                        rpm: rpm,
                        targetValue: targetValue
                    )
                    needsWrite = false
                    lastWriteError = nil
                } catch FanControlError.operationSuperseded {
                    throw FanControlError.operationSuperseded
                } catch {
                    if let observed = try? readNumeric(targetKey), speedsMatch(observed, rpm) {
                        return try verifyManualModeAfterTarget(
                            preflight: preflight,
                            verifiedRPM: observed,
                            checksCancellation: checksCancellation
                        )
                    }
                    guard isRetryableTargetWriteFailure(error) else {
                        throw error
                    }
                    lastWriteError = error
                    // 0x87 can report failure after the target was committed;
                    // give it read-only settle time. The other transient codes
                    // mean the write should be retried on the next attempt.
                    needsWrite = firmwareResultCode(error) != 0x87
                }
            }

            do {
                let observedRPM = try readNumeric(targetKey)
                lastObservedRPM = observedRPM
                lastReadError = nil
                if speedsMatch(observedRPM, rpm) {
                    return try verifyManualModeAfterTarget(
                        preflight: preflight,
                        verifiedRPM: observedRPM,
                        checksCancellation: checksCancellation
                    )
                }
            } catch {
                guard isTransientReadbackFailure(error) else {
                    throw error
                }
                lastReadError = error
            }

            // An acknowledged target write normally only needs readback time.
            // Allow a long poll-only grace period, then re-assert at most once
            // so an ignored write can recover without continually restarting a
            // firmware-side pending update.
            if !needsWrite,
               !wroteThisAttempt,
               let reassertAttempt,
                attempt == reassertAttempt {
                do {
                    if checksCancellation {
                        try throwIfCancellationRequested()
                    }
                    try writeRPM(
                        fanIndex: preflight.fanIndex,
                        rpm: rpm,
                        targetValue: targetValue
                    )
                    lastWriteError = nil
                } catch FanControlError.operationSuperseded {
                    throw FanControlError.operationSuperseded
                } catch {
                    if let observed = try? readNumeric(targetKey), speedsMatch(observed, rpm) {
                        return try verifyManualModeAfterTarget(
                            preflight: preflight,
                            verifiedRPM: observed,
                            checksCancellation: checksCancellation
                        )
                    }
                    guard isRetryableTargetWriteFailure(error) else {
                        throw error
                    }
                    lastWriteError = error
                    needsWrite = firmwareResultCode(error) != 0x87
                }
            }

            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: timing.targetWriteAttempts,
                initialDelay: timing.targetWriteDelay,
                maximumDelay: timing.targetWriteDelay,
                deadline: deadline
            ) else {
                break
            }
        }

        let finalMode = try readMode(key: preflight.modeKey)
        guard finalMode == .manual else {
            throw FanControlError.modeVerificationFailed(
                fanIndex: preflight.fanIndex,
                expected: "manual after applying target RPM (raw mode 1)",
                actual: finalMode.rawValue
            )
        }
        if lastObservedRPM == nil, let lastReadError {
            throw lastReadError
        }
        if let lastWriteError {
            throw lastWriteError
        }
        throw FanControlError.targetVerificationFailed(
            fanIndex: preflight.fanIndex,
            expected: rpm,
            actual: lastObservedRPM ?? .nan
        )
    }

    private func verifyManualModeAfterTarget(
        preflight: ManualPreflight,
        verifiedRPM: Double,
        checksCancellation: Bool
    ) throws -> Double {
        // The mode readback can trail a successful mode/target write. Keep
        // final verification strict, but give that readback a short bounded
        // window rather than restarting the entire Ftst unlock sequence.
        let deadline = retryDeadline(maximumDuration: 1)
        var lastMode = ObservedFanMode.unknown(-1)
        while true {
            if checksCancellation {
                try throwIfCancellationRequested()
            }
            lastMode = try readMode(key: preflight.modeKey)
            if lastMode == .manual {
                return verifiedRPM
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else {
                throw FanControlError.modeVerificationFailed(
                    fanIndex: preflight.fanIndex,
                    expected: "manual after applying target RPM (raw mode 1)",
                    actual: lastMode.rawValue
                )
            }
            let remaining = TimeInterval(deadline - now) / 1_000_000_000
            Thread.sleep(forTimeInterval: min(0.05, remaining))
        }
    }

    private func encodeRPM(_ rpm: Double, for target: SMCValue) throws -> [UInt8] {
        guard rpm.isFinite, rpm >= 0 else {
            throw FanControlError.invalidRPM(rpm)
        }

        switch (target.dataType, target.dataSize) {
        case ("flt ", 4):
            var value = Float(rpm)
            guard value.isFinite else {
                throw FanControlError.invalidRPM(rpm)
            }
            return withUnsafeBytes(of: &value) { Array($0) }
        case ("fpe2", 2):
            let scaledRPM = (rpm * 4).rounded()
            guard scaledRPM <= Double(UInt16.max) else {
                throw FanControlError.invalidRPM(rpm)
            }
            let raw = UInt16(scaledRPM)
            return [UInt8(raw >> 8), UInt8(raw & 0xff)]
        default:
            throw FanControlError.unsupportedSMCEncoding(
                key: target.key,
                dataType: target.dataType,
                dataSize: target.dataSize
            )
        }
    }

    private func resolveFanMode(fanIndex: Int) throws -> (key: String, value: SMCValue, mode: ObservedFanMode) {
        var firstError: Error?
        for key in ["F\(fanIndex)md", "F\(fanIndex)Md"] {
            do {
                let value = try smc.read(key)
                let rawValue = try integerValue(value, key: key)
                return (key, value, ObservedFanMode(rawValue: rawValue))
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        throw firstError ?? SMCError.invalidNumericValue(key: "F\(fanIndex)Md")
    }

    private func readMode(key: String) throws -> ObservedFanMode {
        let value = try smc.read(key)
        return ObservedFanMode(rawValue: try integerValue(value, key: key))
    }

    private func readNumeric(_ key: String) throws -> Double {
        try numericValue(smc.read(key), key: key)
    }

    private func numericValue(_ value: SMCValue, key: String) throws -> Double {
        guard let numeric = value.numericValue, numeric.isFinite else {
            throw SMCError.invalidNumericValue(key: key)
        }
        return numeric
    }

    private func integerValue(_ value: SMCValue, key: String) throws -> Int {
        let numeric = try numericValue(value, key: key)
        guard numeric.rounded(.towardZero) == numeric,
              numeric >= Double(Int.min),
              numeric <= Double(Int.max) else {
            throw SMCError.invalidNumericValue(key: key)
        }
        return Int(numeric)
    }

    private func readOptionalValue(_ key: String) throws -> SMCValue? {
        do {
            return try smc.read(key)
        } catch SMCError.firmwareRejected(_, let code) where code == 0x84 {
            return nil
        }
    }

    private func writeInteger(_ rawValue: Int, key: String, reference: SMCValue) throws {
        try smc.write(
            key,
            bytes: try encodeInteger(rawValue, key: key, reference: reference),
            expectedDataSize: reference.dataSize
        )
    }

    private func encodeInteger(_ rawValue: Int, key: String, reference: SMCValue) throws -> [UInt8] {
        switch (reference.dataType, reference.dataSize) {
        case ("ui8 ", 1):
            guard let value = UInt8(exactly: rawValue) else {
                throw SMCError.invalidNumericValue(key: key)
            }
            return [value]
        case ("ui16", 2):
            guard let value = UInt16(exactly: rawValue) else {
                throw SMCError.invalidNumericValue(key: key)
            }
            return [UInt8(value >> 8), UInt8(value & 0xff)]
        case ("ui32", 4):
            guard let value = UInt32(exactly: rawValue) else {
                throw SMCError.invalidNumericValue(key: key)
            }
            return [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff)
            ]
        default:
            throw FanControlError.unsupportedSMCEncoding(
                key: key,
                dataType: reference.dataType,
                dataSize: reference.dataSize
            )
        }
    }

    private func writeIntegerWithRetry(
        _ rawValue: Int,
        key: String,
        reference: SMCValue,
        maxAttempts: Int,
        delay: TimeInterval,
        acceptsMatchingReadbackAfterWriteError: Bool = true,
        reassertsAcknowledgedWrite: Bool = true,
        acknowledgedWriteSettleAttempts: Int? = nil,
        checksCancellation: Bool = false,
        deadline: UInt64
    ) throws {
        let defaultSettlePollAttempts = maxAttempts <= 2 ? 1 : 3
        let settlePollAttempts = max(
            1,
            min(maxAttempts, acknowledgedWriteSettleAttempts ?? defaultSettlePollAttempts)
        )
        var needsWrite = true
        var nextReassertAttempt: Int?
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            if checksCancellation {
                try throwIfCancellationRequested()
            }
            if needsWrite {
                do {
                    try writeInteger(rawValue, key: key, reference: reference)
                    needsWrite = false
                    nextReassertAttempt = attempt + settlePollAttempts
                    lastError = nil
                } catch {
                    if acceptsMatchingReadbackAfterWriteError,
                       let verified = try? integerValue(smc.read(key), key: key),
                       verified == rawValue {
                        return
                    }
                    guard isRetryableForceTestWriteFailure(error) else {
                        throw error
                    }
                    lastError = error
                    guard waitBeforeRetry(
                        after: attempt,
                        maxAttempts: maxAttempts,
                        initialDelay: delay,
                        maximumDelay: delay,
                        deadline: deadline
                    ) else {
                        break
                    }
                    continue
                }
            }

            do {
                let verified = try integerValue(smc.read(key), key: key)
                if verified == rawValue {
                    return
                }
                lastError = FanControlError.valueVerificationFailed(
                    key: key,
                    expected: rawValue,
                    actual: verified
                )
            } catch {
                guard isTransientReadbackFailure(error) else {
                    throw error
                }
                lastError = error
            }

            // Verify before reasserting an acknowledged write. Some firmware
            // publishes the new value only after several reads; writing first
            // at this boundary can restart that pending transition forever.
            if reassertsAcknowledgedWrite,
               !needsWrite,
               let reassertAt = nextReassertAttempt,
               attempt >= reassertAt {
                do {
                    if checksCancellation {
                        try throwIfCancellationRequested()
                    }
                    try writeInteger(rawValue, key: key, reference: reference)
                    nextReassertAttempt = attempt + settlePollAttempts
                } catch {
                    if acceptsMatchingReadbackAfterWriteError,
                       let verified = try? integerValue(smc.read(key), key: key),
                       verified == rawValue {
                        return
                    }
                    guard isRetryableForceTestWriteFailure(error) else {
                        throw error
                    }
                    needsWrite = true
                    lastError = error
                }
            }
            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: maxAttempts,
                initialDelay: delay,
                maximumDelay: delay,
                deadline: deadline
            ) else {
                break
            }
        }
        throw lastError ?? SMCError.invalidNumericValue(key: key)
    }

    private func writeModeWithRetry(
        fanIndex: Int,
        modeKey: String,
        reference: SMCValue,
        maxAttempts: Int,
        delay: TimeInterval,
        deadline: UInt64
    ) throws {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            try throwIfCancellationRequested()
            do {
                try writeInteger(1, key: modeKey, reference: reference)
                if try waitForManualModeReadback(
                    fanIndex: fanIndex,
                    modeKey: modeKey
                ) {
                    return
                }
                lastError = FanControlError.modeVerificationFailed(
                    fanIndex: fanIndex,
                    expected: "manual (raw mode 1)",
                    actual: -1
                )
            } catch {
                if let observed = try? readMode(key: modeKey), observed == .manual {
                    return
                }
                guard isRetryableModeTransitionFailure(error) ||
                        isTransientReadbackFailure(error) else {
                    throw error
                }
                lastError = error
            }
            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: maxAttempts,
                initialDelay: delay,
                maximumDelay: delay,
                deadline: deadline
            ) else {
                break
            }
        }
        throw lastError ?? FanControlError.modeVerificationFailed(
            fanIndex: fanIndex,
            expected: "manual (raw mode 1)",
            actual: -1
        )
    }

    private func waitForManualModeReadback(
        fanIndex: Int,
        modeKey: String
    ) throws -> Bool {
        // Zero-delay test timings remain deterministic. Production gives a
        // successful SMC write up to 500 ms to appear before reasserting it.
        let settleDuration = timing.manualModeWriteDelay > 0
            ? min(0.5, timing.maximumRetryDuration)
            : 0
        let deadline = retryDeadline(maximumDuration: settleDuration)

        while true {
            try throwIfCancellationRequested()
            do {
                if try readMode(key: modeKey) == .manual {
                    return true
                }
            } catch {
                guard isTransientReadbackFailure(error) else {
                    throw error
                }
            }

            let now = DispatchTime.now().uptimeNanoseconds
            guard settleDuration > 0, now < deadline else {
                return false
            }
            let remaining = TimeInterval(deadline - now) / 1_000_000_000
            Thread.sleep(forTimeInterval: min(0.05, remaining))
        }
    }

    private func writeSystemModeWithRetry(
        fanIndex: Int,
        modeKey: String,
        reference: SMCValue,
        deadline: UInt64
    ) throws -> ObservedFanMode {
        let settlePollAttempts = timing.automaticModeWriteAttempts <= 2 ? 1 : 3
        var needsWrite = true
        var nextReassertAttempt: Int?
        var lastError: Error?
        for attempt in 0..<timing.automaticModeWriteAttempts {
            if needsWrite {
                do {
                    try writeInteger(0, key: modeKey, reference: reference)
                    needsWrite = false
                    nextReassertAttempt = attempt + settlePollAttempts
                    lastError = nil
                } catch {
                    if let observed = try? readMode(key: modeKey), observed.isSystemControlled {
                        return observed
                    }
                    guard isRetryableModeTransitionFailure(error) else {
                        throw error
                    }
                    lastError = error
                    guard waitBeforeRetry(
                        after: attempt,
                        maxAttempts: timing.automaticModeWriteAttempts,
                        initialDelay: timing.automaticModeWriteDelay,
                        maximumDelay: timing.automaticModeWriteDelay,
                        deadline: deadline
                    ) else {
                        break
                    }
                    continue
                }
            }

            do {
                let observed = try readMode(key: modeKey)
                if observed.isSystemControlled {
                    return observed
                }
                lastError = FanControlError.modeVerificationFailed(
                    fanIndex: fanIndex,
                    expected: "automatic or system-managed (raw mode 0 or 3)",
                    actual: observed.rawValue
                )
            } catch {
                guard isTransientReadbackFailure(error) else {
                    throw error
                }
                lastError = error
            }

            if !needsWrite,
               let reassertAt = nextReassertAttempt,
               attempt >= reassertAt {
                do {
                    try writeInteger(0, key: modeKey, reference: reference)
                    nextReassertAttempt = attempt + settlePollAttempts
                } catch {
                    if let observed = try? readMode(key: modeKey), observed.isSystemControlled {
                        return observed
                    }
                    guard isRetryableModeTransitionFailure(error) else {
                        throw error
                    }
                    needsWrite = true
                    lastError = error
                }
            }
            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: timing.automaticModeWriteAttempts,
                initialDelay: timing.automaticModeWriteDelay,
                maximumDelay: timing.automaticModeWriteDelay,
                deadline: deadline
            ) else {
                break
            }
        }
        throw lastError ?? FanControlError.modeVerificationFailed(
            fanIndex: fanIndex,
            expected: "automatic or system-managed (raw mode 0 or 3)",
            actual: -1
        )
    }

    private func verifySystemControlAfterClearingForceTest(
        fanCount: Int,
        deadline: UInt64
    ) throws {
        var lastError: Error?

        for attempt in 0..<timing.automaticModeWriteAttempts {
            var verificationFailures: [FanControlError] = []
            var nonRetryableFailures: [String] = []

            for fanIndex in 0..<fanCount {
                do {
                    let resolved = try resolveFanMode(fanIndex: fanIndex)
                    guard !resolved.mode.isSystemControlled else {
                        continue
                    }

                    try writeInteger(0, key: resolved.key, reference: resolved.value)
                    let verified = try readMode(key: resolved.key)
                    if !verified.isSystemControlled {
                        verificationFailures.append(FanControlError.modeVerificationFailed(
                            fanIndex: fanIndex,
                            expected: "automatic or system-managed after clearing Ftst",
                            actual: verified.rawValue
                        ))
                    }
                } catch {
                    if let resolved = try? resolveFanMode(fanIndex: fanIndex),
                       resolved.mode.isSystemControlled {
                        continue
                    }
                    if isRetryableModeTransitionFailure(error) {
                        verificationFailures.append(FanControlError.modeVerificationFailed(
                            fanIndex: fanIndex,
                            expected: "automatic or system-managed after clearing Ftst",
                            actual: -1
                        ))
                        continue
                    }
                    nonRetryableFailures.append(
                        "fan \(fanIndex): \(error.localizedDescription)"
                    )
                }
            }

            if !nonRetryableFailures.isEmpty {
                nonRetryableFailures.append(
                    contentsOf: verificationFailures.map(\.localizedDescription)
                )
                throw FanControlError.automaticBatchFailed(
                    failures: nonRetryableFailures
                )
            }

            guard !verificationFailures.isEmpty else {
                return
            }
            lastError = FanControlError.automaticBatchFailed(
                failures: verificationFailures.map(\.localizedDescription)
            )

            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: timing.automaticModeWriteAttempts,
                initialDelay: timing.automaticModeWriteDelay,
                maximumDelay: timing.automaticModeWriteDelay,
                deadline: deadline
            ) else {
                break
            }
        }

        throw lastError ?? FanControlError.modeVerificationFailed(
            fanIndex: -1,
            expected: "automatic or system-managed after clearing Ftst",
            actual: -1
        )
    }

    private func speedsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(1, abs(rhs) * 0.001)
    }

    private func isModeVerificationFailure(_ error: Error) -> Bool {
        guard case FanControlError.modeVerificationFailed = error else {
            return false
        }
        return true
    }

    private func isManualUnlockCandidate(_ error: Error) -> Bool {
        if isModeVerificationFailure(error) {
            return true
        }
        if let code = firmwareResultCode(error) {
            // Some firmware reports a rejected direct mode write instead of
            // silently retaining Automatic. Only the observed transient/unlock
            // results justify changing Ftst; structural key/size/access errors
            // must fail without entering diagnostic mode.
            return code == 0x82 || code == 0x85
        }
        return false
    }

    private func firmwareResultCode(_ error: Error) -> UInt8? {
        guard case SMCError.firmwareRejected(_, let code) = error else {
            return nil
        }
        return code
    }

    private func throwIfCancellationRequested() throws {
        if cancellationRequested() {
            throw FanControlError.operationSuperseded
        }
    }

    private func isRetryableForceTestWriteFailure(_ error: Error) -> Bool {
        guard let code = firmwareResultCode(error) else {
            return false
        }
        // Communication collision/spurious-data results can clear on retry.
        // Bad command/parameter, missing, read-only, write-only and size errors
        // describe a persistent request problem for Ftst.
        return code == 0x80 || code == 0x81
    }

    private func isRetryableModeTransitionFailure(_ error: Error) -> Bool {
        guard let code = firmwareResultCode(error) else {
            return false
        }
        // 0x82 is the observed M3/M4 response while thermalmonitord is yielding
        // control after Ftst. Other structural/access errors are not retried.
        return code == 0x80 || code == 0x81 || code == 0x82
    }

    private func isRetryableTargetWriteFailure(_ error: Error) -> Bool {
        guard let code = firmwareResultCode(error) else {
            return false
        }
        // 0x87 has been observed on Apple Silicon target writes whose values
        // were nevertheless committed. 0x82 can briefly occur at the end of
        // the manual-mode handoff; collision/spurious results are transient.
        return code == 0x80 || code == 0x81 || code == 0x82 || code == 0x87
    }

    private func isTransientReadbackFailure(_ error: Error) -> Bool {
        guard let code = firmwareResultCode(error) else {
            return false
        }
        return code == 0x80 || code == 0x81
    }

    private func retryDeadline(maximumDuration: TimeInterval? = nil) -> UInt64 {
        let duration = maximumDuration ?? timing.maximumRetryDuration
        let nanoseconds = UInt64(duration * 1_000_000_000)
        return DispatchTime.now().uptimeNanoseconds &+ nanoseconds
    }

    private func targetRetryDeadline() -> UInt64 {
        let pollingWindow = timing.targetWriteDelay *
            Double(max(0, timing.targetWriteAttempts - 1)) + 0.1
        return retryDeadline(
            maximumDuration: min(timing.maximumRetryDuration, pollingWindow)
        )
    }

    private func forceTestClearRetryDeadline() -> UInt64 {
        let pollingWindow = timing.forceTestClearDelay *
            Double(max(0, timing.forceTestClearAttempts - 1)) + 0.1
        return retryDeadline(
            maximumDuration: min(timing.maximumRetryDuration, max(1, pollingWindow))
        )
    }

    private func forceTestClearSettlePollAttempts() -> Int {
        // Leave most of the clear window read-only so an acknowledged firmware
        // transition can settle. Still permit a few sparse reassertions when a
        // successful SMC write was actually ignored.
        if timing.forceTestClearAttempts <= 2 {
            return 1
        }
        return max(3, timing.forceTestClearAttempts / 3)
    }

    private func waitForActivation(_ delay: TimeInterval, deadline: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else {
            return
        }
        let remaining = TimeInterval(deadline - now) / 1_000_000_000
        Thread.sleep(forTimeInterval: min(delay, remaining))
    }

    private func waitBeforeRetry(
        after attempt: Int,
        maxAttempts: Int,
        initialDelay: TimeInterval,
        maximumDelay: TimeInterval? = nil,
        deadline: UInt64
    ) -> Bool {
        guard attempt < maxAttempts - 1 else {
            return false
        }

        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else {
            return false
        }

        guard initialDelay > 0 else {
            return true
        }

        let exponent = min(attempt, 8)
        let backoff = initialDelay * pow(2, Double(exponent))
        let delay = min(backoff, maximumDelay ?? timing.maximumRetryDelay)
        let remaining = TimeInterval(deadline - now) / 1_000_000_000
        Thread.sleep(forTimeInterval: min(delay, remaining))
        return DispatchTime.now().uptimeNanoseconds < deadline
    }
}
