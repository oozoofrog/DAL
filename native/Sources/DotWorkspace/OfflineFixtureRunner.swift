#if DEBUG
import AppKit
import Foundation
import WorkspaceCore

/// Explicit isolated app-owned QA only. Never runs against the normal workspace.
@MainActor enum OfflineFixtureRunner {
  static func run(store: OfflineWorkspaceStore) async {
    let env = ProcessInfo.processInfo.environment
    guard let mode = env["DAL_OFFLINE_QA_MODE"], let rootPath = env["DAL_OFFLINE_QA_ROOT"] else { return }
    let root = URL(fileURLWithPath: rootPath).standardizedFileURL
    let receiptURL = root.appendingPathComponent("qa-report.json")
    do {
      guard ["create", "reopen", "export", "hand"].contains(mode), root.path == root.resolvingSymlinksInPath().path,
        try String(contentsOf: root.appendingPathComponent("DAL_TEST_FIXTURE_ONLY"), encoding: .utf8) == "synthetic-offline-workbench-test\n" else { throw OfflineError.invalid("격리된 시험 폴더 표식을 확인해 주세요.") }
      if mode == "create" {
        guard store.snapshot.projects.isEmpty, let source = env["DAL_OFFLINE_QA_MEDIA"] else { throw OfflineError.invalid("새 시험에는 비어 있는 시험 폴더와 허용된 영상이 필요합니다.") }
        await store.createProject(name: "DAL_TEST_FIXTURE · 로컬 메모 시험")
        await store.importVideo(URL(fileURLWithPath: source), asNewArtifact: true)
        guard let version = store.version, store.error == nil else { throw OfflineError.invalid(store.error ?? "시험 영상을 열지 못했습니다.") }
        await store.createRequest(anchor: .init(versionID: version.id, startMs: 1000, endMs: min(3000, version.durationMs), annotation: .init(type: "rectangle", x: 0.3, y: 0.3, x2: 0.65, y2: 0.65)), body: "DAL_TEST_FIXTURE · 위치와 저장 재로드 시험. 사람의 제작 지시가 아닙니다.")
        guard let request = store.request else { throw OfflineError.invalid(store.error ?? "시험 메모를 저장하지 못했습니다.") }
        await store.saveText(id: request.id, body: "DAL_TEST_FIXTURE · 원래 영상 구간과 표시, 수정 이력을 보관합니다.", expectedRevision: request.revision)
        if let current = store.request { await store.setResolved(current) }
        if let current = store.request { await store.setResolved(current) }
      }
      guard let request = store.snapshot.requests.first, let version = store.snapshot.versions.first(where: { $0.id == request.anchor.versionID }), store.error == nil else { throw OfflineError.invalid(store.error ?? "시험 기록이 없습니다.") }
      store.selectProject(store.snapshot.projects.first!.id)
      store.selectArtifact(request.artifactID)
      store.selectRequest(request.id)
      await store.verifySelectedMedia()
      if mode == "hand" { return }
      try await store.flushPendingEdits()
      if mode == "export" {
        guard request.body.hasPrefix("DAL_TEST_FIXTURE"), store.project?.name.hasPrefix("DAL_TEST_FIXTURE") == true else { throw OfflineError.invalid("명시된 합성 시험 메모만 내보내기 시험에 사용할 수 있어요.") }
        store.qaExportRequestID = request.id
        return
      }
      try await Task.sleep(for: .milliseconds(1000))
      if let path = env["DOT_SNAPSHOT_PATH"] { AppDelegate.captureOwnWindow(path: path) }
      let receipt: [String: Any] = ["mode": mode, "sourceLabel": "DAL_TEST_FIXTURE", "humanInstruction": false, "requestID": request.id, "versionID": version.id, "fingerprint": version.fingerprint, "body": request.body, "workspaceRevision": store.snapshot.revision, "requestRevision": request.revision, "eventCount": store.snapshot.events.count, "resolved": request.resolved, "availability": store.availability.rawValue, "normalQuitRequested": true]
      try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: receiptURL, options: .atomic)
    } catch {
      try? JSONSerialization.data(withJSONObject: ["mode": mode, "failure": error.localizedDescription], options: [.prettyPrinted]).write(to: receiptURL, options: .atomic)
    }
    AppDelegate.traceOfflineLifecycle("request")
    NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
  }
  private static let handClock = SyntheticHandClock()
  private static var handDriver: SyntheticHandDriver?
  static var isHandQA: Bool {
    let env = ProcessInfo.processInfo.environment
    guard env["DAL_OFFLINE_QA_MODE"] == "hand", env["DAL_FORBID_REAL_CAMERA"] == "1", let path = env["DAL_OFFLINE_QA_ROOT"] else { return false }
    let root = URL(fileURLWithPath: path).standardizedFileURL
    return root == root.resolvingSymlinksInPath() && (try? String(contentsOf: root.appendingPathComponent("DAL_TEST_FIXTURE_ONLY"), encoding: .utf8)) == "synthetic-offline-workbench-test\n"
  }
  static func handSessionForQA() -> HandInputSession? {
    guard isHandQA else { return nil }
    let driver = SyntheticHandDriver(); handDriver = driver
    return HandInputSession(permission: SyntheticHandPermission(), driver: driver, now: { handClock.time }, mapping: HandMapping(region: HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7), mirrored: true))
  }
  static func handViewQA(session: HandInputSession, surface: () -> HandInputSurface, draft: () -> Annotation?, apply: (HandFeedback) -> Void) async {
    guard isHandQA, let rootPath = ProcessInfo.processInfo.environment["DAL_OFFLINE_QA_ROOT"], let driver = handDriver else { return }
    let root = URL(fileURLWithPath: rootPath)
    do {
      try await Task.sleep(for: .milliseconds(300))
      let off = session.state == .off && session.selectedDeviceID == nil
      guard off, surface().context.eligible else { throw OfflineError.invalid("합성 시험의 준비 상태를 확인하지 못했어요.") }
      if let image = ProcessInfo.processInfo.environment["DOT_SNAPSHOT_PATH"] { AppDelegate.captureOwnWindow(path: URL(fileURLWithPath: image).deletingPathExtension().path + "-off.png") }
      await session.enableFromUserAction(context: surface().context)
      session.chooseDevice(id: "DAL_TEST_CAMERA_OFF")
      await session.startSelectedDeviceFromUserAction(context: surface().context)
      session.updateTargets(surface().targets)
      guard session.state == .running else { throw OfflineError.invalid("가짜 입력 어댑터를 준비하지 못했어요.") }
      // Deterministic synthetic joints only, never a captured frame or a human instruction.
      for (offset,closed) in [(0.0,false),(0.1,false),(0.2,false),(0.31,false),(0.4,true),(0.5,true),(0.6,false),(0.71,false)] {
        handClock.time = offset
        let joints: [HandJoint: HandPoint] = [.indexTip: .init(x: 0.32,y: 0.325), .thumbTip: .init(x: closed ? 0.36 : 0.52,y: 0.325), .indexMCP: .init(x: 0.3,y: 0.2), .littleMCP: .init(x: 0.7,y: 0.2), .wrist: .init(x: 0.5,y: 0.1)]
        driver.emit(HandFrame(time: offset, imageWidth: 1000,imageHeight: 1000,handCount: 1,joints: joints))
        if session.feedback.action != nil { apply(session.feedback) }
        try await Task.sleep(for: .milliseconds(50))
      }
      guard let mark = draft(), mark.type == "point", abs(mark.x - 0.8) < 0.001, abs(mark.y - 0.75) < 0.001, session.state == .off else { throw OfflineError.invalid("합성 입력으로 저장 전 점을 확인하지 못했어요.") }
      if let image = ProcessInfo.processInfo.environment["DOT_SNAPSHOT_PATH"] { AppDelegate.captureOwnWindow(path: image) }
      let report: [String: Any] = ["sourceLabel":"DAL_TEST_FIXTURE", "humanInstruction":false, "cameraOFF":true, "syntheticLandmarks":true, "defaultOFFObserved":off, "fakeDriverStartCount":driver.startCount, "unsavedPointCreated":true, "finalStateOFF":session.state == .off, "normalQuitRequested":true, "liveHardwareTested":false]
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("qa-hand-report.json"), options: .atomic)
    } catch {
      session.disable()
      try? JSONSerialization.data(withJSONObject: ["failure":error.localizedDescription,"cameraOFF":true,"syntheticLandmarks":true], options: .prettyPrinted).write(to: root.appendingPathComponent("qa-hand-report.json"), options: .atomic)
    }
    AppDelegate.traceOfflineLifecycle("request")
    NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0.3)
  }

  static func exportViewQA(coordinator: OfflineExportCoordinator, preview: ExportPreview, dismiss: () -> Void) async {
    let env = ProcessInfo.processInfo.environment
    guard env["DAL_OFFLINE_QA_MODE"] == "export", let path = env["DAL_OFFLINE_QA_ROOT"],
      (try? String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("DAL_TEST_FIXTURE_ONLY"), encoding: .utf8)) == "synthetic-offline-workbench-test\n",
      preview.snapshot.requests.allSatisfy({ $0.body.hasPrefix("DAL_TEST_FIXTURE") }) else { return }
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    var closeRequested = false
    do {
      try await Task.sleep(for: .milliseconds(900))
      if let image = env["DOT_SNAPSHOT_PATH"] { AppDelegate.captureOwnWindow(path: image) }
      scrollOwnPreviewToBottom()
      try await Task.sleep(for: .milliseconds(250))
      if let image = env["DOT_SNAPSHOT_PATH"] { AppDelegate.captureOwnWindow(path: URL(fileURLWithPath: image).deletingPathExtension().path + "-files.png") }
      let json: [String: Any]
      if env["DAL_OFFLINE_QA_EXPORT_CANCEL"] == "1" {
        dismiss()
        closeRequested = true
        json = ["sourceLabel": "DAL_TEST_FIXTURE", "humanInstruction": false, "newNoteCreated": false, "exportID": preview.snapshot.exportID, "snapshotCreatedAt": preview.snapshot.createdAtText, "requestIDs": preview.snapshot.requests.map(\.id), "cancelled": true, "savedFile": false, "previewExactByteCount": preview.exactByteCount, "archiveExistsAfterCancel": FileManager.default.fileExists(atPath: preview.archiveURL.path), "normalQuitRequested": true]
      } else {
        let destination = root.appendingPathComponent("qa-export-\(preview.snapshot.exportID)-메모.zip")
        let receipt = try await coordinator.commit(preview: preview, destination: destination)
        json = ["sourceLabel": "DAL_TEST_FIXTURE", "humanInstruction": false, "newNoteCreated": false, "exportID": receipt.exportID, "snapshotCreatedAt": preview.snapshot.createdAtText, "requestIDs": preview.snapshot.requests.map(\.id), "cancelled": false, "savedFile": true, "archivePath": destination.path, "previewExactByteCount": preview.exactByteCount, "savedByteCount": receipt.byteCount, "previewSHA256": preview.archiveSHA256, "savedSHA256": receipt.archiveSHA256, "entryPaths": preview.entries.map(\.path), "captures": preview.captures.map { ["requestID": $0.requestID, "requestedMs": $0.requestedMs, "actualCapturedMs": $0.actualMs, "width": $0.pixelWidth, "height": $0.pixelHeight] as [String: Any] }, "normalQuitRequested": true]
      }
      try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("qa-export-report.json"), options: .atomic)
    } catch {
      try? JSONSerialization.data(withJSONObject: ["failure": error.localizedDescription, "sourceLabel": "DAL_TEST_FIXTURE"], options: [.prettyPrinted]).write(to: root.appendingPathComponent("qa-export-report.json"), options: .atomic)
    }
    if !closeRequested { dismiss() }
    AppDelegate.traceOfflineLifecycle("request")
    NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0.3)
  }
  private static func scrollOwnPreviewToBottom() {
    guard let view = (NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }))?.contentView else { return }
    func find(_ node: NSView) -> NSScrollView? {
      if let scroll = node as? NSScrollView, let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height + 20 { return scroll }
      for child in node.subviews { if let found = find(child) { return found } }
      return nil
    }
    guard let scroll = find(view), let document = scroll.documentView else { return }
    let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
    scroll.contentView.scroll(to: NSPoint(x: 0, y: y));scroll.reflectScrolledClipView(scroll.contentView)
  }

}
@MainActor private final class SyntheticHandClock { var time = 0.0 }
@MainActor private final class SyntheticHandPermission: HandPermissionProvider {
  func videoStatus() -> HandVideoAuthorization { .authorized }
  func requestVideoAccess() async -> Bool { true }
}
@MainActor private final class SyntheticHandDriver: HandCaptureDriver {
  var callback: ((HandFrame) -> Void)?
  var startCount = 0
  func discoverVideoDevices(generation: UUID) async throws -> [HandCameraChoice] { [.init(id: "DAL_TEST_CAMERA_OFF", label: "합성 입력 · 카메라 꺼짐")] }
  func start(deviceID: String, listGeneration: UUID, generation: UUID, onFrame: @escaping (HandFrame) -> Void, onInterruption: @escaping () -> Void) async throws { startCount += 1; callback = onFrame }
  func stop() { callback = nil }
  func emit(_ frame: HandFrame) { callback?(frame) }
}

#endif
