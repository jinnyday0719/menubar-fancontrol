import Foundation
import IOKit

public enum SMCError: Error, LocalizedError, Sendable {
    case serviceNotFound
    case openFailed(kern_return_t)
    case readFailed(key: String, kern_return_t)
    case writeFailed(key: String, kern_return_t)
    case firmwareRejected(key: String, UInt8)
    case invalidKey(String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            "AppleSMC service was not found."
        case .openFailed(let code):
            "Failed to open AppleSMC connection: \(SMCError.message(for: code))"
        case .readFailed(let key, let code):
            "Failed to read SMC key \(key): \(SMCError.message(for: code))"
        case .writeFailed(let key, let code):
            "Failed to write SMC key \(key): \(SMCError.message(for: code))"
        case .firmwareRejected(let key, let code):
            "SMC firmware rejected key \(key): 0x\(String(format: "%02x", code))"
        case .invalidKey(let key):
            "SMC key must be exactly 4 ASCII characters: \(key)"
        }
    }

    private static func message(for code: kern_return_t) -> String {
        if let cString = mach_error_string(code) {
            return String(cString: cString)
        }
        return "kern_return_t(\(code))"
    }
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
}

public protocol SMCClient: Sendable {
    func read(_ key: String) throws -> SMCValue
    func numericValue(for key: String) -> Double?
    func write(_ key: String, bytes: [UInt8]) throws
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

public final class SMCConnection: SMCClient, @unchecked Sendable {
    public let serviceName: String
    public static let parameterStructSize = MemoryLayout<SMCKeyData>.stride
    private let connection: io_connect_t

    public init() throws {
        var lastOpenResult: kern_return_t?

        for candidate in ["AppleSMC", "AppleSMCKeysEndpoint"] {
            guard let matching = IOServiceMatching(candidate) else {
                continue
            }

            var iterator: io_iterator_t = 0
            let matchResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard matchResult == kIOReturnSuccess else {
                lastOpenResult = matchResult
                continue
            }
            defer { IOObjectRelease(iterator) }

            let device = IOIteratorNext(iterator)
            guard device != 0 else {
                continue
            }
            defer { IOObjectRelease(device) }

            var openedConnection: io_connect_t = 0
            let openResult = IOServiceOpen(device, mach_task_self_, 0, &openedConnection)
            guard openResult == kIOReturnSuccess else {
                lastOpenResult = openResult
                continue
            }

            self.serviceName = candidate
            self.connection = openedConnection
            return
        }

        if let lastOpenResult {
            throw SMCError.openFailed(lastOpenResult)
        }
        throw SMCError.serviceNotFound
    }

    deinit {
        IOServiceClose(connection)
    }

    public func read(_ key: String) throws -> SMCValue {
        guard key.utf8.count == 4 else {
            throw SMCError.invalidKey(key)
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = FourCharCode(smcKey: key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        var result = call(input: &input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(key: key, result)
        }
        guard output.result == 0 else {
            throw SMCError.firmwareRejected(key: key, output.result)
        }

        let keyInfo = output.keyInfo
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue

        result = call(input: &input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(key: key, result)
        }
        guard output.result == 0 else {
            throw SMCError.firmwareRejected(key: key, output.result)
        }

        return SMCValue(
            key: key,
            dataType: keyInfo.dataType.smcString,
            dataSize: keyInfo.dataSize,
            resultCode: output.result,
            bytes: bytesArray(output.bytes).prefix(Int(keyInfo.dataSize)).map { $0 }
        )
    }

    public func numericValue(for key: String) -> Double? {
        try? read(key).numericValue
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        guard key.utf8.count == 4 else {
            throw SMCError.invalidKey(key)
        }

        let existing = try read(key)

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = FourCharCode(smcKey: key)
        input.keyInfo.dataSize = existing.dataSize
        input.data8 = SMCCommand.writeBytes.rawValue
        input.bytes = bytesTuple(bytes)

        let result = call(input: &input, output: &output)
        guard result == kIOReturnSuccess else {
            throw SMCError.writeFailed(key: key, result)
        }
        guard output.result == 0 else {
            throw SMCError.firmwareRejected(key: key, output.result)
        }
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        return IOConnectCallStructMethod(
            connection,
            2,
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
}

private extension FourCharCode {
    init(smcKey: String) {
        self = smcKey.utf8.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}

private extension UInt32 {
    var smcString: String {
        String(bytes: [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ], encoding: .ascii) ?? ""
    }
}

private func bytesArray(_ bytes: SMCBytes) -> [UInt8] {
    withUnsafeBytes(of: bytes) { buffer in
        Array(buffer)
    }
}

private func bytesTuple(_ bytes: [UInt8]) -> SMCBytes {
    var padded = bytes + Array(repeating: 0, count: max(0, 32 - bytes.count))
    if padded.count > 32 {
        padded = Array(padded.prefix(32))
    }
    return (
        padded[0], padded[1], padded[2], padded[3],
        padded[4], padded[5], padded[6], padded[7],
        padded[8], padded[9], padded[10], padded[11],
        padded[12], padded[13], padded[14], padded[15],
        padded[16], padded[17], padded[18], padded[19],
        padded[20], padded[21], padded[22], padded[23],
        padded[24], padded[25], padded[26], padded[27],
        padded[28], padded[29], padded[30], padded[31]
    )
}
