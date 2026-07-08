import FanCtlCore
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

    func testManualModeRollsBackToAutomaticWhenRPMWriteFails() {
        let smc = FakeSMCClient(values: [
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
}

private final class FakeSMCClient: SMCClient, @unchecked Sendable {
    enum Error: Swift.Error {
        case rejectedWrite(String)
    }

    var rejectedWriteKeys = Set<String>()
    private(set) var writes: [(key: String, bytes: [UInt8])] = []
    private var values: [String: SMCValue]

    init(values: [String: SMCValue]) {
        self.values = values
    }

    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else {
            throw SMCError.invalidKey(key)
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

        let existing = try? read(key)
        values[key] = SMCValue(
            key: key,
            dataType: existing?.dataType ?? "ui8 ",
            dataSize: existing?.dataSize ?? UInt32(bytes.count),
            bytes: bytes
        )
    }
}
