import XCTest
import WorkspaceCore
@testable import DotWorkspace

@MainActor final class HandInputIntegrationTests: XCTestCase {
    func testDraftTypingPlaybackOrMissingSourceExposesNoGestureAction() {
        for blocked in 0..<5 {
            let surface = HandInputPolicy.surface(versionID: "v1", selectionID: "selection", playheadMs: 1000, sourceReady: blocked != 0, paused: blocked != 1, focused: blocked != 2, typing: blocked == 3, hasUnsavedDraft: blocked == 4, geometry: geometry, visible: nil)
            XCTAssertFalse(surface.context.eligible); XCTAssertTrue(surface.targets.isEmpty)
            let feedback = HandFeedback(pointer: HandPoint(x: 0.5, y: 0.5), phase: .hovering, lockedTarget: nil, lockedContext: surface.context, action: .startPointDraft(HandPoint(x: 0.5, y: 0.5)))
            XCTAssertNil(HandInputPolicy.allowedAction(feedback, on: surface))
        }
    }
    func testOnlyVisibleAnnotationOfCurrentVersionAndTimeIsSelectable() {
        let annotation = Annotation(type: "rectangle", x: 0.3, y: 0.3, x2: 0.65, y2: 0.65)
        let visible = HandVisibleAnnotation(id: "request-a", versionID: "v1", startMs: 1000, endMs: 3000, annotation: annotation)
        XCTAssertEqual(surface(time: 2000, visible: visible).targets.filter { $0.kind == .visibleRequest }.map(\.id), ["request-a"])
        XCTAssertTrue(surface(time: 4000, visible: visible).targets.filter { $0.kind == .visibleRequest }.isEmpty)
        let other = HandVisibleAnnotation(id: "other", versionID: "v2", startMs: 0, endMs: 9000, annotation: annotation)
        XCTAssertTrue(surface(time: 2000, visible: other).targets.filter { $0.kind == .visibleRequest }.isEmpty)
    }
    func testContextVersionTimeAndGeometryChangesRejectOldAction() {
        let original = surface(time: 1000)
        let target = original.targets.first!
        let feedback = HandFeedback(pointer: HandPoint(x: 0.5, y: 0.5), phase: .hovering, lockedTarget: target, lockedContext: original.context, action: .startPointDraft(HandPoint(x: 0.25, y: 0.5)))
        XCTAssertEqual(HandInputPolicy.allowedAction(feedback, on: original), .startPointDraft(HandPoint(x: 0.25, y: 0.5)))
        XCTAssertNil(HandInputPolicy.allowedAction(feedback, on: surface(time: 1001)))
        let changedGeometry = HandVideoGeometry(width: 1200, height: 800, videoWidth: 1600, videoHeight: 900)
        let changed = HandInputPolicy.surface(versionID: "v2", selectionID: "new", playheadMs: 1000, sourceReady: true, paused: true, focused: true, typing: false, hasUnsavedDraft: false, geometry: changedGeometry, visible: nil)
        XCTAssertNil(HandInputPolicy.allowedAction(feedback, on: changed))
    }
    func testPointAndArrowTargetsStayInsideActualVideoBox() {
        for a in [Annotation(type: "point", x: 0, y: 0), Annotation(type: "arrow", x: 0.1, y: 0.2, x2: 0.8, y2: 0.7)] {
            let visible = HandVisibleAnnotation(id: "request", versionID: "v1", startMs: 0, endMs: 3000, annotation: a)
            let targets = surface(time: 1000, visible: visible).targets
            let request = targets.first { $0.kind == .visibleRequest }!.bounds
            XCTAssertGreaterThanOrEqual(request.y, 0.21875); XCTAssertLessThanOrEqual(request.y + request.height, 0.78125)
            XCTAssertGreaterThan(request.width, 0); XCTAssertGreaterThan(request.height, 0)
        }
    }
    func testInvalidGeometryCannotCreateVideoTarget() {
        let bad = HandVideoGeometry(width: 0, height: 1000, videoWidth: 0, videoHeight: .nan)
        let state = HandInputPolicy.surface(versionID: "v1", selectionID: "selection", playheadMs: 1000, sourceReady: true, paused: true, focused: true, typing: false, hasUnsavedDraft: false, geometry: bad, visible: nil)
        XCTAssertFalse(state.context.eligible); XCTAssertTrue(state.targets.isEmpty)
    }
    func testRealFactoriesAreLazyAndForbiddenEntryPointsFailBeforeSDK() async {
        let permission = AppleHandPermission(forbidden: { true })
        let driver = CameraHandDriver(forbidden: { true })
        XCTAssertEqual(permission.videoStatus(), .denied)
        let allowed = await permission.requestVideoAccess(); XCTAssertFalse(allowed)
        do { _ = try await driver.discoverVideoDevices(generation: UUID()); XCTFail("Forbidden discovery must fail") } catch { XCTAssertEqual(error as? HandCameraError, .forbidden) }
        do { try await driver.start(deviceID: "never-discover", listGeneration: UUID(), generation: UUID(), onFrame: { _ in XCTFail("No frame") }, onInterruption: {}); XCTFail("Forbidden start must fail") } catch { XCTAssertEqual(error as? HandCameraError, .forbidden) }
        driver.stop() // An idle stop must not initialize capture or permission objects.
    }
    private var geometry: HandVideoGeometry { HandVideoGeometry(width: 1000, height: 1000, videoWidth: 1600, videoHeight: 900) }
    private func surface(time: Int, visible: HandVisibleAnnotation? = nil) -> HandInputSurface {
        HandInputPolicy.surface(versionID: "v1", selectionID: "selection", playheadMs: time, sourceReady: true, paused: true, focused: true, typing: false, hasUnsavedDraft: false, geometry: geometry, visible: visible)
    }
}
