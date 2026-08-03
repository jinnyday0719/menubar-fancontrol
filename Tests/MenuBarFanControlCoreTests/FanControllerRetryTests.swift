@testable import FanCtlCore
import XCTest

final class FanControllerRetryTests: XCTestCase {
    func testPermanentModeWriteFailureIsNotRetried() {
        let smc = RetryTestSMCClient(values: oneFanValues(mode: 0, forceTest: 0))
        smc.permanentWriteFailureKey = "F0Md"

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate)
                .setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertEqual(smc.writeCount(for: "F0Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "Ftst"), 0)
    }

    func testPermanentTargetWriteFailureIsNotRetried() {
        let smc = RetryTestSMCClient(values: oneFanValues(mode: 0, forceTest: 0))
        smc.permanentWriteFailureKey = "F0Tg"

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate)
                .setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertEqual(smc.writeCount(for: "F0Tg"), 1)
    }

    func testOperationDeadlineStopsVerificationRetries() {
        let smc = RetryTestSMCClient(values: oneFanValues(mode: 0, forceTest: 0))
        smc.ignoredWriteKey = "F0Tg"
        let timing = FanControlTiming(
            forceTestWriteAttempts: 100,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 100,
            manualModeWriteDelay: 0,
            targetWriteAttempts: 100,
            targetWriteDelay: 0,
            maximumRetryDuration: 0,
            maximumRetryDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing)
                .setManual(fanIndex: 0, rpm: 5_000)
        )

