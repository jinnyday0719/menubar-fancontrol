import Foundation

public enum FanCtlLegacyServiceStatus: String, Codable, Equatable, Sendable {
    case enabled
    case requiresApproval
    case inactive
}

public struct FanCtlLegacyCleanupReport: Codable, Equatable, Sendable {
    public let initialDaemonStatus: FanCtlLegacyServiceStatus
    public let initialLoginItemStatus: FanCtlLegacyServiceStatus
    public let manualHelperInstallDetected: Bool
    public let requiresActiveHelperRecovery: Bool

    public init(
        initialDaemonStatus: FanCtlLegacyServiceStatus,
        initialLoginItemStatus: FanCtlLegacyServiceStatus,
        manualHelperInstallDetected: Bool,
        requiresActiveHelperRecovery: Bool
    ) {
        self.initialDaemonStatus = initialDaemonStatus
        self.initialLoginItemStatus = initialLoginItemStatus
        self.manualHelperInstallDetected = manualHelperInstallDetected
        self.requiresActiveHelperRecovery = requiresActiveHelperRecovery
    }

    public var loginItemWasEnabled: Bool {
        initialLoginItemStatus == .enabled
    }
}

public struct FanCtlLegacyCleanupPlan: Equatable, Sendable {
    public let restoresAutomatic: Bool
    public let unregistersDaemon: Bool
    public let unregistersLoginItem: Bool

    public init(
        restoresAutomatic: Bool,
        unregistersDaemon: Bool,
        unregistersLoginItem: Bool
    ) {
        self.restoresAutomatic = restoresAutomatic
        self.unregistersDaemon = unregistersDaemon
        self.unregistersLoginItem = unregistersLoginItem
    }
}

public enum FanCtlLegacyCleanupPlanner {
    public static func plan(
        daemonStatus: FanCtlLegacyServiceStatus,
        loginItemStatus: FanCtlLegacyServiceStatus
    ) -> FanCtlLegacyCleanupPlan {
        FanCtlLegacyCleanupPlan(
            restoresAutomatic: daemonStatus == .enabled,
            unregistersDaemon: daemonStatus != .inactive,
            unregistersLoginItem: loginItemStatus != .inactive
        )
    }
}

public enum FanCtlLegacyPreferencePlanner {
    public static func valuesToCopy(
        keys: [String],
        legacyDomain: [String: Any]
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in keys {
            result[key] = legacyDomain[key]
        }
        return result
    }
}

public enum FanCtlLaunchAtLoginMigrationPlanner {
    public static func shouldRemainEnabled(
        persistedMigrationIntent: Bool? = nil,
        explicitPreference: Bool,
        currentRegistrationStatus: FanCtlLegacyServiceStatus,
        legacyRegistrationStatus: FanCtlLegacyServiceStatus
    ) -> Bool {
        if let persistedMigrationIntent {
            return persistedMigrationIntent
        }
        if legacyRegistrationStatus == .requiresApproval,
           currentRegistrationStatus == .inactive {
            return false
        }
        return explicitPreference ||
            currentRegistrationStatus != .inactive ||
            legacyRegistrationStatus == .enabled
    }
}
