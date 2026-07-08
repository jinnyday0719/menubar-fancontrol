import Foundation

public enum FanControlStrategy: Sendable {
    case directModeWrite
    case forceTestUnlock
}

public struct FanControlResult: Sendable {
    public let fanIndex: Int
    public let requestedRPM: Double
    public let appliedRPM: Double
    public let strategy: FanControlStrategy
}

public final class FanController: Sendable {
    private let smc: any SMCClient

    public init(smc: any SMCClient) {
        self.smc = smc
    }

    public convenience init() throws {
        try self.init(smc: SMCConnection())
    }

    public func setManual(fanIndex: Int, rpm requestedRPM: Double) throws -> FanControlResult {
        let minimum = smc.numericValue(for: "F\(fanIndex)Mn") ?? 0
        let maximum = smc.numericValue(for: "F\(fanIndex)Mx") ?? requestedRPM
        let appliedRPM = min(max(requestedRPM, minimum), maximum)
        let strategy = try enableManualMode(fanIndex: fanIndex)
        do {
            try writeRPM(fanIndex: fanIndex, rpm: appliedRPM)
        } catch {
            try? setAutomatic(fanIndex: fanIndex)
            throw error
        }

        return FanControlResult(
            fanIndex: fanIndex,
            requestedRPM: requestedRPM,
            appliedRPM: appliedRPM,
            strategy: strategy
        )
    }

    public func setAutomatic(fanIndex: Int) throws {
        let modeKey = fanModeKey(fanIndex: fanIndex)
        if let currentMode = smc.numericValue(for: modeKey), currentMode == 0 || currentMode == 3 {
            clearTestModeIfNeeded()
            return
        }

        do {
            try smc.write(modeKey, bytes: [0])
        } catch {
            if let currentMode = smc.numericValue(for: modeKey), currentMode == 0 || currentMode == 3 {
                clearTestModeIfNeeded()
                return
            }
            throw error
        }

        if (try? smc.read("F\(fanIndex)Tg").dataSize) != nil {
            try? writeRPM(fanIndex: fanIndex, rpm: 0)
        }

        clearTestModeIfNeeded()
    }

    private func enableManualMode(fanIndex: Int) throws -> FanControlStrategy {
        let modeKey = fanModeKey(fanIndex: fanIndex)

        if smc.numericValue(for: modeKey) == 1 {
            return .directModeWrite
        }

        do {
            try smc.write(modeKey, bytes: [1])
            if smc.numericValue(for: modeKey) == 1 {
                return .directModeWrite
            }
        } catch let directWriteError {
            guard hasKey("Ftst") else {
                throw directWriteError
            }
        }

        if smc.numericValue(for: "Ftst") != 1 {
            try writeWithRetry(key: "Ftst", bytes: [1], maxAttempts: 100, delay: 0.05)
            Thread.sleep(forTimeInterval: 3.0)
        }

        try writeWithRetry(key: modeKey, bytes: [1], maxAttempts: 300, delay: 0.1)
        return .forceTestUnlock
    }

    private func writeRPM(fanIndex: Int, rpm: Double) throws {
        let targetKey = "F\(fanIndex)Tg"
        let target = try smc.read(targetKey)

        switch target.dataType {
        case "flt ":
            var value = Float(rpm)
            let bytes = withUnsafeBytes(of: &value) { Array($0) }
            try smc.write(targetKey, bytes: bytes)
        case "fpe2":
            let intValue = Int(rpm.rounded())
            try smc.write(targetKey, bytes: [
                UInt8(intValue >> 6),
                UInt8((intValue << 2) ^ ((intValue >> 6) << 8))
            ])
        default:
            throw SMCError.firmwareRejected(key: targetKey, 0x89)
        }
    }

    private func fanModeKey(fanIndex: Int) -> String {
        if smc.numericValue(for: "F\(fanIndex)md") != nil {
            return "F\(fanIndex)md"
        }
        return "F\(fanIndex)Md"
    }

    private func allFansAreAutomatic() -> Bool {
        guard let count = smc.numericValue(for: "FNum") else {
            return true
        }

        for index in 0..<Int(count) {
            let mode = smc.numericValue(for: fanModeKey(fanIndex: index))
            guard mode == 0 || mode == 3 else {
                return false
            }
        }
        return true
    }

    private func clearTestModeIfNeeded() {
        if allFansAreAutomatic(), (try? smc.read("Ftst").dataSize) != nil {
            try? smc.write("Ftst", bytes: [0])
        }
    }

    private func hasKey(_ key: String) -> Bool {
        guard let value = try? smc.read(key) else {
            return false
        }
        return value.dataSize > 0
    }

    private func writeWithRetry(key: String, bytes: [UInt8], maxAttempts: Int, delay: TimeInterval) throws {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                try smc.write(key, bytes: bytes)
                return
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }

        if let lastError {
            throw lastError
        }
    }
}
