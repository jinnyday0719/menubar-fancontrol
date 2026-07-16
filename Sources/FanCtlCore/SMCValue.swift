import Foundation

public struct SMCValue: Sendable {
    public let key: String
    public let dataType: String
    public let dataSize: UInt32
    public let resultCode: UInt8
    public let bytes: [UInt8]

    public init(key: String, dataType: String, dataSize: UInt32, resultCode: UInt8 = 0, bytes: [UInt8]) {
        self.key = key
        self.dataType = dataType
        self.dataSize = dataSize
        self.resultCode = resultCode
        self.bytes = bytes
    }

    public var numericValue: Double? {
        guard resultCode == 0,
              dataSize > 0,
              Int(dataSize) == bytes.count else {
            return nil
        }

        switch dataType {
        case "ui8 ":
            guard dataSize == 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard dataSize == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard dataSize == 4 else { return nil }
            return Double(
                UInt32(bytes[0]) << 24 |
                UInt32(bytes[1]) << 16 |
                UInt32(bytes[2]) << 8 |
                UInt32(bytes[3])
            )
        case "sp1e":
            return fixedPoint(divisor: 16_384)
        case "sp3c":
            return fixedPoint(divisor: 4_096)
        case "sp4b":
            return fixedPoint(divisor: 2_048)
        case "sp5a":
            return fixedPoint(divisor: 1_024)
        case "sp69":
            return fixedPoint(divisor: 512)
        case "sp78":
            return fixedPoint(divisor: 256)
        case "sp87":
            return fixedPoint(divisor: 128)
        case "sp96":
            return fixedPoint(divisor: 64)
        case "spa5":
            return fixedPoint(divisor: 32)
        case "spb4":
            return fixedPoint(divisor: 16)
        case "spf0":
            return fixedPoint(divisor: 1)
        case "flt ":
            guard dataSize == 4 else { return nil }
            let bitPattern = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Float(bitPattern: bitPattern)
            guard value.isFinite else { return nil }
            return Double(value)
        case "fpe2":
            guard dataSize == 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4
        default:
            return nil
        }
    }

    private func fixedPoint(divisor: Double) -> Double? {
        guard dataSize == 2 else { return nil }
        let bitPattern = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let raw = Int16(bitPattern: bitPattern)
        return Double(raw) / divisor
    }
}
