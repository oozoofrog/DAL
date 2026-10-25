import XCTest
@testable import WorkspaceCore

final class HandPointerEngineTests: XCTestCase {
    // Wrong origin/mirror or ROI mapping would move an immutable video mark.
    func testMappingUsesOneOriginFlipAndOneOptionalMirror() {
        let roi = HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
        let plain = HandMapping(region: roi, mirrored: false)
        let mirrored = HandMapping(region: roi, mirrored: true)
        XCTAssertEqual(plain.map(HandPoint(x: 0.2, y: 0.85, confidence: 1))!.x, 0, accuracy: 0.000001)
        XCTAssertEqual(plain.map(HandPoint(x: 0.2, y: 0.85, confidence: 1))!.y, 0, accuracy: 0.000001)
        XCTAssertEqual(mirrored.map(HandPoint(x: 0.2, y: 0.85, confidence: 1))!.x, 1, accuracy: 0.000001)
        XCTAssertEqual(mirrored.map(HandPoint(x: 0.2, y: 0.85, confidence: 1))!.y, 0, accuracy: 0.000001)
        XCTAssertEqual(plain.map(HandPoint(x: 0.8, y: 0.15, confidence: 1))!.x, 1, accuracy: 0.000001)
        XCTAssertEqual(plain.map(HandPoint(x: 0.8, y: 0.15, confidence: 1))!.y, 1, accuracy: 0.000001)
    }

