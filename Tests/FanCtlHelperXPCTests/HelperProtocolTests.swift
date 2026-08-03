import XCTest
@testable import FanCtlHelperXPC

final class HelperProtocolTests: XCTestCase {
    func testWireFailureRoundTripPreservesDetailedMessage() {
        let encoded = FanCtlHelperWire.encodeFailure(
            code: "fan_control_failed",
            message: "fan 0 | target verification failed"
        )

        XCTAssertEqual(
            FanCtlHelperWire.decodeFailure(encoded),
            FanCtlHelperWireFailure(
                code: "fan_control_failed",
                message: "fan 0 | target verification failed"
            )
        )
        XCTAssertTrue(encoded.hasPrefix("MENUBAR_FANCONTROL_HELPER_ERROR|"))
    }

    func testWireFailureRejectsMalformedResponses() {
        XCTAssertNil(FanCtlHelperWire.decodeFailure("plain helper message"))
        XCTAssertNil(FanCtlHelperWire.decodeFailure("MFANCTL_HELPER_ERROR|missing-message"))
        XCTAssertNil(FanCtlHelperWire.decodeFailure("WRONG_PREFIX|code|message"))
    }

    func testWireFailureDecodesLegacyPrefixDuringBrandMigration() {
        XCTAssertEqual(
            FanCtlHelperWire.decodeFailure("MFANCTL_HELPER_ERROR|legacy|message"),
            FanCtlHelperWireFailure(code: "legacy", message: "message")
        )
    }

    func testManualLeaseHasRoomForMoreThanTwoHeartbeatIntervals() {
        XCTAssertGreaterThan(
            FanCtlHelperConstants.manualControlLeaseDuration,
            FanCtlHelperConstants.manualControlHeartbeatInterval * 2
        )
    }

    func testSharedCommandBoundsAndProtocolVersionAreValid() {
        XCTAssertEqual(FanCtlHelperConstants.protocolVersion, 4)
        XCTAssertEqual(FanCtlHelperConstants.appName, "MenuBar FanControl")
        XCTAssertEqual(FanCtlHelperConstants.appExecutableName, "MenuBarFanControl")
        XCTAssertEqual(FanCtlHelperConstants.releaseArtifactName, "MenuBar-FanControl")
        XCTAssertEqual(FanCtlHelperConstants.helperExecutableName, "MenuBarFanControlHelper")
        XCTAssertEqual(FanCtlHelperConstants.developerTeamIdentifier, "93BTXAM95W")
        XCTAssertEqual(
            FanCtlHelperConstants.appBundleIdentifier,
            "io.github.jinnyday0719.MenuBarFanControl"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.helperBundleIdentifier,
            "io.github.jinnyday0719.MenuBarFanControl.Helper"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.machServiceName,
            FanCtlHelperConstants.helperBundleIdentifier
        )
        XCTAssertEqual(
            FanCtlHelperConstants.daemonPlistName,
            "io.github.jinnyday0719.MenuBarFanControl.Helper.plist"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyAppBundleIdentifier,
            "io.github.jinnyday0719.mfanctl"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyMachServiceName,
            "io.github.jinnyday0719.mfanctl.FanControlHelper"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyDaemonPlistName,
            "io.github.jinnyday0719.mfanctl.FanControlHelper.plist"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyManualHelperIdentifier,
            "io.github.jinnyday0719.mfanctl.helper"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyManualHelperExecutablePath,
            "/Library/PrivilegedHelperTools/io.github.jinnyday0719.mfanctl.helper"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyManualHelperPlistPath,
            "/Library/LaunchDaemons/io.github.jinnyday0719.mfanctl.helper.plist"
        )
        XCTAssertEqual(
            FanCtlHelperConstants.legacyManualHelperSocketPath,
            "/var/run/io.github.jinnyday0719.mfanctl.helper.sock"
        )
        XCTAssertGreaterThan(FanCtlHelperConstants.minimumRPM, 0)
        XCTAssertGreaterThan(
            FanCtlHelperConstants.maximumEncodedRPM,
            FanCtlHelperConstants.minimumRPM
        )
    }

    func testRegistrationPlannerKeepsCurrentEnabledRegistration() {
        XCTAssertEqual(
            registrationAction(
                status: .enabled,
                registered: "current"
            ),
            .none
        )
    }

    func testRegistrationPlannerAdoptsApprovedPendingRegistration() {
        XCTAssertEqual(
            registrationAction(
                status: .enabled,
                pending: "current"
            ),
            .adoptPendingRegistration
        )
    }

    func testRegistrationPlannerReplacesStaleOrForcedEnabledRegistration() {
        XCTAssertEqual(
            registrationAction(
                status: .enabled,
                registered: "old"
            ),
            .replace
        )
        XCTAssertEqual(
            registrationAction(
                status: .enabled,
                forceReinstall: true,
                registered: "current"
            ),
            .replace
        )
    }

    func testRegistrationPlannerRespectsCurrentUserApprovalDecision() {
        XCTAssertEqual(
            registrationAction(
                status: .requiresApproval,
                registered: "current"
            ),
            .awaitApproval
        )
        XCTAssertEqual(
            registrationAction(
                status: .requiresApproval,
                pending: "current"
            ),
            .awaitApproval
        )
    }

