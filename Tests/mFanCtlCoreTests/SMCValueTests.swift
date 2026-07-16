@testable import FanCtlCore
import XCTest

final class SMCValueTests: XCTestCase {
    func testFPE2Decoding() {
        let value = SMCValue(key: "F0Ac", dataType: "fpe2", dataSize: 2, bytes: [0x2a, 0x80])
        XCTAssertEqual(value.numericValue, 2720)
    }

    func testSP78Decoding() {
        let value = SMCValue(key: "Tp01", dataType: "sp78", dataSize: 2, bytes: [42, 128])
        XCTAssertEqual(value.numericValue, 42.5)
    }

    func testSignedFixedPointDecodesNegativeValues() {
        let value = SMCValue(key: "Tp01", dataType: "sp78", dataSize: 2, bytes: [0xfe, 0x80])
        XCTAssertEqual(value.numericValue, -1.5)
    }

    func testNumericValueRejectsTruncatedPayload() {
        let value = SMCValue(key: "F0Ac", dataType: "ui16", dataSize: 2, bytes: [0x12])
        XCTAssertNil(value.numericValue)
    }

    func testNumericValueRejectsMismatchedTypeSize() {
        let value = SMCValue(key: "F0Md", dataType: "ui8 ", dataSize: 2, bytes: [0, 0])
        XCTAssertNil(value.numericValue)
    }

    func testNumericValueRejectsTrailingPayloadBytes() {
        let value = SMCValue(key: "F0Md", dataType: "ui8 ", dataSize: 1, bytes: [0, 0])
        XCTAssertNil(value.numericValue)
    }

    func testNumericValueRejectsFirmwareErrorResult() {
        let value = SMCValue(
            key: "F0Md",
            dataType: "ui8 ",
            dataSize: 1,
            resultCode: 0x84,
            bytes: [0]
        )
        XCTAssertNil(value.numericValue)
    }

    func testFloatDecoding() {
        let bitPattern = Float(42.5).bitPattern.littleEndian
        let bytes = [
            UInt8(bitPattern & 0xff),
            UInt8((bitPattern >> 8) & 0xff),
            UInt8((bitPattern >> 16) & 0xff),
            UInt8((bitPattern >> 24) & 0xff)
        ]
        let value = SMCValue(key: "Tg00", dataType: "flt ", dataSize: 4, bytes: bytes)
        XCTAssertEqual(value.numericValue ?? 0, 42.5, accuracy: 0.001)
    }

    func testGPUKeysForM4Pro() {
        XCTAssertEqual(
            gpuClusterTemperatureKeys(modelIdentifier: "Mac16,8", family: .m4ProOrMax),
            ["Tg05", "Tg0S", "Tg0Y", "Tg0k", "Tg0z"]
        )
    }

    func testCanonicalModelAlias() {
        XCTAssertEqual(canonicalMacModelIdentifier("Mac16,8"), "MacBookPro21,2")
    }

    func testM3AirProfileFromAlias() {
        XCTAssertEqual(
            gpuClusterTemperatureKeys(modelIdentifier: "Mac15,2", family: .m3),
            ["Tg0D", "Tg0P", "Tg0X", "Tg0b", "Tg0j", "Tg0v"]
        )
    }

    func testPlusModelPattern() {
        XCTAssertEqual(
            gpuClusterTemperatureKeys(modelIdentifier: "Mac17,7", family: .m5),
            ["Tg08", "Tg12", "Tg1x", "Tg29"]
        )
    }

    func testZeroIsValidNumericValue() {
        let value = SMCValue(key: "F0Md", dataType: "ui8 ", dataSize: 1, bytes: [0])
        XCTAssertEqual(value.numericValue, 0)
    }

    func testSMCParameterStructMatchesAppleSMCABI() {
        XCTAssertEqual(SMCConnection.parameterStructSize, 80)
        XCTAssertEqual(SMCConnection.parameterResultOffset, 40)
        XCTAssertEqual(SMCConnection.parameterStatusOffset, 41)
        XCTAssertEqual(SMCConnection.parameterCommandOffset, 42)
        XCTAssertEqual(SMCConnection.parameterData32Offset, 44)
        XCTAssertEqual(SMCConnection.parameterPayloadOffset, 48)
    }

