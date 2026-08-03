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

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate).setManual(fanIndex: 0, rpm: 5000)
        )
        XCTAssertTrue(smc.writes.contains { $0.key == "F0Md" && $0.bytes == [1] })
        XCTAssertTrue(smc.writes.contains { $0.key == "F0Md" && $0.bytes == [0] })
    }

    func testDelayedTargetReadbackIsRetriedWithoutWaitingForActualRPM() throws {
        var values = standardFanValues(mode: 3, forceTest: 0)
        values["F0Ac"] = fpe2("F0Ac", 2_317)
        values["F0Mn"] = fpe2("F0Mn", 2_317)
        values["F0Mx"] = fpe2("F0Mx", 5_072)
        values["F0Tg"] = fpe2("F0Tg", 2_317)
        let smc = FakeSMCClient(values: values)
        smc.manualModeRequiresForceTest = true
        smc.staleReadCountForNextWrite["F0Tg"] = 4
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            targetWriteAttempts: 5,
            targetWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(
            fanIndex: 0,
            rpm: 5_072
        )

        XCTAssertEqual(result.appliedRPM, 5_072)
        XCTAssertEqual(try smc.read("F0Ac").numericValue, 2_317)
        XCTAssertEqual(try smc.read("F0Tg").numericValue, 5_072)
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
        XCTAssertEqual(try smc.read("Ftst").numericValue, 1)
        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 1)
        XCTAssertFalse(smc.writes.contains { $0.key == "F0Md" && $0.bytes == [0] })
    }

    func testProductionTargetRetryBudgetSurvivesMoreThanEightStaleReadbacks() throws {
        var values = standardFanValues(mode: 0, forceTest: 0)
        values["F0Tg"] = fpe2("F0Tg", 2_317)
        let smc = FakeSMCClient(values: values)
        smc.staleReadCountForNextWrite["F0Tg"] = 16
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            targetWriteAttempts: FanControlTiming.production.targetWriteAttempts,
            targetWriteDelay: 0,
            maximumRetryDuration: 1,
            maximumRetryDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(
            fanIndex: 0,
            rpm: 5_000
        )

        XCTAssertEqual(result.appliedRPM, 5_000)
        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 2)
    }

    func testAcknowledgedButIgnoredTargetWriteIsReassertedSparingly() throws {
        var values = standardFanValues(mode: 0, forceTest: 0)
        values["F0Tg"] = fpe2("F0Tg", 2_317)
        let smc = FakeSMCClient(values: values)
        smc.ignoreWrites(key: "F0Tg", bytes: [0x4e, 0x20], attempts: 1)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            targetWriteAttempts: 8,
            targetWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(
            fanIndex: 0,
            rpm: 5_000
        )

        XCTAssertEqual(result.appliedRPM, 5_000)
        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 2)
    }

    func testTargetRetryExhaustionRestoresAutomaticControl() throws {
        var values = standardFanValues(mode: 0, forceTest: 0)
        values["F0Tg"] = fpe2("F0Tg", 2_317)
        let smc = FakeSMCClient(values: values)
        smc.ignoreWrites(key: "F0Tg", bytes: [0x4e, 0x20], attempts: 10)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            targetWriteAttempts: 3,
            targetWriteDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing).setManual(fanIndex: 0, rpm: 5_000)
        ) { error in
            guard case FanControlError.targetVerificationFailed(
                fanIndex: 0,
                expected: 5_000,
                actual: 2_317
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 1)
        XCTAssertEqual(try smc.read("F0Md").numericValue, 0)
        XCTAssertEqual(try smc.read("Ftst").numericValue, 0)
    }

    func testAutomaticModeWriteRetriesUntilReadbackChanges() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 1, forceTest: nil))
        smc.ignoreWrites(key: "F0Md", bytes: [0], attempts: 2)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            automaticModeWriteAttempts: 8,
            automaticModeWriteDelay: 0
        )

        try FanController(smc: smc, timing: timing).setAutomatic(fanIndex: 0)

        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [0] }.count,
            3
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 0)
    }

    func testAutomaticModeWriteExhaustionIsNotReportedAsSuccess() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 1, forceTest: nil))
        smc.ignoreWrites(key: "F0Md", bytes: [0], attempts: 10)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            automaticModeWriteAttempts: 2,
            automaticModeWriteDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing).setAutomatic(fanIndex: 0)
        )
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [0] }.count,
            2
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testForceTestClearRetriesUntilReadbackChanges() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1))
        smc.ignoreWrites(key: "Ftst", bytes: [0], attempts: 2)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            forceTestClearAttempts: 8,
            forceTestClearDelay: 0
        )
        let controller = FanController(smc: smc, timing: timing)

        try controller.setAutomatic(fanIndex: 0)

        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [0] }.count,
            3
        )
        XCTAssertTrue(try controller.automaticControlStatus().isFullyAutomatic)
    }

    func testForceTestClearExhaustionIsNotReportedAsAutomatic() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1))
        smc.ignoreWrites(key: "Ftst", bytes: [0], attempts: 10)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            forceTestClearAttempts: 2,
            forceTestClearDelay: 0
        )
        let controller = FanController(smc: smc, timing: timing)

        XCTAssertThrowsError(try controller.setAutomatic(fanIndex: 0))
        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [0] }.count,
            2
        )
        XCTAssertFalse(try controller.automaticControlStatus().isFullyAutomatic)
    }

    func testManualTargetIsNotReportedAsAppliedWhenModeDrops() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: nil))
        smc.forcedModeAfterNextTargetWrite = 0

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate).setManual(fanIndex: 0, rpm: 5_000)
        ) { error in
            guard case FanControlError.modeVerificationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 1)
        XCTAssertEqual(try smc.read("F0Md").numericValue, 0)
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

    func testSubsequentFanReassertsForceTestAfterDirectRejection() throws {
        var values = standardTwoFanValues(mode: 0, forceTest: 0)
        values["F0Tg"] = fpe2("F0Tg", 2_317)
        values["F1Tg"] = fpe2("F1Tg", 2_317)
        let smc = FakeSMCClient(values: values)
        smc.manualModeRequiresForceTest = true
        // Fan 1 briefly reports the Apple Silicon hand-off rejection even
        // after fan 0 has completed. Refresh Ftst and retry that fan without
        // rolling fan 0 back to Automatic.
        smc.firmwareRejectedWriteAttempts["F1Md"] = (remaining: 1, code: 0x82)
        let controller = FanController(smc: smc, timing: .immediate)

        _ = try controller.setManual(fanIndex: 0, rpm: 5_000)
        _ = try controller.setManual(fanIndex: 1, rpm: 5_000)

        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [1] }.count,
            2
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
        XCTAssertEqual(try smc.read("F1Md").numericValue, 1)
    }

    func testForceTestFallbackReassertsStaleEnabledFlag() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1))
        smc.manualModeRequiresFreshForceTestWrite = true
        let controller = FanController(smc: smc, timing: .immediate)

        let result = try controller.setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [1] }.count,
            1
        )
        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [0] }.count,
            1
        )
        let forceTestWrites = smc.writes.filter { $0.key == "Ftst" }
        XCTAssertEqual(forceTestWrites.map(\.bytes), [[0], [1]])
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testForceTestClearWaitsPastTheOldShortVerificationWindow() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1))
        smc.staleReadCountForNextWrite["Ftst"] = 20
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            automaticModeWriteAttempts: 2,
            automaticModeWriteDelay: 0,
            forceTestClearAttempts: 30,
            forceTestClearDelay: 0,
            maximumRetryDuration: 1,
            maximumRetryDelay: 0
        )

        try FanController(smc: smc, timing: timing).setAutomatic()

        XCTAssertEqual(try smc.read("Ftst").numericValue, 0)
        XCTAssertTrue(try FanController(smc: smc).automaticControlStatus().isFullyAutomatic)
    }

    func testForceTestFallbackDoesNotTrustStaleFlagAfterRejectedReassert() {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 1))
        smc.manualModeRequiresFreshForceTestWrite = true
        smc.forceTestEnableFirmwareRejectedAttempts = 2
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 11,
            manualModeWriteDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing)
                .setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [1] }.count,
            2
        )
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            1
        )
        XCTAssertEqual(try? smc.read("F0Md").numericValue, 0)
        XCTAssertEqual(try? smc.read("Ftst").numericValue, 0)
    }

    func testForceTestFallbackReassertsOneIgnoredModeWriteAfterSettleWindow() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestRejectedAttempts = 1
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 11,
            manualModeWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            3
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testProductionManualModeRetryBudgetSurvivesMoreThanTwentyFourRejectedWrites() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestFirmwareRejectedAttempts = 25
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: FanControlTiming.production.manualModeWriteAttempts,
            manualModeWriteDelay: 0,
            maximumRetryDuration: 1,
            maximumRetryDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(
            fanIndex: 0,
            rpm: 5_000
        )

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            27
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testProductionManualModeDeadlineHasHardwareTimingMargin() {
        XCTAssertGreaterThanOrEqual(
            FanControlTiming.production.maximumRetryDuration,
            15
        )
        XCTAssertGreaterThanOrEqual(
            Double(FanControlTiming.production.manualModeWriteAttempts - 1) *
                FanControlTiming.production.manualModeWriteDelay,
            14.9
        )
    }

    func testForceTestFallbackRetriesTransientFirmwareRejection() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestFirmwareRejectedAttempts = 1
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing).setManual(
            fanIndex: 0,
            rpm: 5_000
        )

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            3
        )
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
        XCTAssertEqual(try smc.read("Ftst").numericValue, 1)
    }

    func testManualModeGetsFreshDeadlineAfterForceTestActivation() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestFirmwareRejectedAttempts = 1
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0.01,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            maximumRetryDuration: 0.005,
            maximumRetryDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
    }

    func testForceTestFallbackRetriesTransientVerificationRead() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.transientReadFailuresAfterNextWrite["Ftst"] = 1
        let timing = FanControlTiming(
            forceTestWriteAttempts: 4,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [1] }.count,
            1
        )
    }

    func testForceTestEnableReassertsAcknowledgedButIgnoredWrites() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.ignoreWrites(key: "Ftst", bytes: [1], attempts: 5)
        let timing = FanControlTiming(
            forceTestWriteAttempts: FanControlTiming.production.forceTestWriteAttempts,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            maximumRetryDuration: 1,
            maximumRetryDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "Ftst" && $0.bytes == [1] }.count,
            6
        )
    }

    func testAcknowledgedButIgnoredModeWriteIsReassertedImmediately() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.ignoreWrites(key: "F0Md", bytes: [1], attempts: 5)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 10,
            manualModeWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            7
        )
    }

    func testForceTestFallbackDoesNotRetryPermanentModeFirmwareError() {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.manualModeRequiresForceTest = true
        smc.manualModePostForceTestFirmwareRejectedAttempts = 10
        smc.manualModePostForceTestFirmwareRejectedCode = 0x86
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 10,
            manualModeWriteDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing)
                .setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            2
        )
    }

    func testDirectPermanentFirmwareErrorDoesNotEnableForceTest() {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.firmwareRejectedWriteAttempts["F0Md"] = (remaining: 1, code: 0x87)

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate)
                .setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertFalse(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [1] })
        XCTAssertEqual(try? smc.read("Ftst").numericValue, 0)
    }

    func testDirectTransientFirmwareErrorRetriesWithoutForceTest() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.firmwareRejectedWriteAttempts["F0Md"] = (remaining: 1, code: 0x80)

        let result = try FanController(smc: smc, timing: .immediate)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .directModeWrite)
        XCTAssertEqual(
            smc.writes.filter { $0.key == "F0Md" && $0.bytes == [1] }.count,
            2
        )
        XCTAssertFalse(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [1] })
    }

    func testSuccessfulDirectModeWriteWaitsForDelayedReadbackWithoutForceTest() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 0, forceTest: 0))
        smc.staleReadCountForNextWrite["F0Md"] = 3
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 10,
            manualModeWriteDelay: 0.001,
            maximumRetryDuration: 1,
            maximumRetryDelay: 0.001
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .directModeWrite)
        XCTAssertFalse(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [1] })
        XCTAssertEqual(try smc.read("F0Md").numericValue, 1)
        XCTAssertEqual(try smc.read("F0Tg").numericValue ?? .nan, 5_000, accuracy: 1)
    }

    func testTargetWriteRetriesTransientRejectionsWithoutPollOnlyDelay() throws {
        let smc = FakeSMCClient(values: standardFanValues(mode: 1, forceTest: 1))
        smc.firmwareRejectedWriteAttempts["F0Tg"] = (remaining: 3, code: 0x82)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            targetWriteAttempts: 6,
            targetWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.appliedRPM, 5_000, accuracy: 0.25)
        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 4)
    }

    func testTargetReassertAllowsDelayedReadbackAfterFirmwareError() throws {
        var values = standardFanValues(mode: 0, forceTest: 0)
        values["F0Tg"] = fpe2("F0Tg", 2_317)
        let smc = FakeSMCClient(values: values)
        smc.staleReadCountForNextWrite["F0Tg"] = 7
        smc.applyThenFirmwareRejectOnWriteNumber["F0Tg"] = (2, 0x87)
        let timing = FanControlTiming(
            forceTestWriteAttempts: 2,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 2,
            manualModeWriteDelay: 0,
            targetWriteAttempts: 8,
            targetWriteDelay: 0
        )

        let result = try FanController(smc: smc, timing: timing)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.appliedRPM, 5_000)
        XCTAssertEqual(smc.writes.filter { $0.key == "F0Tg" }.count, 2)
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

    func testEmptyFanSetIsNotReportedAsAutomatic() {
        let status = FanAutomaticControlStatus(
            fans: [],
            forceTestMode: 0
        )

        XCTAssertFalse(status.isFullyAutomatic)
    }

    func testSetAutomaticRejectsEmptyFanSet() {
        let smc = FakeSMCClient(values: [
            "FNum": ui8("FNum", 0),
            "Ftst": ui8("Ftst", 0)
        ])

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate).setAutomatic()
        ) { error in
            guard case FanControlError.invalidFanCount(let count) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(count, 0)
        }
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

