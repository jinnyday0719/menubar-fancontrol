import Foundation

public enum FanCtlHelperConstants {
    public static let appName = "MenuBar FanControl"
    public static let appExecutableName = "MenuBarFanControl"
    public static let releaseArtifactName = "MenuBar-FanControl"
    public static let helperExecutableName = "MenuBarFanControlHelper"
    public static let legacyCleanupAppName = "MenuBar FanControl Legacy Cleanup"
    public static let legacyCleanupExecutableName = "MenuBarFanControlLegacyCleanup"

    public static let appBundleIdentifier = "io.github.jinnyday0719.MenuBarFanControl"
    public static let helperBundleIdentifier = "io.github.jinnyday0719.MenuBarFanControl.Helper"
    public static let machServiceName = helperBundleIdentifier
    public static let daemonPlistName = "\(machServiceName).plist"

    // These identifiers are used only to find and remove installations made by
    // releases from before the MenuBar FanControl identity migration.
    public static let legacyAppBundleIdentifier = "io.github.jinnyday0719.mfanctl"
    public static let legacyMachServiceName = "io.github.jinnyday0719.mfanctl.FanControlHelper"
    public static let legacyDaemonPlistName = "\(legacyMachServiceName).plist"
    public static let legacyManualHelperIdentifier = "io.github.jinnyday0719.mfanctl.helper"
    public static let legacyManualHelperExecutablePath =
        "/Library/PrivilegedHelperTools/\(legacyManualHelperIdentifier)"
    public static let legacyManualHelperPlistPath =
        "/Library/LaunchDaemons/\(legacyManualHelperIdentifier).plist"
    public static let legacyManualHelperSocketPath =
        "/var/run/\(legacyManualHelperIdentifier).sock"
    public static let legacyManualHelperLogPath =
        "/var/log/\(legacyManualHelperIdentifier).log"
    public static let developerTeamIdentifier = "93BTXAM95W"

    public static let protocolVersion = 4
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
    public static let failurePrefix = "MENUBAR_FANCONTROL_HELPER_ERROR"
    private static let legacyFailurePrefix = "MFANCTL_HELPER_ERROR"

    public static func encodeFailure(code: String, message: String) -> String {
        "\(failurePrefix)|\(code)|\(message)"
    }

    public static func decodeFailure(_ value: String) -> FanCtlHelperWireFailure? {
        let parts = value.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == Substring(failurePrefix) ||
                  parts[0] == Substring(legacyFailurePrefix) else {
            return nil
        }

        return FanCtlHelperWireFailure(code: String(parts[1]), message: String(parts[2]))
    }
}

public enum FanCtlHelperRegistrationStatus: Sendable {
    case enabled
    case requiresApproval
    case inactive
}

public enum FanCtlHelperRegistrationAction: Equatable, Sendable {
    case none
    case adoptPendingRegistration
    case register
    case replace
    case awaitApproval
}

public enum FanCtlMutationKind: Hashable, Sendable {
    case manualControl
    case automaticControl
    case leaseRenewal
    case maintenance
}

/// Tracks only the newest queued mutation in each independent command domain.
/// Manual and Automatic are ordered together so the latest user choice wins;
/// lease heartbeats never supersede a fan-control request.
public final class FanCtlMutationSupersessionTracker: @unchecked Sendable {
    private enum Domain: Hashable {
        case fanControl
        case lease
        case maintenance
    }

    private let lock = NSLock()
    private var latestSubmittedSequences: [Domain: Int64] = [:]
    private var latestClaimedSequences: [Domain: Int64] = [:]

    public init() {}

    public func submit(_ sequence: Int64, kind: FanCtlMutationKind) {
        lock.withLock {
            let domain = domain(for: kind)
            latestSubmittedSequences[domain] = max(
                latestSubmittedSequences[domain] ?? .min,
                sequence
            )
        }
    }

    public func latestSequence(for kind: FanCtlMutationKind) -> Int64 {
        lock.withLock { latestSubmittedSequences[domain(for: kind)] ?? .min }
    }

    public func isSuperseded(_ sequence: Int64, kind: FanCtlMutationKind) -> Bool {
        lock.withLock { (latestSubmittedSequences[domain(for: kind)] ?? .min) > sequence }
    }

    /// Atomically admits only the newest unexecuted command in a domain.
    /// Manual and Automatic share one ordering domain, while heartbeats and
    /// maintenance cannot invalidate a user control request.
    public func claimForExecution(_ sequence: Int64, kind: FanCtlMutationKind) -> Bool {
        lock.withLock {
            let domain = domain(for: kind)
            guard sequence >= (latestSubmittedSequences[domain] ?? .min),
                  sequence > (latestClaimedSequences[domain] ?? .min) else {
                return false
            }
            latestClaimedSequences[domain] = sequence
            return true
        }
    }

    private func domain(for kind: FanCtlMutationKind) -> Domain {
        switch kind {
        case .manualControl, .automaticControl:
            .fanControl
        case .leaseRenewal:
            .lease
        case .maintenance:
            .maintenance
        }
    }
}

public enum FanCtlHelperRegistrationPlanner {
    public static func action(
        status: FanCtlHelperRegistrationStatus,
        forceReinstall: Bool,
        currentFingerprint: String,
        registeredFingerprint: String?,
        pendingFingerprint: String?
    ) -> FanCtlHelperRegistrationAction {
        switch status {
        case .enabled:
            if forceReinstall {
                return .replace
            }
            if registeredFingerprint == currentFingerprint {
                return .none
            }
            if pendingFingerprint == currentFingerprint {
                return .adoptPendingRegistration
            }
            return .replace
        case .requiresApproval:
            return registeredFingerprint == currentFingerprint ||
                pendingFingerprint == currentFingerprint
                ? .awaitApproval
                : .replace
        case .inactive:
            return .register
        }
    }
}

@objc(MenuBarFanControlHelperXPCProtocol)
public protocol FanCtlHelperXPCProtocol {
    func ping(withReply reply: @escaping (NSString?, NSString?) -> Void)
    func getVersion(withReply reply: @escaping (NSNumber, NSString) -> Void)
    func renewManualControlLease(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setAutomatic(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setMaximum(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setRPM(_ rpm: NSNumber, sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void)
    func removeLegacyManualHelperInstall(
        _ sequence: NSNumber,
        withReply reply: @escaping (NSString?, NSString?) -> Void
    )
}

@objc(MFanCtlHelperXPCProtocol)
public protocol FanCtlLegacyUnsequencedHelperXPCProtocol {
    func ping(withReply reply: @escaping (NSString?, NSString?) -> Void)
    func setAutomatic(withReply reply: @escaping (NSString?, NSString?) -> Void)
}