    func testManualModeRollsBackToAutomaticWhenRPMWriteFails() {
        let smc = FakeSMCClient(values: [
            "FNum": ui8("FNum", 1),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "ui16", dataSize: 2, bytes: [0x07, 0xd0]),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "ui16", dataSize: 2, bytes: [0x1f, 0x40]),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", dataSize: 1, bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", dataSize: 2, bytes: [0, 0])
        ])
        smc.rejectedWriteKeys = ["F0Tg"]

        XCTAssertThrowsError(try FanController(smc: smc).setManual(fanIndex: 0, rpm: 5000))
        XCTAssertTrue(smc.writes.contains { $0.key == "F0Md" && $0.bytes == [1] })
        XCTAssertTrue(smc.writes.contains { $0.key == "F0Md" && $0.bytes == [0] })
    }

    func testManualRPMIsClampedAndVerified() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: nil))

        let result = try FanController(smc: smc).setManual(fanIndex: 0, rpm: 10_000)

        XCTAssertEqual(result.appliedRPM, 8_000)
        XCTAssertTrue(smc.writes.contains { $0.key == "F0Tg" && $0.bytes == [0x7d, 0x00] })
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testFPE2RPMEncodingPreservesQuarterRPMValues() throws {
        var values = standardFanValues(mode: 0, forceTest: nil)
        values["F0Mx"] = SMCValue(
            key: "F0Mx",
            dataType: "fpe2",
            dataSize: 2,
            bytes: [0x7d, 0x02]
        )
        let smc = FakeSMCClient(values: values)

        let result = try FanController(smc: smc).setManual(fanIndex: 0, rpm: 10_000)

        XCTAssertEqual(result.appliedRPM, 8_000.5)
        XCTAssertTrue(smc.writes.contains { $0.key == "F0Tg" && $0.bytes == [0x7d, 0x02] })
    }

    func testInvalidRPMIsRejectedBeforeAnySMCWrite() {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: nil))

        XCTAssertThrowsError(try FanController(smc: smc).setManual(fanIndex: 0, rpm: .nan))
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testModeZeroWithForceTestEnabledIsNotFullyAutomatic() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1))
        let controller = FanController(smc: smc)

        XCTAssertFalse(try controller.automaticControlStatus().isFullyAutomatic)

        try controller.setAutomatic(fanIndex: 0)

        XCTAssertTrue(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [0] })
        XCTAssertTrue(try controller.automaticControlStatus().isFullyAutomatic)
    }

    func testForceTestFallbackVerifiesManualMode() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        let controller = FanController(smc: smc, timing: .immediate)

        let result = try controller.setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertTrue(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [1] })
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testForceTestFallbackPollsUntilManualModeIsReady() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestRejectedAttempts = 3
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 4,
            manualModeWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            5
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testForceTestPollingExhaustionRestoresAutomaticState() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestRejectedAttempts = 3
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing).setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertEqual(try smc.read("F0Md").numericValue, 0)
        XCTAssertEqual(try smc.read("Ftst").numericValue, 0)
    }

    func testFailedForceTestManualOperationClearsForceTestDuringRollback() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.rejectedWriteKeys = ["F0Tg"]
        let controller = FanController(smc: smc, timing: .immediate)

        XCTAssertThrowsError(try controller.setManual(fanIndex: 0, rpm: 5_000))

        XCTAssertEqual(try smc.read("F0Md").numericValue, 0)
        XCTAssertEqual(try smc.read("Ftst").numericValue, 0)
    }

    func testSystemManagedModeIsAutomaticWhenForceTestIsClear() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 3, forceTest: 0))

        let status = try FanController(smc: smc).automaticControlStatus()

        XCTAssertEqual(status.fans, [FanModeState(fanIndex: 0, mode: .systemManaged)])
        XCTAssertTrue(status.isFullyAutomatic)
    }

    func testUnknownModeIsNotReportedAsAutomatic() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 2, forceTest: 0))

        let status = try FanController(smc: smc).automaticControlStatus()

        XCTAssertEqual(status.fans, [FanModeState(fanIndex: 0, mode: .unknown(2))])
        XCTAssertFalse(status.isFullyAutomatic)
    }

    func testStrictFanReadDoesNotSilentlyOmitUnreadableFan() {
        var values = standardFanValues(mode: 0, forceTest: nil)
        values["FNum"] = ui8("FNum", 2)
        values["F1Md"] = ui8("F1Md", 0)
        let smc = FakeSMCClient(values: values)
        let reader = SensorReader(smc: smc)

        XCTAssertThrowsError(try reader.readFansStrict())
        XCTAssertNotNil(reader.snapshot().fanReadError)
    }

    func testStrictSnapshotIncludesForceTestMode() throws {
        let reader = SensorReader(smc: FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1)))

        XCTAssertEqual(try reader.snapshotStrict().fanTestMode, 1)
    }

    func testStrictSnapshotRejectsMalformedForceTestMode() {
        var values = standardFanValues(mode: 0, forceTest: 0)
        values["Ftst"] = SMCValue(key: "Ftst", dataType: "ui8 ", dataSize: 1, bytes: [])
        let reader = SensorReader(smc: FakeSMCClient(values: values))

        XCTAssertThrowsError(try reader.snapshotStrict())
        XCTAssertNotNil(reader.snapshot().fanReadError)
    }
}

