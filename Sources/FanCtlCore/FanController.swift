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
        // Keep the previous firmware-compatibility windows while using
        // exponentially fewer wakeups than fixed 50/100 ms polling.
        forceTestWriteAttempts: 14,
        forceTestWriteDelay: 0.05,
        forceTestActivationDelay: 0,
        manualModeWriteAttempts: 24,
        manualModeWriteDelay: 0.1,
        targetWriteAttempts: 8,
        targetWriteDelay: 0.05,
        automaticModeWriteAttempts: 12,
        automaticModeWriteDelay: 0.05,
        forceTestClearAttempts: 8,
        forceTestClearDelay: 0.05,
        maximumRetryDuration: 12,
        maximumRetryDelay: 0.5
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

public final class FanController: Sendable {
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
    private let controlLock = NSRecursiveLock()

    public init(smc: any SMCClient) {
        self.smc = smc
        self.timing = .production
    }

    init(smc: any SMCClient, timing: FanControlTiming) {
        self.smc = smc
        self.timing = timing
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
        let operationDeadline = retryDeadline()

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
                deadline: operationDeadline
            )
            let verifiedRPM = try writeRPMWithRetry(
                preflight: preflight,
                rpm: appliedRPM,
                targetValue: targetValue,
                deadline: operationDeadline
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
        let operationDeadline = retryDeadline()

        try validateFanIndex(fanIndex)
        let resolved = try resolveFanMode(fanIndex: fanIndex)
        try restoreSystemControl(
            fanIndex: fanIndex,
            modeKey: resolved.key,
            modeValue: resolved.value,
            deadline: operationDeadline
        )
    }

