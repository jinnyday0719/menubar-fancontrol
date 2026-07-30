@testable import FanCtlCore
import Foundation
import XCTest

final class SensorCachingTests: XCTestCase {
    func testSamplingCadenceUsesFastSnapshotsUntilCompleteInterval() {
        var cadence = SensorSamplingCadence(completeSnapshotInterval: 20)

        XCTAssertEqual(cadence.scope(at: 0), .complete)
        cadence.recordSuccessfulSnapshot(scope: .complete, at: 0)
        XCTAssertEqual(cadence.scope(at: 2), .fast)
        XCTAssertEqual(cadence.scope(at: 18), .fast)
        XCTAssertEqual(cadence.scope(at: 20), .complete)
    }

    func testSamplingCadenceInvalidationAndFailedCompleteStayComplete() {
        var cadence = SensorSamplingCadence(completeSnapshotInterval: 20)

        XCTAssertEqual(cadence.scope(at: 0), .complete)
        // No success is recorded, matching a failed complete read.
        XCTAssertEqual(cadence.scope(at: 2), .complete)

        cadence.recordSuccessfulSnapshot(scope: .complete, at: 2)
        XCTAssertEqual(cadence.scope(at: 4), .fast)
        cadence.invalidateControlState()
        XCTAssertEqual(cadence.scope(at: 5), .complete)
    }

    func testSMCKeyMetadataCacheLoadsEachKeyOnlyOnce() throws {
        let cache = SMCKeyMetadataCache()
        let expected = SMCKeyMetadata(
            dataSize: 2,
            dataTypeCode: 0x6670_6532,
            dataType: "fpe2"
        )
        var loadCount = 0

        for _ in 0..<3 {
            let value = try cache.metadata(for: 0x4630_4163) {
                loadCount += 1
                return expected
            }
            XCTAssertEqual(value, expected)
        }

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(cache.count, 1)
    }

    func testSMCKeyMetadataCacheDoesNotCacheFailures() throws {
        enum ExpectedError: Error {
            case unavailable
        }

        let cache = SMCKeyMetadataCache()
        XCTAssertThrowsError(
            try cache.metadata(for: 0x4630_4163) {
                throw ExpectedError.unavailable
            }
        )

        let loaded = try cache.metadata(for: 0x4630_4163) {
            SMCKeyMetadata(
                dataSize: 2,
                dataTypeCode: 0x6670_6532,
                dataType: "fpe2"
            )
        }
        XCTAssertEqual(loaded.dataType, "fpe2")
        XCTAssertEqual(cache.count, 1)
    }

    func testSMCKeyMetadataCacheRemembersUnsupportedKey() {
        let cache = SMCKeyMetadataCache()
        var loadCount = 0

        for _ in 0..<2 {
            XCTAssertThrowsError(
                try cache.metadata(for: 0x5467_3034) {
                    loadCount += 1
                    throw SMCError.firmwareRejected(key: "Tg04", 0x84)
                }
            )
        }

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(cache.count, 1)
    }

    func testRecoveryDispositionRetainsConnectionForPermanentDataErrors() {
        XCTAssertEqual(
            smcConnectionRecoveryDisposition(
                for: SMCError.invalidDataSize(key: "F0Ac", expected: "2", actual: 1)
            ),
            .retainConnection
        )
        XCTAssertEqual(
            smcConnectionRecoveryDisposition(for: SMCError.invalidNumericValue(key: "FNum")),
            .retainConnection
        )
        XCTAssertEqual(
            smcConnectionRecoveryDisposition(for: FanControlError.invalidFanCount(10.5)),
            .retainConnection
        )
    }

    func testRecoveryDispositionReopensConnectionForTransportErrors() {
        XCTAssertEqual(
            smcConnectionRecoveryDisposition(
                for: SMCError.readFailed(key: "F0Ac", kIOReturnNotOpen)
            ),
            .reopenConnection
        )
    }

