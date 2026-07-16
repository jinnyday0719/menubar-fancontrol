import Foundation

public enum FanCtlHelperConstants {
    public static let appName = "mFanCtl"
    public static let appExecutableName = "mFanCtl"
    public static let machServiceName = "io.github.jinnyday0719.mfanctl.FanControlHelper"
    public static let daemonPlistName = "\(machServiceName).plist"
    public static let helperExecutableName = "mFanCtlFanHelper"
    public static let appBundleIdentifier = "io.github.jinnyday0719.mfanctl"
    public static let protocolVersion = 3
    public static let minimumRPM = 1
    public static let maximumEncodedRPM = 16_383
    public static let manualControlLeaseDuration: TimeInterval = 15
    public static let manualControlHeartbeatInterval: TimeInterval = 5
}

public struct FanCtlHelperWireFailure: Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum FanCtlHelperWire {
    public static let failurePrefix = "MFANCTL_HELPER_ERROR"

    public static func encodeFailure(code: String, message: String) -> String {
        "\(failurePrefix)|\(code)|\(message)"
    }

    public static func decodeFailure(_ value: String) -> FanCtlHelperWireFailure? {
        let parts = value.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Substring(failurePrefix) else {
            return nil
        }

        return FanCtlHelperWireFailure(code: String(parts[1]), message: String(parts[2]))
    }
}

@objc(MFanCtlHelperXPCProtocol)
public protocol FanCtlHelperXPCProtocol {
    func ping(withReply reply: @escaping (NSString?, NSString?) -> Void)
    func getVersion(withReply reply: @escaping (NSNumber, NSString) -> Void)
    func renewManualControlLease(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setAutomatic(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setMaximum(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setRPM(_ rpm: NSNumber, sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
}