    /// Restores every fan in one transaction-like pass. This avoids repeating
    /// fan-count, all-fan safety, and Ftst verification for each individual fan.
    public func setAutomatic() throws {
        controlLock.lock()
        defer { controlLock.unlock() }

        let operationDeadline = retryDeadline()
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
                        deadline: operationDeadline
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
                if try clearForceTestModeWhenSafe(deadline: operationDeadline) {
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
                deadline: operationDeadline
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
        if preflight.initialMode == .manual {
            return .directModeWrite
        }

        var directWriteError: Error?
        do {
            try writeInteger(1, key: preflight.modeKey, reference: preflight.modeValue)
            let observed = try readMode(key: preflight.modeKey)
            guard observed == .manual else {
                throw FanControlError.modeVerificationFailed(
                    fanIndex: preflight.fanIndex,
                    expected: "manual (raw mode 1)",
                    actual: observed.rawValue
                )
            }
            return .directModeWrite
        } catch {
            guard isManualUnlockCandidate(error) else {
                throw error
            }
            directWriteError = error
        }

        guard let forceTestValue = try readOptionalValue("Ftst") else {
            throw directWriteError ?? FanControlError.modeVerificationFailed(
                fanIndex: preflight.fanIndex,
                expected: "manual (raw mode 1)",
                actual: preflight.initialMode.rawValue
            )
        }

        if try integerValue(forceTestValue, key: "Ftst") != 1 {
            try writeIntegerWithRetry(
                1,
                key: "Ftst",
                reference: forceTestValue,
                maxAttempts: timing.forceTestWriteAttempts,
                delay: timing.forceTestWriteDelay,
                deadline: deadline
            )
            if timing.forceTestActivationDelay > 0 {
                waitForActivation(
                    timing.forceTestActivationDelay,
                    deadline: deadline
                )
            }
        }

        try writeModeWithRetry(
            fanIndex: preflight.fanIndex,
            modeKey: preflight.modeKey,
            reference: preflight.modeValue,
            maxAttempts: timing.manualModeWriteAttempts,
            delay: timing.manualModeWriteDelay,
            deadline: deadline
        )
        return .forceTestUnlock
    }

    private func rollback(_ preflight: ManualPreflight, deadline: UInt64) throws {
        if preflight.initialMode == .manual {
            _ = try writeRPMWithRetry(
                preflight: preflight,
                rpm: preflight.initialTargetRPM,
                targetValue: preflight.targetValue,
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

        _ = try clearForceTestModeWhenSafe(deadline: deadline)

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
        try smc.write(targetKey, bytes: encodeRPM(rpm, for: targetValue))
    }

    private func writeRPMWithRetry(
        preflight: ManualPreflight,
        rpm: Double,
        targetValue: SMCValue,
        deadline: UInt64
    ) throws -> Double {
        let targetKey = "F\(preflight.fanIndex)Tg"
        var lastError: Error?

        for attempt in 0..<timing.targetWriteAttempts {
            let modeBeforeWrite = try readMode(key: preflight.modeKey)
            guard modeBeforeWrite == .manual else {
                throw FanControlError.modeVerificationFailed(
                    fanIndex: preflight.fanIndex,
                    expected: "manual while applying target RPM (raw mode 1)",
                    actual: modeBeforeWrite.rawValue
                )
            }

            do {
                try writeRPM(
                    fanIndex: preflight.fanIndex,
                    rpm: rpm,
                    targetValue: targetValue
                )
                let verifiedRPM = try readNumeric(targetKey)
                guard speedsMatch(verifiedRPM, rpm) else {
                    throw FanControlError.targetVerificationFailed(
                        fanIndex: preflight.fanIndex,
                        expected: rpm,
                        actual: verifiedRPM
                    )
                }

                let modeAfterWrite = try readMode(key: preflight.modeKey)
                guard modeAfterWrite == .manual else {
                    throw FanControlError.modeVerificationFailed(
                        fanIndex: preflight.fanIndex,
                        expected: "manual after applying target RPM (raw mode 1)",
                        actual: modeAfterWrite.rawValue
                    )
                }
                return verifiedRPM
            } catch {
                guard isTargetVerificationFailure(error) else {
                    throw error
                }
                lastError = error
            }

            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: timing.targetWriteAttempts,
                initialDelay: timing.targetWriteDelay,
                deadline: deadline
            ) else {
                break
            }
        }

        throw lastError ?? FanControlError.targetVerificationFailed(
            fanIndex: preflight.fanIndex,
            expected: rpm,
            actual: .nan
        )
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
        try smc.write(key, bytes: try encodeInteger(rawValue, key: key, reference: reference))
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
        deadline: UInt64
    ) throws {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                try writeInteger(rawValue, key: key, reference: reference)
                let verified = try integerValue(smc.read(key), key: key)
                guard verified == rawValue else {
                    throw FanControlError.valueVerificationFailed(
                        key: key,
                        expected: rawValue,
                        actual: verified
                    )
                }
                return
            } catch {
                guard isValueVerificationFailure(error) else {
                    throw error
                }
                lastError = error
            }
            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: maxAttempts,
                initialDelay: delay,
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
            do {
                try writeInteger(1, key: modeKey, reference: reference)
                let observed = try readMode(key: modeKey)
                guard observed == .manual else {
                    throw FanControlError.modeVerificationFailed(
                        fanIndex: fanIndex,
                        expected: "manual (raw mode 1)",
                        actual: observed.rawValue
                    )
                }
                return
            } catch {
                guard isModeVerificationFailure(error) else {
                    throw error
                }
                lastError = error
            }
            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: maxAttempts,
                initialDelay: delay,
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

    private func writeSystemModeWithRetry(
        fanIndex: Int,
        modeKey: String,
        reference: SMCValue,
        deadline: UInt64
    ) throws -> ObservedFanMode {
        var lastError: Error?
        for attempt in 0..<timing.automaticModeWriteAttempts {
            do {
                try writeInteger(0, key: modeKey, reference: reference)
                let observed = try readMode(key: modeKey)
                guard observed.isSystemControlled else {
                    throw FanControlError.modeVerificationFailed(
                        fanIndex: fanIndex,
                        expected: "automatic or system-managed (raw mode 0 or 3)",
                        actual: observed.rawValue
                    )
                }
                return observed
            } catch {
                guard isModeVerificationFailure(error) else {
                    throw error
                }
                lastError = error
            }
            guard waitBeforeRetry(
                after: attempt,
                maxAttempts: timing.automaticModeWriteAttempts,
                initialDelay: timing.automaticModeWriteDelay,
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
                    if isModeVerificationFailure(error),
                       let verificationFailure = error as? FanControlError {
                        verificationFailures.append(verificationFailure)
                    } else {
                        nonRetryableFailures.append(
                            "fan \(fanIndex): \(error.localizedDescription)"
                        )
                    }
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
        if case SMCError.firmwareRejected = error {
            // Some firmware reports a rejected direct mode write instead of
            // silently retaining Automatic. Ftst is the supported fallback
            // strategy for that state; the rejected write itself is not retried.
            return true
        }
        return false
    }

    private func isValueVerificationFailure(_ error: Error) -> Bool {
        guard case FanControlError.valueVerificationFailed = error else {
            return false
        }
        return true
    }

    private func isTargetVerificationFailure(_ error: Error) -> Bool {
        guard case FanControlError.targetVerificationFailed = error else {
            return false
        }
        return true
    }

    private func retryDeadline(maximumDuration: TimeInterval? = nil) -> UInt64 {
        let duration = maximumDuration ?? timing.maximumRetryDuration
        let nanoseconds = UInt64(duration * 1_000_000_000)
        return DispatchTime.now().uptimeNanoseconds &+ nanoseconds
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
        let delay = min(backoff, timing.maximumRetryDelay)
        let remaining = TimeInterval(deadline - now) / 1_000_000_000
        Thread.sleep(forTimeInterval: min(delay, remaining))
        return DispatchTime.now().uptimeNanoseconds < deadline
    }
}
