import Foundation

public enum FanCtlHelperConstants {
    public static let appName = "mFanCtl"
    public static let appExecutableName = "mFanCtl"
    public static let machServiceName = "io.github.jinnyday0719.mfanctl.FanControlHelper"
    public static let daemonPlistName = "\(machServiceName).plist"
    public static let helperExecutableName = "mFanCtlFanHelper"
    public static let appBundleIdentifier = "io.github.jinnyday0719.mfanctl"
}

@objc(MFanCtlHelperXPCProtocol)
public protocol FanCtlHelperXPCProtocol {
    func ping(withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setAutomatic(withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setMaximum(withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setRPM(_ rpm: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
}