    func testCompleteSnapshotsCacheStaticFanDataButRefreshControlState() throws {
        let smc = CountingSMCClient(values: standardSensorValues())
        let reader = SensorReader(smc: smc, hardware: testHardware)

        _ = try reader.snapshotStrict()
        _ = try reader.snapshotStrict()

        XCTAssertEqual(smc.readCount(for: "FNum"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Mn"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Mx"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Ac"), 2)
        XCTAssertEqual(smc.readCount(for: "F0Tg"), 2)
        XCTAssertEqual(smc.readCount(for: "F0Md"), 2)
        XCTAssertEqual(smc.readCount(for: "Ftst"), 2)
    }

    func testFastSnapshotReadsOnlyTemperatureAndActualRPMAfterWarmup() throws {
        let smc = CountingSMCClient(values: standardSensorValues())
        let reader = SensorReader(smc: smc, hardware: testHardware)

        _ = try reader.snapshotStrict(scope: .fast)
        let countsAfterWarmup = smc.readCounts
        let second = try reader.snapshotStrict(scope: .fast)

        XCTAssertEqual(second.fans.first?.targetRPM, 4_000)
        XCTAssertEqual(second.fans.first?.mode, 1)
        XCTAssertEqual(second.fanTestMode, 1)
        XCTAssertEqual(smc.readCount(for: "F0Ac"), countsAfterWarmup["F0Ac", default: 0] + 1)
        XCTAssertEqual(smc.readCount(for: "Tg04"), countsAfterWarmup["Tg04", default: 0] + 1)
        XCTAssertEqual(smc.readCount(for: "Tg12"), countsAfterWarmup["Tg12", default: 0] + 1)
        XCTAssertEqual(smc.readCount(for: "FNum"), countsAfterWarmup["FNum"])
        XCTAssertEqual(smc.readCount(for: "F0Mn"), countsAfterWarmup["F0Mn"])
        XCTAssertEqual(smc.readCount(for: "F0Mx"), countsAfterWarmup["F0Mx"])
        XCTAssertEqual(smc.readCount(for: "F0Tg"), countsAfterWarmup["F0Tg"])
        XCTAssertEqual(smc.readCount(for: "F0Md"), countsAfterWarmup["F0Md"])
        XCTAssertEqual(smc.readCount(for: "Ftst"), countsAfterWarmup["Ftst"])
    }

    func testInvalidatingControlCacheMakesNextFastSnapshotComplete() throws {
        let smc = CountingSMCClient(values: standardSensorValues())
        let reader = SensorReader(smc: smc, hardware: testHardware)
        _ = try reader.snapshotStrict(scope: .fast)

        smc.setValue(fpe2("F0Tg", 3_200), for: "F0Tg")
        smc.setValue(ui8("F0Md", 0), for: "F0Md")
        smc.setValue(ui8("Ftst", 0), for: "Ftst")
        reader.invalidateControlStateCache()

        let refreshed = try reader.snapshotStrict(scope: .fast)

        XCTAssertEqual(refreshed.fans.first?.targetRPM, 3_200)
        XCTAssertEqual(refreshed.fans.first?.mode, 0)
        XCTAssertEqual(refreshed.fanTestMode, 0)
        XCTAssertEqual(smc.readCount(for: "FNum"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Mn"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Mx"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Tg"), 2)
        XCTAssertEqual(smc.readCount(for: "F0Md"), 2)
        XCTAssertEqual(smc.readCount(for: "Ftst"), 2)
    }

    func testFailedCompleteSnapshotDoesNotPublishPartialControlCache() throws {
        let smc = CountingSMCClient(values: twoFanSensorValues())
        let reader = SensorReader(smc: smc, hardware: testHardware)
        smc.failNextRead(for: "Ftst")

        XCTAssertThrowsError(try reader.snapshotStrict(scope: .complete))

        smc.setValue(fpe2("F0Tg", 3_200), for: "F0Tg")
        smc.setValue(fpe2("F1Tg", 3_400), for: "F1Tg")
        smc.setValue(ui8("F0Md", 0), for: "F0Md")
        smc.setValue(ui8("F1Md", 0), for: "F1Md")
        smc.setValue(ui8("Ftst", 0), for: "Ftst")

        let recovered = try reader.snapshotStrict(scope: .fast)

        XCTAssertEqual(recovered.fans.map(\.targetRPM), [3_200, 3_400])
        XCTAssertEqual(recovered.fans.map(\.mode), [0, 0])
        XCTAssertEqual(recovered.fanTestMode, 0)
        XCTAssertEqual(smc.readCount(for: "FNum"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Mn"), 1)
        XCTAssertEqual(smc.readCount(for: "F1Mn"), 1)
        XCTAssertEqual(smc.readCount(for: "F0Tg"), 2)
        XCTAssertEqual(smc.readCount(for: "F1Tg"), 2)
        XCTAssertEqual(smc.readCount(for: "Ftst"), 2)
    }
}

private let testHardware = HardwareProfile(
    modelIdentifier: "Mac16,1",
    chipName: "Apple M4",
    family: .m4
)

private func standardSensorValues() -> [String: SMCValue] {
    [
        "Tg04": sp78("Tg04", 45),
        "Tg12": sp78("Tg12", 47),
        "FNum": ui8("FNum", 1),
        "F0Ac": fpe2("F0Ac", 3_000),
        "F0Tg": fpe2("F0Tg", 4_000),
        "F0Mn": fpe2("F0Mn", 2_000),
        "F0Mx": fpe2("F0Mx", 5_000),
        "F0Md": ui8("F0Md", 1),
        "Ftst": ui8("Ftst", 1)
    ]
}

private func twoFanSensorValues() -> [String: SMCValue] {
    var values = standardSensorValues()
    values["FNum"] = ui8("FNum", 2)
    values["F1Ac"] = fpe2("F1Ac", 3_100)
    values["F1Tg"] = fpe2("F1Tg", 4_100)
    values["F1Mn"] = fpe2("F1Mn", 2_100)
    values["F1Mx"] = fpe2("F1Mx", 5_100)
    values["F1Md"] = ui8("F1Md", 1)
    return values
}

private func ui8(_ key: String, _ value: UInt8) -> SMCValue {
    SMCValue(key: key, dataType: "ui8 ", dataSize: 1, bytes: [value])
}

private func fpe2(_ key: String, _ rpm: Double) -> SMCValue {
    let raw = UInt16((rpm * 4).rounded())
    return SMCValue(
        key: key,
        dataType: "fpe2",
        dataSize: 2,
        bytes: [UInt8(raw >> 8), UInt8(raw & 0xff)]
    )
}

private func sp78(_ key: String, _ celsius: Double) -> SMCValue {
    let raw = UInt16(bitPattern: Int16((celsius * 256).rounded()))
    return SMCValue(
        key: key,
        dataType: "sp78",
        dataSize: 2,
        bytes: [UInt8(raw >> 8), UInt8(raw & 0xff)]
    )
}

private final class CountingSMCClient: SMCClient, @unchecked Sendable {
    private enum TestError: Error {
        case oneShotFailure(String)
    }

    private let lock = NSLock()
    private var values: [String: SMCValue]
    private var counts: [String: Int] = [:]
    private var oneShotReadFailures: Set<String> = []

    init(values: [String: SMCValue]) {
        self.values = values
    }

    var readCounts: [String: Int] {
        lock.withLock { counts }
    }

    func readCount(for key: String) -> Int {
        lock.withLock { counts[key, default: 0] }
    }

    func setValue(_ value: SMCValue, for key: String) {
        lock.withLock {
            values[key] = value
        }
    }

    func failNextRead(for key: String) {
        _ = lock.withLock {
            oneShotReadFailures.insert(key)
        }
    }

    func read(_ key: String) throws -> SMCValue {
        try lock.withLock {
            counts[key, default: 0] += 1
            if oneShotReadFailures.remove(key) != nil {
                throw TestError.oneShotFailure(key)
            }
            guard let value = values[key] else {
                throw SMCError.firmwareRejected(key: key, 0x84)
            }
            return value
        }
    }

    func numericValue(for key: String) -> Double? {
        try? read(key).numericValue
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        try lock.withLock {
            guard let existing = values[key] else {
                throw SMCError.firmwareRejected(key: key, 0x84)
            }
            guard bytes.count == Int(existing.dataSize) else {
                throw SMCError.invalidDataSize(
                    key: key,
                    expected: "exactly \(existing.dataSize) bytes",
                    actual: bytes.count
                )
            }
            values[key] = SMCValue(
                key: key,
                dataType: existing.dataType,
                dataSize: existing.dataSize,
                bytes: bytes
            )
        }
    }
}