        XCTAssertEqual(smc.writeCount(for: "F0Tg"), 1)
    }

    func testDirectFirmwareRejectionCanUseForceTestFallback() throws {
        let smc = RetryTestSMCClient(values: oneFanValues(mode: 0, forceTest: 0))
        smc.rejectManualModeUntilForceTest = true

        let result = try FanController(smc: smc, timing: .immediate)
            .setManual(fanIndex: 0, rpm: 5_000)

        XCTAssertEqual(result.strategy, .forceTestUnlock)
        XCTAssertEqual(smc.writeCount(for: "Ftst"), 1)
        XCTAssertEqual(smc.writeCount(for: "F0Md"), 2)
    }

    func testBatchAutomaticUsesSingleFanCountPreflight() throws {
        let values = twoFanValues(mode: 1, forceTest: 1)
        let smc = RetryTestSMCClient(values: values)

        try FanController(smc: smc, timing: .immediate).setAutomatic()

        XCTAssertEqual(smc.readCount(for: "FNum"), 1)
        XCTAssertEqual(smc.writeCount(for: "F0Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "F1Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "Ftst"), 1)
    }

    func testBatchAutomaticContinuesAfterPermanentFanFailure() {
        let smc = RetryTestSMCClient(values: twoFanValues(mode: 1, forceTest: 1))
        smc.permanentWriteFailureKey = "F0Md"

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate).setAutomatic()
        )

        XCTAssertEqual(smc.writeCount(for: "F0Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "F1Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "Ftst"), 0)
    }

    func testBatchAutomaticStillAttemptsLaterFansAfterDeadlineExpires() {
        let smc = RetryTestSMCClient(values: twoFanValues(mode: 1, forceTest: 0))
        smc.ignoredWriteKey = "F0Md"
        let timing = FanControlTiming(
            forceTestWriteAttempts: 100,
            forceTestWriteDelay: 0,
            forceTestActivationDelay: 0,
            manualModeWriteAttempts: 100,
            manualModeWriteDelay: 0,
            automaticModeWriteAttempts: 100,
            automaticModeWriteDelay: 0,
            maximumRetryDuration: 0,
            maximumRetryDelay: 0
        )

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: timing).setAutomatic()
        )

        XCTAssertEqual(smc.writeCount(for: "F0Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "F1Md"), 1)
        XCTAssertEqual(smc.numericValue(for: "F1Md"), 0)
    }

    func testBatchAutomaticSucceedsWhenReportedWriteErrorStillApplied() throws {
        let smc = RetryTestSMCClient(values: oneFanValues(mode: 1, forceTest: 1))
        smc.applyThenFailWriteKey = "F0Md"

        try FanController(smc: smc, timing: .immediate).setAutomatic()

        XCTAssertEqual(smc.writeCount(for: "F0Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "Ftst"), 1)
    }

    func testPostForceTestVerificationContinuesPastFirstFanIOFailure() {
        let smc = RetryTestSMCClient(values: twoFanValues(mode: 0, forceTest: 1))
        smc.modesAfterForceTestClear = ["F0Md": 1, "F1Md": 1]
        smc.permanentWriteFailureKey = "F0Md"

        XCTAssertThrowsError(
            try FanController(smc: smc, timing: .immediate).setAutomatic()
        )

        XCTAssertEqual(smc.writeCount(for: "Ftst"), 1)
        XCTAssertEqual(smc.writeCount(for: "F0Md"), 1)
        XCTAssertEqual(smc.writeCount(for: "F1Md"), 1)
    }
}

private enum RetryTestError: Error {
    case missingValue(String)
    case permanentWriteFailure(String)
}

private final class RetryTestSMCClient: SMCClient, @unchecked Sendable {
    private var values: [String: SMCValue]
    private var reads: [String: Int] = [:]
    private var writes: [String: Int] = [:]
    var permanentWriteFailureKey: String?
    var applyThenFailWriteKey: String?
    var ignoredWriteKey: String?
    var modesAfterForceTestClear: [String: UInt8] = [:]
    var rejectManualModeUntilForceTest = false

    init(values: [String: SMCValue]) {
        self.values = values
    }

    func read(_ key: String) throws -> SMCValue {
        reads[key, default: 0] += 1
        guard let value = values[key] else {
            throw RetryTestError.missingValue(key)
        }
        return value
    }

    func numericValue(for key: String) -> Double? {
        try? read(key).numericValue
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        writes[key, default: 0] += 1
        if permanentWriteFailureKey == key {
            throw RetryTestError.permanentWriteFailure(key)
        }
        if ignoredWriteKey == key {
            return
        }
        if rejectManualModeUntilForceTest,
           key.hasSuffix("Md") || key.hasSuffix("md"),
           bytes == [1],
           values["Ftst"]?.numericValue != 1 {
            throw SMCError.firmwareRejected(key: key, 0x85)
        }
        guard let previous = values[key] else {
            throw RetryTestError.missingValue(key)
        }
        values[key] = SMCValue(
            key: key,
            dataType: previous.dataType,
            dataSize: previous.dataSize,
            bytes: bytes
        )
        if key == "Ftst", bytes == [0] {
            for (modeKey, mode) in modesAfterForceTestClear {
                values[modeKey] = retryUI8(modeKey, mode)
            }
        }
        if applyThenFailWriteKey == key {
            throw RetryTestError.permanentWriteFailure(key)
        }
    }

    func readCount(for key: String) -> Int {
        reads[key, default: 0]
    }

    func writeCount(for key: String) -> Int {
        writes[key, default: 0]
    }
}

private func oneFanValues(mode: UInt8, forceTest: UInt8) -> [String: SMCValue] {
    [
        "FNum": retryUI8("FNum", 1),
        "F0Mn": retryUI16("F0Mn", 2_000),
        "F0Mx": retryUI16("F0Mx", 8_000),
        "F0Md": retryUI8("F0Md", mode),
        "F0Tg": retryFPE2("F0Tg", 2_000),
        "Ftst": retryUI8("Ftst", forceTest)
    ]
}

private func twoFanValues(mode: UInt8, forceTest: UInt8) -> [String: SMCValue] {
    var values = oneFanValues(mode: mode, forceTest: forceTest)
    values["FNum"] = retryUI8("FNum", 2)
    values["F1Md"] = retryUI8("F1Md", mode)
    return values
}

private func retryUI8(_ key: String, _ value: UInt8) -> SMCValue {
    SMCValue(key: key, dataType: "ui8 ", dataSize: 1, bytes: [value])
}

private func retryUI16(_ key: String, _ value: UInt16) -> SMCValue {
    SMCValue(
        key: key,
        dataType: "ui16",
        dataSize: 2,
        bytes: [UInt8(value >> 8), UInt8(value & 0xff)]
    )
}

private func retryFPE2(_ key: String, _ rpm: Double) -> SMCValue {
    let raw = UInt16((rpm * 4).rounded())
    return SMCValue(
        key: key,
        dataType: "fpe2",
        dataSize: 2,
        bytes: [UInt8(raw >> 8), UInt8(raw & 0xff)]
    )
}
