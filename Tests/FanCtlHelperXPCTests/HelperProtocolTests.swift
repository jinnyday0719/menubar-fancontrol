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
    }

    func testWireFailureRejectsMalformedResponses() {
        XCTAssertNil(FanCtlHelperWire.decodeFailure("plain helper message"))
        XCTAssertNil(FanCtlHelperWire.decodeFailure("MFANCTL_HELPER_ERROR|missing-message"))
        XCTAssertNil(FanCtlHelperWire.decodeFailure("WRONG_PREFIX|code|message"))
    }

    func testManualLeaseHasRoomForMoreThanTwoHeartbeatIntervals() {
        XCTAssertGreaterThan(
            FanCtlHelperConstants.manualControlLeaseDuration,
            FanCtlHelperConstants.manualControlHeartbeatInterval * 2
        )
    }

    func testSharedCommandBoundsAndProtocolVersionAreValid() {
        XCTAssertEqual(FanCtlHelperConstants.protocolVersion, 3)
        XCTAssertGreaterThan(FanCtlHelperConstants.minimumRPM, 0)
        XCTAssertGreaterThan(
            FanCtlHelperConstants.maximumEncodedRPM,
            FanCtlHelperConstants.minimumRPM
        )
    }
}
