import XCTest
@testable import OutcutShare

@MainActor
final class PermissionsModelTests: XCTestCase {
    func testRefreshReportsAllSatisfied() async {
        let model = PermissionsModel(preflight: { true },
                                     captureProbe: { true },
                                     virtualDisplayCheck: { true })
        await model.refresh()
        XCTAssertTrue(model.status.screenRecordingGranted)
        XCTAssertTrue(model.status.captureWorks)
        XCTAssertTrue(model.status.virtualDisplayAvailable)
        XCTAssertTrue(model.status.allSatisfied)
        XCTAssertFalse(model.status.needsRelaunch)
    }

    func testRefreshReportsMissingPermission() async {
        let model = PermissionsModel(preflight: { false },
                                     captureProbe: { false },
                                     virtualDisplayCheck: { true })
        await model.refresh()
        XCTAssertFalse(model.status.screenRecordingGranted)
        XCTAssertFalse(model.status.allSatisfied)
        XCTAssertFalse(model.status.needsRelaunch)
    }

    func testGrantedButNotWorkingNeedsRelaunch() async {
        let model = PermissionsModel(preflight: { true },
                                     captureProbe: { false },
                                     virtualDisplayCheck: { true })
        await model.refresh()
        XCTAssertTrue(model.status.screenRecordingGranted)
        XCTAssertFalse(model.status.captureWorks)
        XCTAssertFalse(model.status.allSatisfied)
        XCTAssertTrue(model.status.needsRelaunch)
    }

    func testCaptureProbeSkippedWhileNotGranted() async {
        // The functional probe must not run (and possibly trigger TCC UI)
        // while preflight already says the permission is missing.
        var probeRan = false
        let model = PermissionsModel(preflight: { false },
                                     captureProbe: { probeRan = true; return true },
                                     virtualDisplayCheck: { true })
        await model.refresh()
        XCTAssertFalse(probeRan)
        XCTAssertFalse(model.status.captureWorks)
    }

    func testMissingVirtualDisplayDoesNotBlockAllSatisfied() async {
        let model = PermissionsModel(preflight: { true },
                                     captureProbe: { true },
                                     virtualDisplayCheck: { false })
        await model.refresh()
        XCTAssertFalse(model.status.virtualDisplayAvailable)
        XCTAssertTrue(model.status.allSatisfied)
    }
}