    func testRegistrationPlannerReplacesStalePendingRegistration() {
        XCTAssertEqual(
            registrationAction(
                status: .requiresApproval,
                registered: "old",
                pending: "old"
            ),
            .replace
        )
    }

    func testRegistrationPlannerRegistersInactiveService() {
        XCTAssertEqual(
            registrationAction(status: .inactive),
            .register
        )
    }

    func testLegacyCleanupPlannerRestoresBeforeRemovingEnabledDaemon() {
        XCTAssertEqual(
            FanCtlLegacyCleanupPlanner.plan(
                daemonStatus: .enabled,
                loginItemStatus: .enabled
            ),
            FanCtlLegacyCleanupPlan(
                restoresAutomatic: true,
                unregistersDaemon: true,
                unregistersLoginItem: true
            )
        )
    }

    func testLegacyCleanupPlannerDoesNotContactDeniedDaemon() {
        XCTAssertEqual(
            FanCtlLegacyCleanupPlanner.plan(
                daemonStatus: .requiresApproval,
                loginItemStatus: .inactive
            ),
            FanCtlLegacyCleanupPlan(
                restoresAutomatic: false,
                unregistersDaemon: true,
                unregistersLoginItem: false
            )
        )
    }

    func testLegacyCleanupPlannerSkipsAbsentServices() {
        XCTAssertEqual(
            FanCtlLegacyCleanupPlanner.plan(
                daemonStatus: .inactive,
                loginItemStatus: .inactive
            ),
            FanCtlLegacyCleanupPlan(
                restoresAutomatic: false,
                unregistersDaemon: false,
                unregistersLoginItem: false
            )
        )
    }

    func testLegacyPreferencePlannerCopiesOnlyAllowlistedKeys() {
        let presets = Data([0x01, 0x02, 0x03])
        let values = FanCtlLegacyPreferencePlanner.valuesToCopy(
            keys: ["enabled", "presets", "language"],
            legacyDomain: [
                "enabled": false,
                "presets": presets,
                "language": "ko",
                "registeredFanControlHelperBuild": "19"
            ]
        )

        XCTAssertEqual(values["enabled"] as? Bool, false)
        XCTAssertEqual(values["presets"] as? Data, presets)
        XCTAssertEqual(values["language"] as? String, "ko")
        XCTAssertNil(values["registeredFanControlHelperBuild"])
    }

    func testLegacyCleanupReportRoundTripsThroughJSON() throws {
        let report = FanCtlLegacyCleanupReport(
            initialDaemonStatus: .enabled,
            initialLoginItemStatus: .requiresApproval,
            manualHelperInstallDetected: true,
            requiresActiveHelperRecovery: true
        )

        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(
            try JSONDecoder().decode(
                FanCtlLegacyCleanupReport.self,
                from: data
            ),
            report
        )
        XCTAssertFalse(report.loginItemWasEnabled)
    }

    func testLaunchAtLoginMigrationPreservesEnabledLegacyRegistration() {
        XCTAssertTrue(
            FanCtlLaunchAtLoginMigrationPlanner.shouldRemainEnabled(
                explicitPreference: false,
                currentRegistrationStatus: .inactive,
                legacyRegistrationStatus: .enabled
            )
        )
    }

    func testLaunchAtLoginMigrationPreservesLegacyApprovalDenial() {
        XCTAssertFalse(
            FanCtlLaunchAtLoginMigrationPlanner.shouldRemainEnabled(
                explicitPreference: true,
                currentRegistrationStatus: .inactive,
                legacyRegistrationStatus: .requiresApproval
            )
        )
    }

    func testLaunchAtLoginMigrationKeepsCurrentPendingRegistration() {
        XCTAssertTrue(
            FanCtlLaunchAtLoginMigrationPlanner.shouldRemainEnabled(
                explicitPreference: false,
                currentRegistrationStatus: .requiresApproval,
                legacyRegistrationStatus: .inactive
            )
        )
    }

    func testLaunchAtLoginMigrationKeepsPersistedDisabledIntentOnRetry() {
        XCTAssertFalse(
            FanCtlLaunchAtLoginMigrationPlanner.shouldRemainEnabled(
                persistedMigrationIntent: false,
                explicitPreference: true,
                currentRegistrationStatus: .enabled,
                legacyRegistrationStatus: .inactive
            )
        )
    }

    func testLaunchAtLoginMigrationKeepsPersistedEnabledIntentOnRetry() {
        XCTAssertTrue(
            FanCtlLaunchAtLoginMigrationPlanner.shouldRemainEnabled(
                persistedMigrationIntent: true,
                explicitPreference: false,
                currentRegistrationStatus: .inactive,
                legacyRegistrationStatus: .inactive
            )
        )
    }

    private func registrationAction(
        status: FanCtlHelperRegistrationStatus,
        forceReinstall: Bool = false,
        registered: String? = nil,
        pending: String? = nil
    ) -> FanCtlHelperRegistrationAction {
        FanCtlHelperRegistrationPlanner.action(
            status: status,
            forceReinstall: forceReinstall,
            currentFingerprint: "current",
            registeredFingerprint: registered,
            pendingFingerprint: pending
        )
    }
}
