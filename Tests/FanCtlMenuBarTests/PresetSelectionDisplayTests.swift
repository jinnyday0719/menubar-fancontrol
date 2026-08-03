import XCTest
@testable import FanCtlMenuBar

@MainActor
final class PresetSelectionDisplayTests: XCTestCase {
    func testConfirmedPresetRemainsCheckedWhileTransitionIsInProgress() {
        XCTAssertEqual(
            FanCtlMenuBarModel.checkedPreset(
                selectedPreset: .automatic,
                pendingPreset: .maximum
            ),
            .automatic
        )
    }

    func testSelectedPresetIsCheckedWhenNoTransitionIsPending() {
        XCTAssertEqual(
            FanCtlMenuBarModel.checkedPreset(
                selectedPreset: .maximum,
                pendingPreset: nil
            ),
            .maximum
        )
    }

    func testPendingAutomaticDoesNotHideConfirmedManualPreset() {
        XCTAssertEqual(
            FanCtlMenuBarModel.checkedPreset(
                selectedPreset: .maximum,
                pendingPreset: .automatic
            ),
            .maximum
        )
    }

    func testAutomaticRemainsEnabledToSupersedeManualTransition() {
        XCTAssertTrue(FanCtlMenuBarModel.isPresetEnabled(
            .automatic,
            pendingPreset: .maximum,
            helperIsInstalling: false
        ))
        XCTAssertFalse(FanCtlMenuBarModel.isPresetEnabled(
            .maximum,
            pendingPreset: .maximum,
            helperIsInstalling: false
        ))
    }

    func testNoPresetIsEnabledWhileAutomaticOrHelperInstallIsPending() {
        XCTAssertFalse(FanCtlMenuBarModel.isPresetEnabled(
            .automatic,
            pendingPreset: .automatic,
            helperIsInstalling: false
        ))
        XCTAssertFalse(FanCtlMenuBarModel.isPresetEnabled(
            .automatic,
            pendingPreset: nil,
            helperIsInstalling: true
        ))
    }

    func testStaleSnapshotCannotReconcileDuringControlStateInvalidation() {
        XCTAssertFalse(FanCtlMenuBarModel.shouldReconcileObservedState(
            beganEligible: true,
            observationGeneration: 4,
            currentControlGeneration: 4,
            controlStateRefreshPending: true,
            hasInvalidationTask: true
        ))
        XCTAssertFalse(FanCtlMenuBarModel.shouldReconcileObservedState(
            beganEligible: true,
            observationGeneration: 4,
            currentControlGeneration: 4,
            controlStateRefreshPending: true,
            hasInvalidationTask: false
        ))
        XCTAssertFalse(FanCtlMenuBarModel.shouldReconcileObservedState(
            beganEligible: true,
            observationGeneration: 4,
            currentControlGeneration: 4,
            controlStateRefreshPending: false,
            hasInvalidationTask: true
        ))
        XCTAssertTrue(FanCtlMenuBarModel.shouldReconcileObservedState(
            beganEligible: true,
            observationGeneration: 4,
            currentControlGeneration: 4,
            controlStateRefreshPending: false,
            hasInvalidationTask: false
        ))
    }

    func testEditingPreviousPresetDoesNotOverrideAnotherPendingChoice() {
        let presetID = UUID()
        XCTAssertFalse(FanCtlMenuBarModel.shouldReapplyUpdatedUserPreset(
            .custom(presetID),
            selectedPreset: .custom(presetID),
            pendingPreset: .maximum,
            safetyRecoveryPending: false
        ))
        XCTAssertFalse(FanCtlMenuBarModel.shouldReapplyUpdatedUserPreset(
            .custom(presetID),
            selectedPreset: .custom(presetID),
            pendingPreset: .automatic,
            safetyRecoveryPending: false
        ))
    }

    func testEditingPendingPresetKeepsOnlyThatLatestDesiredValue() {
        let presetID = UUID()
        XCTAssertTrue(FanCtlMenuBarModel.shouldReapplyUpdatedUserPreset(
            .custom(presetID),
            selectedPreset: .automatic,
            pendingPreset: .custom(presetID),
            safetyRecoveryPending: false
        ))
    }

    func testAutomaticTransitionRejectsDeferredManualReapplication() {
        let presetID = UUID()
        XCTAssertEqual(
            FanCtlMenuBarModel.pendingPresetRequestDisposition(
                requestedPreset: .custom(presetID),
                pendingPreset: .automatic
            ),
            .ignore
        )
        XCTAssertEqual(
            FanCtlMenuBarModel.pendingPresetRequestDisposition(
                requestedPreset: .automatic,
                pendingPreset: .maximum
            ),
            .start
        )
        XCTAssertEqual(
            FanCtlMenuBarModel.pendingPresetRequestDisposition(
                requestedPreset: .custom(presetID),
                pendingPreset: .maximum
            ),
            .deferLatest
        )
    }
}
