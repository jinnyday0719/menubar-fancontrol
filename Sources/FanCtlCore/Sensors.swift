import Foundation

public struct TemperatureSensorReading: Sendable {
    public let key: String
    public let celsius: Double
}

public struct GPUTemperatureSnapshot: Sendable {
    public let averageCelsius: Double
    public let sensors: [TemperatureSensorReading]
    public let profileIdentifier: String
}

public struct FanSnapshot: Sendable {
    public let index: Int
    public let actualRPM: Double
    public let targetRPM: Double?
    public let minimumRPM: Double?
    public let maximumRPM: Double?
    public let mode: Int?
}

public struct SensorSnapshot: Sendable {
    public let hardware: HardwareProfile
    public let gpuTemperature: GPUTemperatureSnapshot?
    public let fans: [FanSnapshot]
    public let fanTestMode: Int?
    public let fanReadError: String?
}

public final class SensorReader: Sendable {
    private static let plausibleGPUTemperatureRange = 10.0..<130.0

    private let smc: any SMCClient
    private let hardware: HardwareProfile

    public init(smc: any SMCClient, hardware: HardwareProfile = .current) {
        self.smc = smc
        self.hardware = hardware
    }

    public convenience init(hardware: HardwareProfile = .current) throws {
        try self.init(smc: SMCConnection(), hardware: hardware)
    }

    public func snapshot() -> SensorSnapshot {
        let gpuTemperature = readGPUTemperature()
        do {
            return SensorSnapshot(
                hardware: hardware,
                gpuTemperature: gpuTemperature,
                fans: try readFansStrict(),
                fanTestMode: try readOptionalInteger("Ftst"),
                fanReadError: nil
            )
        } catch {
            return SensorSnapshot(
                hardware: hardware,
                gpuTemperature: gpuTemperature,
                fans: [],
                fanTestMode: nil,
                fanReadError: error.localizedDescription
            )
        }
    }

    public func snapshotStrict() throws -> SensorSnapshot {
        SensorSnapshot(
            hardware: hardware,
            gpuTemperature: readGPUTemperature(),
            fans: try readFansStrict(),
            fanTestMode: try readOptionalInteger("Ftst"),
            fanReadError: nil
        )
    }

    public func readGPUTemperature() -> GPUTemperatureSnapshot? {
        let profile = sensorProfile(for: hardware)
        let readings = profile.gpuClusterKeys.compactMap { key -> TemperatureSensorReading? in
            guard let value = smc.numericValue(for: key),
                  Self.plausibleGPUTemperatureRange.contains(value) else {
                return nil
            }
            return TemperatureSensorReading(key: key, celsius: value)
        }

        guard !readings.isEmpty else {
            return nil
        }

        let average = readings.map(\.celsius).reduce(0, +) / Double(readings.count)
        return GPUTemperatureSnapshot(
            averageCelsius: average,
            sensors: readings,
            profileIdentifier: profile.identifier
        )
    }

    public func readFans() throws -> [FanSnapshot] {
        try readFansStrict()
    }

    public func readFansStrict() throws -> [FanSnapshot] {
        let rawCount = try readNumeric("FNum")
        guard rawCount >= 0,
              rawCount <= 10,
              rawCount.rounded(.towardZero) == rawCount else {
            throw FanControlError.invalidFanCount(rawCount)
        }

        return try (0..<Int(rawCount)).map { index in
            return FanSnapshot(
                index: index,
                actualRPM: try readNumeric("F\(index)Ac"),
                targetRPM: try readOptionalNumeric("F\(index)Tg"),
                minimumRPM: try readOptionalNumeric("F\(index)Mn"),
                maximumRPM: try readOptionalNumeric("F\(index)Mx"),
                mode: try readFanModeStrict(index: index)
            )
        }
    }

    private func readFanModeStrict(index: Int) throws -> Int? {
        do {
            return try integerValue("F\(index)md")
        } catch SMCError.firmwareRejected(_, let code) where code == 0x84 {
            return try readOptionalInteger("F\(index)Md")
        }
    }

    private func readNumeric(_ key: String) throws -> Double {
        let value = try smc.read(key)
        guard let numeric = value.numericValue, numeric.isFinite else {
            throw SMCError.invalidNumericValue(key: key)
        }
        return numeric
    }

    private func readOptionalNumeric(_ key: String) throws -> Double? {
        do {
            return try readNumeric(key)
        } catch SMCError.firmwareRejected(_, let code) where code == 0x84 {
            return nil
        }
    }

    private func integerValue(_ key: String) throws -> Int {
        let numeric = try readNumeric(key)
        guard numeric.rounded(.towardZero) == numeric,
              numeric >= Double(Int.min),
              numeric <= Double(Int.max) else {
            throw SMCError.invalidNumericValue(key: key)
        }
        return Int(numeric)
    }

    private func readOptionalInteger(_ key: String) throws -> Int? {
        do {
            return try integerValue(key)
        } catch SMCError.firmwareRejected(_, let code) where code == 0x84 {
            return nil
        }
    }
}
