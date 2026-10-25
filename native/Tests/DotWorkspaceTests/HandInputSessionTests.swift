import XCTest
import WorkspaceCore
@testable import DotWorkspace

@MainActor final class HandInputSessionTests: XCTestCase {
    func testConstructionAndDisableDoNotQueryPermissionOrDiscoverDevices() {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        XCTAssertEqual(s.state, .off); XCTAssertTrue(s.choices.isEmpty); XCTAssertNil(s.selectedDeviceID)
        s.disable()
        XCTAssertEqual(p.statusCalls, 0); XCTAssertEqual(p.requestCalls, 0); XCTAssertEqual(d.discoverCalls, 0); XCTAssertEqual(d.startCalls, 0)
    }
    func testDeniedPermissionNeverDiscoversOrStarts() async {
        let p = FakeHandPermission(); p.status = .denied; let d = FakeHandDriver(); let s = make(p,d)
        await s.enableFromUserAction(context: context())
        XCTAssertEqual(s.state, .denied); XCTAssertEqual(d.discoverCalls, 0); XCTAssertEqual(d.startCalls, 0)
    }
    func testLatePermissionGrantCannotReviveStoppedSession() async {
        let p = FakeHandPermission(); p.status = .notDetermined; p.hold = true
        let d = FakeHandDriver(); let s = make(p,d)
        let pending = Task { await s.enableFromUserAction(context: context()) }
        await wait { p.gate != nil }; s.disable(); p.gate?.resume(returning: true); p.gate = nil; await pending.value
        XCTAssertEqual(s.state, .off); XCTAssertEqual(d.discoverCalls, 0); XCTAssertEqual(d.startCalls, 0)
    }
    func testEvenOneCameraRequiresOwnerSelectionAndSeparateStart() async {
        for count in [1,2] {
            let p = FakeHandPermission(); let d = FakeHandDriver(); d.devices = Array(d.devices.prefix(count)); let s = make(p,d)
            await s.enableFromUserAction(context: context())
            XCTAssertEqual(s.state, .choosingDevice); XCTAssertNil(s.selectedDeviceID); XCTAssertEqual(d.startCalls, 0)
            await s.startSelectedDeviceFromUserAction(context: context()); XCTAssertEqual(d.startCalls, 0)
            s.chooseDevice(id: "camera-a"); await s.startSelectedDeviceFromUserAction(context: context())
            XCTAssertEqual(s.state, .running); XCTAssertEqual(d.startedIDs, ["camera-a"])
            s.disable(); await s.enableFromUserAction(context: context())
            XCTAssertNil(s.selectedDeviceID); XCTAssertEqual(s.state, .choosingDevice)
        }
    }
    func testUnknownChoiceCannotStartOrFallBackToDefault() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "missing")
        await s.startSelectedDeviceFromUserAction(context: context())
        XCTAssertNil(s.selectedDeviceID); XCTAssertEqual(d.startCalls, 0)
    }
    func testLateDiscoveryCannotPopulateStoppedSession() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); d.holdDiscovery = true; let s = make(p,d)
        let pending = Task { await s.enableFromUserAction(context: context()) }
        await wait { d.discoveryGate != nil }; s.disable(); d.discoveryGate?.resume(returning: d.devices); d.discoveryGate = nil; await pending.value
        XCTAssertEqual(s.state, .off); XCTAssertTrue(s.choices.isEmpty)
    }
    func testChangedDeviceListBeforeStartClearsChoiceRatherThanSwitchesCamera() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a")
        d.devices = [HandCameraChoice(id: "camera-b", label: "B")]
        await s.startSelectedDeviceFromUserAction(context: context())
        XCTAssertEqual(d.startCalls, 0); XCTAssertNil(s.selectedDeviceID); XCTAssertEqual(s.state, .choosingDevice)
    }
    func testLateStartCompletionCannotReviveOrDeliverFramesAfterStop() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); d.holdStart = true; let s = make(p,d)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a")
        let pending = Task { await s.startSelectedDeviceFromUserAction(context: context()) }
        await wait { d.startGate != nil }; let callback = d.frameCallback; s.disable(); d.startGate?.resume(); d.startGate = nil; await pending.value
        callback?(sample()); XCTAssertEqual(s.state, .off); XCTAssertNil(s.feedback.pointer); XCTAssertNil(s.feedback.action)
        XCTAssertGreaterThanOrEqual(d.stopCalls, 1)
    }
    func testInterruptionClearsSelectionAndNeverRestarts() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a"); await s.startSelectedDeviceFromUserAction(context: context())
        d.interruptionCallback?(); XCTAssertEqual(s.state, .off); XCTAssertNil(s.selectedDeviceID); XCTAssertTrue(s.choices.isEmpty); XCTAssertEqual(d.startCalls, 1)
    }
    func testFocusOrContextLossStopsAndLateFramesCannotEmitAction() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a"); await s.startSelectedDeviceFromUserAction(context: context())
        let callback = d.frameCallback
        s.updateContext(HandContext(id: "other", versionID: "v2", playheadMs: 2000, eligible: false))
        callback?(sample()); XCTAssertEqual(s.state, .off); XCTAssertNil(s.feedback.pointer); XCTAssertNil(s.feedback.action)
        s.updateContext(context()); XCTAssertEqual(d.startCalls, 1)
    }
    func testDoubleEnableDoesNotStartASecondPermissionRequest() async {
        let p = FakeHandPermission(); p.status = .notDetermined; p.hold = true; let d = FakeHandDriver(); let s = make(p,d)
        let pending = Task { await s.enableFromUserAction(context: context()) }; await wait { p.gate != nil }
        await s.enableFromUserAction(context: context()); XCTAssertEqual(p.requestCalls, 1)
        s.disable(); p.gate?.resume(returning: true); p.gate = nil; await pending.value
    }
    func testIneligibleEnableAndStartNeverQueryOrStartCamera() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        let blocked = HandContext(id: "view", versionID: "v1", playheadMs: 1000, eligible: false)
        await s.enableFromUserAction(context: blocked)
        XCTAssertEqual(p.statusCalls, 0); XCTAssertEqual(d.discoverCalls, 0); XCTAssertEqual(s.state, .off)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a")
        await s.startSelectedDeviceFromUserAction(context: blocked)
        XCTAssertEqual(d.startCalls, 0)
    }
    func testMappingChangeStopsRunningAndRequiresFreshChoice() async {
        let p = FakeHandPermission(); let d = FakeHandDriver(); let s = make(p,d)
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a"); await s.startSelectedDeviceFromUserAction(context: context())
        s.updateMapping(HandMapping(region: HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7), mirrored: true))
        XCTAssertEqual(s.state, .off); XCTAssertNil(s.selectedDeviceID); XCTAssertTrue(s.choices.isEmpty)
        await s.startSelectedDeviceFromUserAction(context: context()); XCTAssertEqual(d.startCalls, 1)
    }
    func testMappingChangeInvalidatesPendingPermissionAndStartCompletion() async {
        let mapping = HandMapping(region: HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7), mirrored: true)
        let p = FakeHandPermission(); p.status = .notDetermined; p.hold = true; let d = FakeHandDriver(); let s = make(p,d)
        let permission = Task { await s.enableFromUserAction(context: context()) }; await wait { p.gate != nil }
        s.updateMapping(mapping); p.gate?.resume(returning: true); p.gate = nil; await permission.value
        XCTAssertEqual(s.state, .off); XCTAssertEqual(d.discoverCalls, 0)
        p.status = .authorized; d.holdStart = true
        await s.enableFromUserAction(context: context()); s.chooseDevice(id: "camera-a")
        let start = Task { await s.startSelectedDeviceFromUserAction(context: context()) }; await wait { d.startGate != nil }
        s.updateMapping(HandMapping(region: HandRegion(x: 0, y: 0, width: 1, height: 1), mirrored: false))
        d.startGate?.resume(); d.startGate = nil; await start.value
        XCTAssertEqual(s.state, .off); XCTAssertNil(s.selectedDeviceID)
    }

    private func make(_ p: FakeHandPermission, _ d: FakeHandDriver) -> HandInputSession {
        HandInputSession(permission: p, driver: d, now: { 1 }, mapping: HandMapping(region: HandRegion(x: 0, y: 0, width: 1, height: 1), mirrored: false))
    }
    private func context() -> HandContext { HandContext(id: "view", versionID: "v1", playheadMs: 1000, eligible: true) }
    private func sample() -> HandFrame { HandFrame(time: 1, imageWidth: 1000, imageHeight: 1000, handCount: 0, joints: [:]) }
    private func wait(_ predicate: () -> Bool) async { for _ in 0..<100 { if predicate() { return }; await Task.yield() }; XCTFail("Expected bounded fake callback readiness") }
}