private func ui8(_ key: String, _ value: UInt8) -> SMCValue {
    SMCValue(key: key, dataType: "ui8 ", dataSize: 1, bytes: [value])
}

private func standardFanValues(mode: UInt8, forceTest: UInt8?) -> [String: SMCValue] {
    var values: [String: SMCValue] = [
        "FNum": ui8("FNum", 1),
        "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", dataSize: 2, bytes: [0x1f, 0x40]),
        "F0Mn": SMCValue(key: "F0Mn", dataType: "ui16", dataSize: 2, bytes: [0x07, 0xd0]),
        "F0Mx": SMCValue(key: "F0Mx", dataType: "ui16", dataSize: 2, bytes: [0x1f, 0x40]),
        "F0Md": ui8("F0Md", mode),
        "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", dataSize: 2, bytes: [0x1f, 0x40])
    ]
    if let forceTest {
        values["Ftst"] = ui8("Ftst", forceTest)
    }
    return values
}

private final class FakeSMCClient: SMCClient, @unchecked Sendable {
    enum Error: Swift.Error {
        case rejectedWrite(String)
    }

    var rejectedWriteKeys = Set<String>()
    var manualModeRequiresForceTest = false
    var manualModePostForceTestRejectedAttempts = 0
    private(set) var writes: [(key: String, bytes: [UInt8])] = []
    private var values: [String: SMCValue]

    init(values: [String: SMCValue]) {
        self.values = values
    }

    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else {
            throw SMCError.firmwareRejected(key: key, 0x84)
        }
        return value
    }

    func numericValue(for key: String) -> Double? {
        try? read(key).numericValue
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        writes.append((key, bytes))
        if rejectedWriteKeys.contains(key) {
            throw Error.rejectedWrite(key)
        }

        let existing = try read(key)
        guard bytes.count == Int(existing.dataSize) else {
            throw SMCError.invalidDataSize(
                key: key,
                expected: "exactly \(existing.dataSize) bytes",
                actual: bytes.count
            )
        }
        if manualModeRequiresForceTest,
           key.hasSuffix("Md") || key.hasSuffix("md"),
           bytes == [1],
           values["Ftst"]?.numericValue != 1 {
            return
        }
        if (key.hasSuffix("Md") || key.hasSuffix("md")),
           bytes == [1],
           values["Ftst"]?.numericValue == 1,
           manualModePostForceTestRejectedAttempts > 0 {
            manualModePostForceTestRejectedAttempts -= 1
            return
        }
        values[key] = SMCValue(
            key: key,
            dataType: existing.dataType,
            dataSize: existing.dataSize,
            bytes: bytes
        )
    }
}