    func testOutsideOrInvalidROIRejectsRatherThanClampsToEdge() {
        let map = HandMapping(region: HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7), mirrored: false)
        XCTAssertNil(map.map(HandPoint(x: 0.19, y: 0.5, confidence: 1)))
        XCTAssertNil(map.map(HandPoint(x: .nan, y: 0.5, confidence: 1)))
        XCTAssertNil(map.map(HandPoint(x: 0.5, y: 0.5, confidence: 0.64)))
        XCTAssertNil(HandMapping(region: HandRegion(x: 0, y: 0, width: 0, height: 1), mirrored: false).map(HandPoint(x: 0.5, y: 0.5, confidence: 1)))
    }

    // 50 pixel fingertip distance / 200 pixel palm span = 0.25 in either orientation.
    func testPinchDistanceUsesPixelAspectNotNormalizedDistance() {
        let landscape = frame(time: 0, width: 1000, height: 500, index: (0.5, 0.5), thumb: (0.5, 0.6), palm: ((0.4, 0.4), (0.6, 0.4)))
        let portrait = frame(time: 0, width: 500, height: 1000, index: (0.5, 0.5), thumb: (0.5, 0.55), palm: ((0.3, 0.4), (0.7, 0.4)))
        XCTAssertEqual(HandPointerEngine.pinchRatio(frame: landscape)!, 0.25, accuracy: 0.000001)
        XCTAssertEqual(HandPointerEngine.pinchRatio(frame: portrait)!, 0.25, accuracy: 0.000001)
    }

    func testInvalidJointMissingHandAndOutOfOrderSamplesCancelPointer() {
        var engine = HandPointerEngine(mapping: HandMapping(region: HandRegion(x: 0, y: 0, width: 1, height: 1), mirrored: false))
        let context = HandContext(id: "view-a", versionID: "v1", playheadMs: 1000, eligible: true)
        XCTAssertNotNil(engine.process(frame: frame(time: 1), now: 1, context: context, targets: []).pointer)
        XCTAssertNil(engine.process(frame: frame(time: 1), now: 1.01, context: context, targets: []).pointer)
        var missing = frame(time: 2); missing.joints.removeValue(forKey: .wrist)
        XCTAssertNil(engine.process(frame: missing, now: 2, context: context, targets: []).pointer)
        var ambiguous = frame(time: 3); ambiguous.handCount = 2
        XCTAssertNil(engine.process(frame: ambiguous, now: 3, context: context, targets: []).pointer)
    }

    func testTimeoutCancelsWithoutInventingReleaseAction() {
        var engine = HandPointerEngine(mapping: HandMapping(region: HandRegion(x: 0, y: 0, width: 1, height: 1), mirrored: false))
        let context = HandContext(id: "view-a", versionID: "v1", playheadMs: 1000, eligible: true)
        _ = engine.process(frame: frame(time: 1), now: 1, context: context, targets: [])
        let lost = engine.tick(now: 1.151)
        XCTAssertNil(lost.pointer); XCTAssertNil(lost.action); XCTAssertEqual(lost.phase, .idle)
    }

    func testPinchLocksTargetUntilStableReleaseAndEmitsOnce() {
        var engine = identityEngine()
        let a = HandTarget(id: "request-a", kind: .visibleRequest, bounds: HandRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let video = HandTarget(id: "video", kind: .videoSurface, bounds: HandRegion(x: 0, y: 0, width: 1, height: 1))
        let context = testContext()
        for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: [video, a]) }
        let locked = engine.process(frame: frame(time: 0.4, thumb: (0.54, 0.5)), now: 0.4, context: context, targets: [video, a])
        XCTAssertEqual(locked.phase, .pinching); XCTAssertEqual(locked.lockedTarget?.id, "request-a"); XCTAssertEqual(locked.lockedContext, context)
        XCTAssertNil(locked.action)
        _ = engine.process(frame: frame(time: 0.5, index: (0.8, 0.5), thumb: (0.84, 0.5)), now: 0.5, context: context, targets: [video, a])
        XCTAssertNil(engine.process(frame: frame(time: 0.6, index: (0.8, 0.5), thumb: (1, 0.5)), now: 0.6, context: context, targets: [video, a]).action)
        XCTAssertEqual(engine.process(frame: frame(time: 0.71, index: (0.8, 0.5), thumb: (1, 0.5)), now: 0.71, context: context, targets: [video, a]).action, .selectVisibleRequest("request-a"))
        XCTAssertNil(engine.process(frame: frame(time: 0.72), now: 0.72, context: context, targets: [video, a]).action)
        XCTAssertNil(engine.process(frame: frame(time: 0.73, thumb: (0.54, 0.5)), now: 0.73, context: context, targets: [video, a]).action)
    }

    func testNoActivationWithoutOpenAndHoverDwellOrAfterLostTracking() {
        var engine = identityEngine(); let context = testContext(); let targets = [videoTarget()]
        _ = engine.process(frame: frame(time: 0), now: 0, context: context, targets: targets)
        XCTAssertNotEqual(engine.process(frame: frame(time: 0.1, thumb: (0.54, 0.5)), now: 0.1, context: context, targets: targets).phase, .pinching)
        engine.cancel()
        for t in [1.0, 1.1, 1.2, 1.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: targets) }
        _ = engine.process(frame: frame(time: 1.4, thumb: (0.54, 0.5)), now: 1.4, context: context, targets: targets)
        XCTAssertEqual(engine.tick(now: 1.551).phase, .idle)
        for t in [1.6, 1.7, 1.8] { XCTAssertNil(engine.process(frame: frame(time: t, thumb: (0.54, 0.5)), now: t, context: context, targets: targets).action) }
        XCTAssertNil(engine.process(frame: frame(time: 1.9), now: 1.9, context: context, targets: targets).action)
        XCTAssertNil(engine.process(frame: frame(time: 2.01), now: 2.01, context: context, targets: targets).action)
    }

    func testReleaseChatterRequiresContinuousOpenAndPointUsesPinchStart() {
        var engine = identityEngine(); let context = testContext(); let targets = [videoTarget()]
        for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: targets) }
        _ = engine.process(frame: frame(time: 0.4, thumb: (0.54, 0.5)), now: 0.4, context: context, targets: targets)
        _ = engine.process(frame: frame(time: 0.5), now: 0.5, context: context, targets: targets)
        _ = engine.process(frame: frame(time: 0.55, thumb: (0.62, 0.5)), now: 0.55, context: context, targets: targets)
        XCTAssertNil(engine.process(frame: frame(time: 0.6, index: (0.7, 0.5), thumb: (0.9, 0.5)), now: 0.6, context: context, targets: targets).action)
        XCTAssertEqual(engine.process(frame: frame(time: 0.71, index: (0.7, 0.5), thumb: (0.9, 0.5)), now: 0.71, context: context, targets: targets).action, .startPointDraft(HandPoint(x: 0.5, y: 0.5)))
    }

    func testContextChangeAndLockedTargetRemovalCancelInsteadOfReleasing() {
        for removeTarget in [false, true] {
            var engine = identityEngine(); let targets = [videoTarget()]; let context = testContext()
            for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: targets) }
            _ = engine.process(frame: frame(time: 0.4, thumb: (0.54, 0.5)), now: 0.4, context: context, targets: targets)
            let next = removeTarget ? context : HandContext(id: "different-view", versionID: "v2", playheadMs: 2000, eligible: true)
            let changed = engine.process(frame: frame(time: 0.5), now: 0.5, context: next, targets: removeTarget ? [] : targets)
            XCTAssertNil(changed.lockedTarget); XCTAssertNil(changed.action)
            XCTAssertNil(engine.process(frame: frame(time: 0.61), now: 0.61, context: next, targets: targets).action)
        }
    }

    func testSmoothingResetsAfterInvalidSampleAndGapCannotRelease() {
        var engine = identityEngine(); let context = testContext()
        _ = engine.process(frame: frame(time: 0, index: (0.2, 0.5), thumb: (0.4, 0.5)), now: 0, context: context, targets: [])
        let smoothed = engine.process(frame: frame(time: 0.08, index: (0.8, 0.5), thumb: (1, 0.5)), now: 0.08, context: context, targets: [])
        XCTAssertEqual(smoothed.pointer!.x, 0.5792723353, accuracy: 0.000001)
        var bad = frame(time: 0.09); bad.handCount = 0
        _ = engine.process(frame: bad, now: 0.09, context: context, targets: [])
        XCTAssertEqual(engine.process(frame: frame(time: 0.1, index: (0.8, 0.5), thumb: (1, 0.5)), now: 0.1, context: context, targets: []).pointer!.x, 0.8, accuracy: 0.000001)
    }

    func testLetterboxPointConvertsToVideoCoordinatesAndBarsNeverArm() {
        let box = VideoContentBox(containerWidth: 1000, containerHeight: 1000, videoWidth: 1600, videoHeight: 900)
        let target = HandTarget(id: "video", kind: .videoSurface, bounds: HandRegion(x: box.left / 1000, y: box.top / 1000, width: box.width / 1000, height: box.height / 1000))
        var engine = identityEngine(); let context = testContext()
        for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t, index: (0.25, 0.7), thumb: (0.45, 0.7)), now: t, context: context, targets: [target]) }
        _ = engine.process(frame: frame(time: 0.4, index: (0.25, 0.7), thumb: (0.29, 0.7)), now: 0.4, context: context, targets: [target])
        _ = engine.process(frame: frame(time: 0.5, index: (0.25, 0.7), thumb: (0.45, 0.7)), now: 0.5, context: context, targets: [target])
        let result = engine.process(frame: frame(time: 0.61, index: (0.25, 0.7), thumb: (0.45, 0.7)), now: 0.61, context: context, targets: [target])
        guard case .startPointDraft(let point) = result.action else { return XCTFail("Expected unsaved video point") }
        XCTAssertEqual(point.x, 0.25, accuracy: 0.000001); XCTAssertEqual(point.y, 0.1444444444, accuracy: 0.000001)
        XCTAssertEqual(result.lockedContext?.playheadMs, 1000)
        engine.cancel()
        for t in [1.0, 1.1, 1.2, 1.31] { XCTAssertNotEqual(engine.process(frame: frame(time: t, index: (0.5, 0.95), thumb: (0.7, 0.95)), now: t, context: context, targets: [target]).phase, .ready) }
    }

    func testTrackingGapAndChangedLockedBoundsCannotCompleteAnOldPinch() {
        for changeBounds in [false, true] {
            var engine = identityEngine(); let context = testContext(); let target = videoTarget()
            for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: [target]) }
            _ = engine.process(frame: frame(time: 0.4, thumb: (0.54, 0.5)), now: 0.4, context: context, targets: [target])
            let changed = HandTarget(id: "video", kind: .videoSurface, bounds: HandRegion(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
            let time = changeBounds ? 0.5 : 0.7
            let feedback = engine.process(frame: frame(time: time), now: time, context: context, targets: [changeBounds ? changed : target])
            XCTAssertNil(feedback.lockedTarget); XCTAssertNil(feedback.action)
            XCTAssertNil(engine.process(frame: frame(time: time + 0.11), now: time + 0.11, context: context, targets: [target]).action)
        }
    }

    func testSecondPinchNeedsFreshOpenAndHoverDwell() {
        var engine = identityEngine(); let context = testContext(); let targets = [videoTarget()]
        for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: targets) }
        _ = engine.process(frame: frame(time: 0.4, thumb: (0.54, 0.5)), now: 0.4, context: context, targets: targets)
        _ = engine.process(frame: frame(time: 0.5), now: 0.5, context: context, targets: targets)
        XCTAssertNotNil(engine.process(frame: frame(time: 0.61), now: 0.61, context: context, targets: targets).action)
        XCTAssertNotEqual(engine.process(frame: frame(time: 0.7, thumb: (0.54, 0.5)), now: 0.7, context: context, targets: targets).phase, .pinching)
        for t in [0.8, 0.9, 1.0, 1.11] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: targets) }
        XCTAssertEqual(engine.process(frame: frame(time: 1.2, thumb: (0.54, 0.5)), now: 1.2, context: context, targets: targets).phase, .pinching)
        _ = engine.process(frame: frame(time: 1.3), now: 1.3, context: context, targets: targets)
        XCTAssertNotNil(engine.process(frame: frame(time: 1.41), now: 1.41, context: context, targets: targets).action)
    }

    func testGradualPinchKeepsArmedTargetThroughIntermediateClosingRatios() {
        var engine = identityEngine(); let context = testContext(); let targets = [videoTarget()]
        for t in [0.0, 0.1, 0.2, 0.31] { _ = engine.process(frame: frame(time: t), now: t, context: context, targets: targets) }
        // Palm span .4: .16/.4=.40, .12/.4=.30, .096/.4=.24.
        _ = engine.process(frame: frame(time: 0.4, thumb: (0.66, 0.5)), now: 0.4, context: context, targets: targets)
        _ = engine.process(frame: frame(time: 0.5, thumb: (0.62, 0.5)), now: 0.5, context: context, targets: targets)
        XCTAssertEqual(engine.process(frame: frame(time: 0.6, thumb: (0.596, 0.5)), now: 0.6, context: context, targets: targets).phase, .pinching)
        _ = engine.process(frame: frame(time: 0.7), now: 0.7, context: context, targets: targets)
        XCTAssertNotNil(engine.process(frame: frame(time: 0.81), now: 0.81, context: context, targets: targets).action)
    }

    func testOverlappingVisibleTargetsRejectAmbiguousSelectionRegardlessOfOrder() {
        let a = HandTarget(id: "a", kind: .visibleRequest, bounds: HandRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let b = HandTarget(id: "b", kind: .visibleRequest, bounds: a.bounds)
        for targets in [[a,b,videoTarget()], [b,a,videoTarget()]] {
            var engine = identityEngine(); let context = testContext()
            for t in [0.0, 0.1, 0.2, 0.31] { XCTAssertNotEqual(engine.process(frame: frame(time: t), now: t, context: context, targets: targets).phase, .ready) }
            XCTAssertNil(engine.process(frame: frame(time: 0.4, thumb: (0.54, 0.5)), now: 0.4, context: context, targets: targets).lockedTarget)
        }
    }

    private func identityEngine() -> HandPointerEngine { HandPointerEngine(mapping: HandMapping(region: HandRegion(x: 0, y: 0, width: 1, height: 1), mirrored: false)) }
    private func testContext() -> HandContext { HandContext(id: "view-a", versionID: "v1", playheadMs: 1000, eligible: true) }
    private func videoTarget() -> HandTarget { HandTarget(id: "video", kind: .videoSurface, bounds: HandRegion(x: 0, y: 0, width: 1, height: 1)) }

    private func frame(time: Double, width: Double = 1000, height: Double = 1000, index: (Double, Double) = (0.5, 0.5), thumb: (Double, Double) = (0.7, 0.5), palm: ((Double, Double), (Double, Double)) = ((0.3, 0.3), (0.7, 0.3))) -> HandFrame {
        HandFrame(time: time, imageWidth: width, imageHeight: height, handCount: 1, joints: [
            .indexTip: HandPoint(x: index.0, y: index.1, confidence: 1),
            .thumbTip: HandPoint(x: thumb.0, y: thumb.1, confidence: 1),
            .indexMCP: HandPoint(x: palm.0.0, y: palm.0.1, confidence: 1),
            .littleMCP: HandPoint(x: palm.1.0, y: palm.1.1, confidence: 1),
            .wrist: HandPoint(x: 0.5, y: 0.2, confidence: 1)
        ])
    }
}