@MainActor private final class FakeHandPermission: HandPermissionProvider {
    var status: HandVideoAuthorization = .authorized
    var statusCalls = 0; var requestCalls = 0; var hold = false
    var gate: CheckedContinuation<Bool,Never>?
    func videoStatus() -> HandVideoAuthorization { statusCalls += 1; return status }
    func requestVideoAccess() async -> Bool { requestCalls += 1; if hold { return await withCheckedContinuation { gate = $0 } }; return true }
}
@MainActor private final class FakeHandDriver: HandCaptureDriver {
    var devices = [HandCameraChoice(id: "camera-a", label: "A"), HandCameraChoice(id: "camera-b", label: "B")]
    var discoverCalls = 0; var startCalls = 0; var stopCalls = 0; var startedIDs: [String] = []
    var holdDiscovery = false; var holdStart = false
    var discoveryGate: CheckedContinuation<[HandCameraChoice],Error>?
    var startGate: CheckedContinuation<Void,Error>?
    var frameCallback: ((HandFrame) -> Void)?; var interruptionCallback: (() -> Void)?
    func discoverVideoDevices(generation: UUID) async throws -> [HandCameraChoice] { discoverCalls += 1; if holdDiscovery { return try await withCheckedThrowingContinuation { discoveryGate = $0 } }; return devices }
    func start(deviceID: String, listGeneration: UUID, generation: UUID, onFrame: @escaping (HandFrame) -> Void, onInterruption: @escaping () -> Void) async throws {
        startCalls += 1; startedIDs.append(deviceID); frameCallback = onFrame; interruptionCallback = onInterruption
        if holdStart { try await withCheckedThrowingContinuation { startGate = $0 } }
    }
    func stop() { stopCalls += 1 }
}
