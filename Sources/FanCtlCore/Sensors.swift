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

public enum SensorSnapshotScope: Equatable, Sendable {
    /// Refresh every fan value. Use after a control operation, after wake, and
    /// periodically to reconcile mode/target/Ftst changes made elsewhere.
    case complete

    /// Refresh temperatures and actual RPM while reusing the last complete
    /// control-state sample. The first fast sample automatically becomes complete.
    case fast
}

public struct SensorSamplingCadence: Sendable {
    public let completeSnapshotInterval: TimeInterval
    private var lastCompleteSnapshotUptime: TimeInterval?

    public init(completeSnapshotInterval: TimeInterval) {
        precondition(
            completeSnapshotInterval.isFinite && completeSnapshotInterval > 0,
            "Complete sensor snapshot interval must be finite and positive"
        )
        self.completeSnapshotInterval = completeSnapshotInterval
    }

    public mutating func scope(
        at uptime: TimeInterval,
        forceComplete: Bool = false
    ) -> SensorSnapshotScope {
        guard !forceComplete, let lastCompleteSnapshotUptime else {
            return .complete
        }
        guard uptime.isFinite,
              uptime >= lastCompleteSnapshotUptime,
              uptime - lastCompleteSnapshotUptime < completeSnapshotInterval else {
            return .complete
        }
        return .fast
    }

    public mutating func recordSuccessfulSnapshot(
        scope: SensorSnapshotScope,
        at uptime: TimeInterval
    ) {
        guard scope == .complete, uptime.isFinite, uptime >= 0 else {
            return
        }
        lastCompleteSnapshotUptime = uptime
    }

    public mutating func invalidateControlState() {
        lastCompleteSnapshotUptime = nil
    }
}

extension FanControlError: SMCConnectionRecoveryClassifying {
    public var smcConnectionRecoveryDisposition: SMCConnectionRecoveryDisposition {
        // FanControlError represents decoded values or a verification result, not
        // an IOKit transport failure. Reopening AppleSMC would only add churn.
        .retainConnection
    }
}

public final class SensorReader: @unchecked Sendable {
    private static let plausibleGPUTemperatureRange = 10.0..<130.0

    private struct StaticFanData: Sendable {
        let index: Int
        let minimumRPM: Double?
        let maximumRPM: Double?
    }

    private struct FanControlState: Sendable {
        let targetRPM: Double?
        let mode: Int?
    }

    private struct ControlState: Sendable {
        let fans: [FanControlState]
        let fanTestMode: Int?
    }

    private let smc: any SMCClient
    private let hardware: HardwareProfile
    private let cacheLock = NSRecursiveLock()
    private var cachedStaticFanData: [StaticFanData]?
    private var cachedControlState: ControlState?

    public init(smc: any SMCClient, hardware: HardwareProfile = .current) {
        self.smc = smc
        self.hardware = hardware
    }

    public convenience init(hardware: HardwareProfile = .current) throws {
        try self.init(smc: SMCConnection(), hardware: hardware)
    }

    public func snapshot(scope: SensorSnapshotScope = .complete) -> SensorSnapshot {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let gpuTemperature = readGPUTemperatureUnlocked()
        do {
            let fanState = try readFanState(scope: scope)
            return SensorSnapshot(
                hardware: hardware,
                gpuTemperature: gpuTemperature,
                fans: fanState.fans,
                fanTestMode: fanState.fanTestMode,
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

    public func snapshotStrict(
        scope: SensorSnapshotScope = .complete
    ) throws -> SensorSnapshot {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let fanState = try readFanState(scope: scope)
        return SensorSnapshot(
            hardware: hardware,
            gpuTemperature: readGPUTemperatureUnlocked(),
            fans: fanState.fans,
            fanTestMode: fanState.fanTestMode,
            fanReadError: nil
        )
    }

    public func readGPUTemperature() -> GPUTemperatureSnapshot? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return readGPUTemperatureUnlocked()
    }

    /// Forces the next `.fast` snapshot to refresh mode, target, and Ftst while
    /// retaining static fan metadata such as FNum and min/max RPM.
    public func invalidateControlStateCache() {
        cacheLock.withLock {
            cachedControlState = nil
        }
    }

    private func readGPUTemperatureUnlocked() -> GPUTemperatureSnapshot? {
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
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let staticFans = try staticFanData()
        return try readCompleteFans(staticFans: staticFans)
    }

    private func readFanState(
        scope: SensorSnapshotScope
    ) throws -> (fans: [FanSnapshot], fanTestMode: Int?) {
        let staticFans = try staticFanData()

        if scope == .fast,
           let cachedControlState,
           cachedControlState.fans.count == staticFans.count {
            let fans = try zip(staticFans, cachedControlState.fans).map { staticFan, control in
                FanSnapshot(
                    index: staticFan.index,
                    actualRPM: try readNumeric("F\(staticFan.index)Ac"),
                    targetRPM: control.targetRPM,
                    minimumRPM: staticFan.minimumRPM,
                    maximumRPM: staticFan.maximumRPM,
                    mode: control.mode
                )
            }
            return (fans, cachedControlState.fanTestMode)
        }

        let fans = try readCompleteFans(staticFans: staticFans)
        let fanTestMode = try readOptionalInteger("Ftst")
        cachedControlState = ControlState(
            fans: fans.map {
                FanControlState(targetRPM: $0.targetRPM, mode: $0.mode)
            },
            fanTestMode: fanTestMode
        )
        return (fans, fanTestMode)
    }

    private func staticFanData() throws -> [StaticFanData] {
        if let cachedStaticFanData {
            return cachedStaticFanData
        }

        let rawCount = try readNumeric("FNum")
        guard rawCount >= 0,
              rawCount <= 10,
              rawCount.rounded(.towardZero) == rawCount else {
            throw FanControlError.invalidFanCount(rawCount)
        }

        let loaded = try (0..<Int(rawCount)).map { index in
            StaticFanData(
                index: index,
                minimumRPM: try readOptionalNumeric("F\(index)Mn"),
                maximumRPM: try readOptionalNumeric("F\(index)Mx")
            )
        }
        cachedStaticFanData = loaded
        return loaded
    }

    private func readCompleteFans(staticFans: [StaticFanData]) throws -> [FanSnapshot] {
        try staticFans.map { staticFan in
            FanSnapshot(
                index: staticFan.index,
                actualRPM: try readNumeric("F\(staticFan.index)Ac"),
                targetRPM: try readOptionalNumeric("F\(staticFan.index)Tg"),
                minimumRPM: staticFan.minimumRPM,
                maximumRPM: staticFan.maximumRPM,
                mode: try readFanModeStrict(index: staticFan.index)
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
