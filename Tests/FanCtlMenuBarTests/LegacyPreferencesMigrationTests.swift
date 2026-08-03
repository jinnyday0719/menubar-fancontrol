import Foundation
import XCTest
@testable import FanCtlMenuBar

final class LegacyPreferencesMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MenuBarFanControlTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCopiesUserSettingsWithoutHelperRegistrationState() {
        let presets = Data([0x10, 0x20, 0x30])

        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: [
                "didAskLaunchAtLogin": true,
                "launchAtLoginEnabled": false,
                "menuBarTitleFormat": "{TEMP}℃",
                "appLanguageCode": "ko",
                "updateCheckAtLaunchEnabled": false,
                "userFanPresets": presets,
                "registeredFanControlHelperBuild": "19",
                "registeredFanControlHelperFingerprint": "legacy"
            ]
        )

        XCTAssertEqual(defaults.object(forKey: "didAskLaunchAtLogin") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "launchAtLoginEnabled") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "menuBarTitleFormat"), "{TEMP}℃")
        XCTAssertEqual(defaults.string(forKey: "appLanguageCode"), "ko")
        XCTAssertEqual(
            defaults.object(forKey: "updateCheckAtLaunchEnabled") as? Bool,
            false
        )
        XCTAssertEqual(defaults.data(forKey: "userFanPresets"), presets)
        XCTAssertNil(defaults.object(forKey: "registeredFanControlHelperBuild"))
        XCTAssertNil(
            defaults.object(forKey: "registeredFanControlHelperFingerprint")
        )
    }

    func testIncompleteMigrationRefreshesValuesFromLegacyIdentity() {
        defaults.set("en", forKey: "appLanguageCode")

        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["appLanguageCode": "ko"]
        )

        XCTAssertEqual(defaults.string(forKey: "appLanguageCode"), "ko")
        XCTAssertEqual(
            defaults.integer(
                forKey: "menuBarFanControlIdentifierMigrationVersion"
            ),
            0
        )
    }

    func testCompletedMigrationIsIdempotent() {
        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "first"]
        )
        LegacyPreferencesMigration.complete(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl"
        )

        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "second"]
        )

        XCTAssertEqual(defaults.string(forKey: "menuBarTitleFormat"), "first")
    }

    func testIgnoresLegacyDomainForUnexpectedBundleIdentity() {
        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "example.invalid",
            legacyDomain: ["appLanguageCode": "ko"]
        )

        XCTAssertNil(defaults.string(forKey: "appLanguageCode"))
    }

    func testRetryUsesLatestLegacyValuesUntilCompletion() {
        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "first"]
        )
        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "second"]
        )

        XCTAssertEqual(defaults.string(forKey: "menuBarTitleFormat"), "second")
    }

    func testMissingLegacyDomainDoesNotCompleteMigration() {
        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: nil
        )

        XCTAssertEqual(
            defaults.integer(
                forKey: "menuBarFanControlIdentifierMigrationVersion"
            ),
            0
        )
    }

    func testRefreshAndCompleteCopiesFinalLegacyValues() {
        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "before-quit"]
        )

        LegacyPreferencesMigration.refreshAndComplete(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "after-quit"]
        )

        XCTAssertEqual(
            defaults.string(forKey: "menuBarTitleFormat"),
            "after-quit"
        )

        LegacyPreferencesMigration.stageIfNeeded(
            defaults: defaults,
            currentBundleIdentifier: "io.github.jinnyday0719.MenuBarFanControl",
            legacyDomain: ["menuBarTitleFormat": "too-late"]
        )
        XCTAssertEqual(
            defaults.string(forKey: "menuBarTitleFormat"),
            "after-quit"
        )
    }

    func testUnverifiedPersistedLaunchIntentIsDiscardedOnRetry() {
        defaults.set(
            true,
            forKey: "menuBarFanControlLegacyLaunchAtLoginIntent"
        )

        LegacyLaunchAtLoginIntentMigration.reconcile(
            defaults: defaults,
            observedLegacyStatus: .inactive
        )

        XCTAssertNil(
            LegacyLaunchAtLoginIntentMigration.persistedIntent(
                defaults: defaults
            )
        )
    }

    func testSuccessfulRemovalPreservesEnabledIntentAcrossRetry() {
        LegacyLaunchAtLoginIntentMigration.recordSuccessfulRemoval(
            defaults: defaults,
            removedRegistrationStatus: .enabled
        )

        LegacyLaunchAtLoginIntentMigration.reconcile(
            defaults: defaults,
            observedLegacyStatus: .inactive
        )

        XCTAssertEqual(
            LegacyLaunchAtLoginIntentMigration.persistedIntent(
                defaults: defaults
            ),
            true
        )
    }

    func testSuccessfulRemovalPreservesApprovalDenialAcrossRetry() {
        LegacyLaunchAtLoginIntentMigration.recordSuccessfulRemoval(
            defaults: defaults,
            removedRegistrationStatus: .requiresApproval
        )

        LegacyLaunchAtLoginIntentMigration.reconcile(
            defaults: defaults,
            observedLegacyStatus: .inactive
        )

        XCTAssertEqual(
            LegacyLaunchAtLoginIntentMigration.persistedIntent(
                defaults: defaults
            ),
            false
        )
    }

    func testReappearingRegistrationInvalidatesRecordedIntent() {
        LegacyLaunchAtLoginIntentMigration.recordSuccessfulRemoval(
            defaults: defaults,
            removedRegistrationStatus: .enabled
        )

        LegacyLaunchAtLoginIntentMigration.reconcile(
            defaults: defaults,
            observedLegacyStatus: .requiresApproval
        )

        XCTAssertNil(
            LegacyLaunchAtLoginIntentMigration.persistedIntent(
                defaults: defaults
            )
        )
    }
}
