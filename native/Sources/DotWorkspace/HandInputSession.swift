import Foundation
import Combine
import WorkspaceCore

enum HandVideoAuthorization { case notDetermined, authorized, denied, restricted }
struct HandCameraChoice: Equatable, Identifiable { let id: String; let label: String }
@MainActor protocol HandPermissionProvider: AnyObject {
    func videoStatus() -> HandVideoAuthorization
    func requestVideoAccess() async -> Bool
}
@MainActor protocol HandCaptureDriver: AnyObject {
    func discoverVideoDevices(generation: UUID) async throws -> [HandCameraChoice]
    func start(deviceID: String, listGeneration: UUID, generation: UUID, onFrame: @escaping (HandFrame) -> Void, onInterruption: @escaping () -> Void) async throws
    func stop()
}

/// Session-only state. Construction/restoration never queries authorization or devices.
@MainActor final class HandInputSession: ObservableObject {
    enum State: Equatable { case off, requestingPermission, discovering, choosingDevice, starting, running, denied, unavailable }
    @Published private(set) var state: State = .off
    @Published private(set) var choices: [HandCameraChoice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var feedback = HandFeedback.idle
    @Published private(set) var message: String?
    private(set) var generation = UUID()
    private(set) var listGeneration = UUID()
    private let permission: HandPermissionProvider
    private let driver: HandCaptureDriver
    private let now: () -> Double
    private var engine: HandPointerEngine
    private var context: HandContext?
    private var targets: [HandTarget] = []

    init(permission: HandPermissionProvider, driver: HandCaptureDriver, now: @escaping () -> Double, mapping: HandMapping) {
        self.permission = permission; self.driver = driver; self.now = now; engine = HandPointerEngine(mapping: mapping)
    }
    func enableFromUserAction(context: HandContext) async {
        guard context.eligible else { disable(); return }
        guard state == .off || state == .denied || state == .unavailable else { return }
        generation = UUID(); let token = generation
        self.context = context; choices = []; selectedDeviceID = nil; listGeneration = UUID(); message = nil
        engine.cancel(); feedback = .idle; state = .requestingPermission
        let status = permission.videoStatus()
        let allowed: Bool
        switch status {
        case .authorized: allowed = true
        case .notDetermined: allowed = await permission.requestVideoAccess()
        case .denied, .restricted: allowed = false
        }
        guard generation == token, state == .requestingPermission else { return }
        guard allowed else { state = .denied; message = "카메라 사용을 허용하지 않았어요. 마우스와 키보드로 계속 작업할 수 있어요."; return }
        state = .discovering
        do {
            let devices = try await driver.discoverVideoDevices(generation: token)
            guard generation == token, state == .discovering else { return }
            choices = uniqueDevices(devices); listGeneration = UUID(); selectedDeviceID = nil
            state = choices.isEmpty ? .unavailable : .choosingDevice
            if choices.isEmpty { message = "사용할 수 있는 카메라가 없어요." }
        } catch {
            guard generation == token else { return }
            disable(); state = .unavailable; message = "카메라 목록을 불러오지 못했어요. 다시 켜려면 직접 선택해 주세요."
        }
    }
    func chooseDevice(id: String) {
        guard state == .choosingDevice else { return }
        selectedDeviceID = choices.contains(where: { $0.id == id }) ? id : nil
        engine.cancel(); feedback = .idle
    }
    func startSelectedDeviceFromUserAction(context: HandContext) async {
        guard context.eligible else { disable(); return }
        guard state == .choosingDevice, let selectedDeviceID, choices.contains(where: { $0.id == selectedDeviceID }), self.context == context else { return }
        let token = generation; let listToken = listGeneration; let approvedChoices = choices
        state = .starting
        do {
            // An explicit choice is valid only for the exact device list the owner saw.
            let current = uniqueDevices(try await driver.discoverVideoDevices(generation: token))
            guard token == generation, state == .starting, listToken == listGeneration else { return }
            guard current == approvedChoices, current.contains(where: { $0.id == selectedDeviceID }) else {
                choices = current; self.selectedDeviceID = nil; listGeneration = UUID()
                state = current.isEmpty ? .unavailable : .choosingDevice
                message = "카메라 목록이 바뀌었어요. 사용할 카메라를 다시 선택해 주세요."; return
            }
            try await driver.start(deviceID: selectedDeviceID, listGeneration: listToken, generation: token, onFrame: { [weak self] frame in self?.receive(generation: token, frame: frame) }, onInterruption: { [weak self] in
                guard let self, self.generation == token else { return }; self.disable(); self.message = "카메라 연결이 끊겼어요. 다시 사용하려면 직접 켜고 선택해 주세요."
            })
            guard token == generation, state == .starting else { return }
            state = .running; engine.cancel(); feedback = .idle
        } catch {
            guard token == generation else { return }
            disable(); state = .unavailable; message = "카메라를 시작하지 못했어요. 마우스와 키보드로 계속 작업할 수 있어요."
        }
    }
    func disable() {
        // Invalidate callbacks before cleanup; a late completion cannot revive this session.
        generation = UUID(); listGeneration = UUID(); state = .off
        choices = []; selectedDeviceID = nil; context = nil; targets = []
        engine.cancel(); feedback = .idle; message = nil; driver.stop()
    }
    func updateContext(_ next: HandContext) {
        if context != nil && (context != next || !next.eligible) { disable() }
        context = next
    }
    func updateTargets(_ next: [HandTarget]) {
        if next != targets { engine.cancel(); feedback = .idle }
        targets = next
    }
    func updateMapping(_ mapping: HandMapping) {
        guard mapping != engine.mapping else { return }
        disable()
        engine = HandPointerEngine(mapping: mapping); feedback = .idle
    }
    func receive(generation token: UUID, frame: HandFrame) {
        guard token == generation, state == .running, let context, context.eligible else { return }
        feedback = engine.process(frame: frame, now: now(), context: context, targets: targets)
    }
    func tick() { tick(now: now()) }
    func tick(now: Double) {
        guard state == .running else { return }; feedback = engine.tick(now: now)
    }
    private func uniqueDevices(_ devices: [HandCameraChoice]) -> [HandCameraChoice] {
        guard Set(devices.map(\.id)).count == devices.count, devices.allSatisfy({ !$0.id.isEmpty }) else { return [] }
        return devices.sorted { $0.id < $1.id }
    }
}
