import Foundation
import AVFoundation
import WorkspaceCore

enum HandCameraError: Error, Equatable { case forbidden, cancelled, unavailable, configuration }
private func realCameraForbidden() -> Bool { ProcessInfo.processInfo.environment["DAL_FORBID_REAL_CAMERA"] == "1" }

@MainActor final class AppleHandPermission: HandPermissionProvider {
    private let forbidden: @Sendable () -> Bool
    init(forbidden: @escaping @Sendable () -> Bool = { realCameraForbidden() }) { self.forbidden = forbidden }
    func videoStatus() -> HandVideoAuthorization {
        guard !forbidden() else { return .denied }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }
    func requestVideoAccess() async -> Bool {
        guard !forbidden() else { return false }
        return await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// No capture/permission object exists until explicit authorized discovery/start.
@MainActor final class CameraHandDriver: HandCaptureDriver {
    private let forbidden: @Sendable () -> Bool
    private let worker: CameraHandWorker
    init(forbidden: @escaping @Sendable () -> Bool = { realCameraForbidden() }) {
        self.forbidden = forbidden; worker = CameraHandWorker(forbidden: forbidden)
    }
    func discoverVideoDevices(generation: UUID) async throws -> [HandCameraChoice] {
        guard !forbidden() else { throw HandCameraError.forbidden }
        worker.prepareDiscovery(generation)
        return try await worker.discover(generation)
    }
    func start(deviceID: String, listGeneration: UUID, generation: UUID, onFrame: @escaping (HandFrame) -> Void, onInterruption: @escaping () -> Void) async throws {
        guard !forbidden() else { throw HandCameraError.forbidden }
        try await worker.start(deviceID: deviceID, listGeneration: listGeneration, generation: generation, onFrame: onFrame, onInterruption: onInterruption)
    }
    func stop() { worker.stop() }
}

/// SDK objects and Vision work stay on this serial queue. Invalidation uses a lock so stop
/// suppresses actions immediately, even while an SDK start/stop call has not returned.
private final class CameraHandWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "DAL.hand.camera", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UUID?
    private let forbidden: @Sendable () -> Bool
    private let detector: VisionHandDetector
    private var session: AVCaptureSession?
    private var observers: [NSObjectProtocol] = []
    private var discoveredIDs: [String] = []
    private var captureGeneration: UUID?
    private var captureListGeneration: UUID?
    private var onFrame: ((HandFrame) -> Void)?
    private var onInterruption: (() -> Void)?
    private var lastProcessed: Double = -.infinity
    init(forbidden: @escaping @Sendable () -> Bool) { self.forbidden = forbidden; detector = VisionHandDetector(forbidden: forbidden); super.init() }
    func prepareDiscovery(_ token: UUID) { lock.lock(); generation = token; lock.unlock() }
    private func current(_ token: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == token }
    private func invalidate() { lock.lock(); generation = nil; lock.unlock() }
    private func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices.sorted { $0.uniqueID < $1.uniqueID }
    }
    func discover(_ token: UUID) async throws -> [HandCameraChoice] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.forbidden() else { return continuation.resume(throwing: HandCameraError.forbidden) }
                guard self.current(token) else { return continuation.resume(throwing: HandCameraError.cancelled) }
                let devices = self.devices()
                guard self.current(token) else { return continuation.resume(throwing: HandCameraError.cancelled) }
                self.discoveredIDs = devices.map(\.uniqueID)
                continuation.resume(returning: devices.map { HandCameraChoice(id: $0.uniqueID, label: $0.localizedName) })
            }
        }
    }
    func start(deviceID: String, listGeneration: UUID, generation token: UUID, onFrame: @escaping (HandFrame) -> Void, onInterruption: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            queue.async {
                guard !self.forbidden() else { return continuation.resume(throwing: HandCameraError.forbidden) }
                guard self.current(token) else { return continuation.resume(throwing: HandCameraError.cancelled) }
                let devices = self.devices()
                guard devices.map(\.uniqueID) == self.discoveredIDs, let selected = devices.first(where: { $0.uniqueID == deviceID }) else { return continuation.resume(throwing: HandCameraError.unavailable) }
                self.stopCurrent()
                guard self.current(token) else { return continuation.resume(throwing: HandCameraError.cancelled) }
                do {
                    let capture = AVCaptureSession(); capture.beginConfiguration()
                    do {
                        let input = try AVCaptureDeviceInput(device: selected)
                        let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        guard capture.canAddInput(input), capture.canAddOutput(output) else { throw HandCameraError.configuration }
                        capture.addInput(input); capture.addOutput(output)
                        output.setSampleBufferDelegate(self, queue: self.queue)
                        if let connection = output.connection(with: .video) {
                            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
                            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                        }
                        capture.commitConfiguration()
                    } catch { capture.commitConfiguration(); throw error }
                    guard self.current(token), !self.forbidden() else { throw HandCameraError.cancelled }
                    self.session = capture; self.captureGeneration = token; self.captureListGeneration = listGeneration
                    self.onFrame = onFrame; self.onInterruption = onInterruption; self.lastProcessed = -.infinity
                    self.installObservers(token)
                    capture.startRunning()
                    guard self.current(token), !self.forbidden() else { self.stopCurrent(); throw HandCameraError.cancelled }
                    guard capture.isRunning else { self.stopCurrent(); throw HandCameraError.unavailable }
                    continuation.resume()
                } catch { self.stopCurrent(); continuation.resume(throwing: error) }
            }
        }
    }
    private func installObservers(_ token: UUID) {
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification, AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.interrupt(token) })
        }
    }
    func stop() {
        invalidate()
        queue.async { self.stopCurrent(); self.discoveredIDs = [] }
    }
    private func interrupt(_ token: UUID) {
        guard current(token) else { return }; invalidate()
        queue.async {
            let callback = self.onInterruption; self.stopCurrent(); self.discoveredIDs = []
            if let callback { Task { @MainActor in callback() } }
        }
    }
    private func stopCurrent() {
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        onFrame = nil; onInterruption = nil; captureGeneration = nil; captureListGeneration = nil
        if let session { if session.isRunning { session.stopRunning() }; session.inputs.forEach(session.removeInput); session.outputs.forEach(session.removeOutput) }
        session = nil
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !forbidden(), let token = captureGeneration, current(token), captureListGeneration != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessed >= 1 / 15 else { return }; lastProcessed = now
        guard let frame = detector.detect(sampleBuffer, time: now), current(token), let callback = onFrame else { return }
        Task { @MainActor in callback(frame) }
    }
}