private func fpe2(_ key: String, _ rpm: Double) -> SMCValue {
    let raw = UInt16((rpm * 4).rounded())
    return SMCValue(
        key: key,
        dataType: "fpe2",
        dataSize: 2,
        bytes: [UInt8(raw >> 8), UInt8(raw & 0xff)]
    )
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

private func standardTwoFanValues(mode: UInt8, forceTest: UInt8?) -> [String: SMCValue] {
    var values = standardFanValues(mode: mode, forceTest: forceTest)
    values["FNum"] = ui8("FNum", 2)
    values["F1Ac"] = fpe2("F1Ac", 2_317)
    values["F1Mn"] = fpe2("F1Mn", 2_000)
    values["F1Mx"] = fpe2("F1Mx", 8_000)
    values["F1Md"] = ui8("F1Md", mode)
    values["F1Tg"] = fpe2("F1Tg", 2_317)
    return values
}

private final class FakeSMCClient: SMCClient, @unchecked Sendable {
    private struct WriteSignature: Hashable {
        let key: String
        let bytes: [UInt8]
    }

    enum Error: Swift.Error {
        case rejectedWrite(String)
    }

    var rejectedWriteKeys = Set<String>()
    var manualModeRequiresForceTest = false
    var manualModeRequiresFreshForceTestWrite = false
    var manualModePostForceTestRejectedAttempts = 0
    var manualModePostForceTestFirmwareRejectedAttempts = 0
    var manualModePostForceTestFirmwareRejectedCode: UInt8 = 0x82
    var forceTestEnableFirmwareRejectedAttempts = 0
    var staleReadCountForNextWrite: [String: Int] = [:]
    var staleReadCountAfterEveryWrite: [String: Int] = [:]
    var transientReadFailuresAfterNextWrite: [String: Int] = [:]
    var firmwareRejectedWriteAttempts: [String: (remaining: Int, code: UInt8)] = [:]
    var forcedModeAfterNextTargetWrite: UInt8?
    var applyThenFirmwareRejectOnWriteNumber: [String: (number: Int, code: UInt8)] = [:]
    private(set) var writes: [(key: String, bytes: [UInt8])] = []
    private var values: [String: SMCValue]
    private var ignoredWriteAttempts: [WriteSignature: Int] = [:]
    private var pendingWrites: [String: (value: SMCValue, remainingStaleReads: Int)] = [:]
    private var transientReadFailures: [String: Int] = [:]
    private var didWriteForceTestEnable = false

    init(values: [String: SMCValue]) {
        self.values = values
    }

    func ignoreWrites(key: String, bytes: [UInt8], attempts: Int) {
        ignoredWriteAttempts[WriteSignature(key: key, bytes: bytes)] = attempts
    }

    func read(_ key: String) throws -> SMCValue {
        if let remaining = transientReadFailures[key], remaining > 0 {
            transientReadFailures[key] = remaining - 1
            throw SMCError.firmwareRejected(key: key, 0x80)
        }
        if var pending = pendingWrites[key] {
            if pending.remainingStaleReads > 0 {
                pending.remainingStaleReads -= 1
                pendingWrites[key] = pending
            } else {
                values[key] = pending.value
                pendingWrites.removeValue(forKey: key)
            }
        }
        guard let value = values[key] else {
            throw SMCError.firmwareRejected(key: key, 0x84)
        }
        return value
    }

    func numericValue(for key: String) -> Double? {
        try? read(key).numericValue
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        let existing = try read(key)
        try performWrite(key, bytes: bytes, existing: existing)
    }

    func write(_ key: String, bytes: [UInt8], expectedDataSize: UInt32) throws {
        guard let existing = values[key] else {
            throw SMCError.firmwareRejected(key: key, 0x84)
        }
        guard existing.dataSize == expectedDataSize else {
            throw SMCError.invalidDataSize(
                key: key,
                expected: "exactly \(existing.dataSize) bytes",
                actual: Int(expectedDataSize)
            )
        }
        try performWrite(key, bytes: bytes, existing: existing)
    }

    private func performWrite(
        _ key: String,
        bytes: [UInt8],
        existing: SMCValue
    ) throws {
        writes.append((key, bytes))
        if rejectedWriteKeys.contains(key) {
            throw Error.rejectedWrite(key)
        }

        guard bytes.count == Int(existing.dataSize) else {
            throw SMCError.invalidDataSize(
                key: key,
                expected: "exactly \(existing.dataSize) bytes",
                actual: bytes.count
            )
        }
        if var rejection = firmwareRejectedWriteAttempts[key], rejection.remaining > 0 {
            rejection.remaining -= 1
            firmwareRejectedWriteAttempts[key] = rejection
            throw SMCError.firmwareRejected(key: key, rejection.code)
        }
        if key == "Ftst", bytes == [1], forceTestEnableFirmwareRejectedAttempts > 0 {
            forceTestEnableFirmwareRejectedAttempts -= 1
            throw SMCError.firmwareRejected(key: key, 0x80)
        }
        if key == "Ftst", bytes == [1] {
            didWriteForceTestEnable = true
        }
        if manualModeRequiresFreshForceTestWrite,
           key.hasSuffix("Md") || key.hasSuffix("md"),
           bytes == [1],
           !didWriteForceTestEnable {
            return
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
           manualModePostForceTestFirmwareRejectedAttempts > 0 {
            manualModePostForceTestFirmwareRejectedAttempts -= 1
            throw SMCError.firmwareRejected(
                key: key,
                manualModePostForceTestFirmwareRejectedCode
            )
        }
        if (key.hasSuffix("Md") || key.hasSuffix("md")),
           bytes == [1],
           values["Ftst"]?.numericValue == 1,
           manualModePostForceTestRejectedAttempts > 0 {
            manualModePostForceTestRejectedAttempts -= 1
            return
        }
        let signature = WriteSignature(key: key, bytes: bytes)
        if let remaining = ignoredWriteAttempts[signature], remaining > 0 {
            ignoredWriteAttempts[signature] = remaining - 1
            return
        }

        let nextValue = SMCValue(
            key: key,
            dataType: existing.dataType,
            dataSize: existing.dataSize,
            bytes: bytes
        )
        if let staleReads = staleReadCountAfterEveryWrite[key], staleReads > 0 {
            pendingWrites[key] = (nextValue, staleReads)
        } else if var pending = pendingWrites[key] {
            pending.value = nextValue
            pendingWrites[key] = pending
        } else if let staleReads = staleReadCountForNextWrite.removeValue(forKey: key), staleReads > 0 {
            pendingWrites[key] = (nextValue, staleReads)
        } else {
            values[key] = nextValue
        }

        if key == "F0Tg", let forcedModeAfterNextTargetWrite {
            values["F0Md"] = ui8("F0Md", forcedModeAfterNextTargetWrite)
            self.forcedModeAfterNextTargetWrite = nil
        }
        if let rejection = applyThenFirmwareRejectOnWriteNumber[key],
           writes.filter({ $0.key == key }).count == rejection.number {
            throw SMCError.firmwareRejected(key: key, rejection.code)
        }
        if let failures = transientReadFailuresAfterNextWrite.removeValue(forKey: key) {
            transientReadFailures[key] = failures
        }
    }
}
