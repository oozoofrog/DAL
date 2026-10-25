import Foundation
import SwiftUI
import WorkspaceCore

@MainActor final class OfflineWorkspaceStore: ObservableObject {
  let repository: OfflineRepository
  @Published private(set) var snapshot = OfflineWorkspace()
  @Published var selectedProjectID: String?
  @Published var selectedArtifactID: String?
  @Published var selectedVersionID: String? {
    willSet { if newValue != selectedVersionID { invalidateMediaSelection() } }
  }
  @Published var selectedRequestID: String?
  @Published var qaExportRequestID: String?
  @Published private(set) var mediaSelectionID = UUID()
  @Published private var composerBodies: [String: String] = [:]
  private let inspectMedia: (URL) async throws -> MediaFingerprint
  @Published private(set) var availability: MediaAvailability = .missing
  @Published var drafts = DraftStore()
  @Published var error: String?
  @Published private(set) var busy = false
  private var operations = OperationKeys()
  private var verificationToken = UUID()
  var project: OfflineProject? { snapshot.projects.first { $0.id == selectedProjectID } }
  var artifact: OfflineArtifact? { snapshot.artifacts.first { $0.id == selectedArtifactID && $0.projectID == selectedProjectID } }
  var version: OfflineVersion? { snapshot.versions.first { $0.id == selectedVersionID && $0.artifactID == selectedArtifactID } }
  var request: OfflineRequest? { snapshot.requests.first { $0.id == selectedRequestID && $0.artifactID == selectedArtifactID } }
  var canUseVerifiedSource: Bool { version != nil && availability == .matching && !busy }
  func canAnnotate(using media: MediaController) -> Bool {
    canUseVerifiedSource && media.isReadyForOffline(version, selectionID: mediaSelectionID)
  }
  init(directory: URL, inspectMedia: @escaping (URL) async throws -> MediaFingerprint = { try await OfflineMediaIdentity.inspect($0) }) throws {
    repository = try OfflineRepository(directory: directory); self.inspectMedia = inspectMedia
  }
  func composerBody(_ versionID: String) -> String { composerBodies[versionID] ?? "" }
  func setComposerBody(_ versionID: String, body: String) { composerBodies[versionID] = body }
  private func invalidateMediaSelection() {
    availability = .missing; verificationToken = UUID(); mediaSelectionID = UUID()
  }
  func prepareMedia(_ media: MediaController) async {
    let selection = mediaSelectionID
    let captured = version
    media.clear()
    await verifySelectedMedia()
    guard !Task.isCancelled, selection == mediaSelectionID, let captured, version == captured, availability == .matching else { return }
    await media.loadOffline(captured, selectionID: selection)
    guard !Task.isCancelled, selection == mediaSelectionID, version == captured else {
      if media.loadedSelectionID == selection { media.clear() }
      return
    }
    if let request { media.seek(Double(request.anchor.startMs) / 1000) }
  }
  func load() async {
    do {
      snapshot = try await repository.load()
      if !snapshot.projects.contains(where: { $0.id == selectedProjectID }) { selectedProjectID = snapshot.projects.first?.id }
      if !snapshot.artifacts.contains(where: { $0.id == selectedArtifactID && $0.projectID == selectedProjectID }) { selectedArtifactID = snapshot.artifacts.first { $0.projectID == selectedProjectID }?.id }
      if !snapshot.versions.contains(where: { $0.id == selectedVersionID && $0.artifactID == selectedArtifactID }) { selectedVersionID = snapshot.versions.last { $0.artifactID == selectedArtifactID }?.id }
      if !snapshot.requests.contains(where: { $0.id == selectedRequestID && $0.artifactID == selectedArtifactID }) { selectedRequestID = nil }
      error = nil
      await verifySelectedMedia()
    } catch { self.error = error.localizedDescription }
  }
  private func mutate(_ mutation: OfflineMutation) async throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(mutation)
    let fingerprint = encoded.base64EncodedString() + "|\(snapshot.revision)"
    snapshot = try await repository.transact(expectedWorkspaceRevision: snapshot.revision, mutation: mutation, operationKey: operations.key(for: fingerprint))
    operations.confirm(fingerprint)
  }
  func createProject(name: String) async {
    do {
      let id = UUID().uuidString
      try await mutate(.createProject(id: id, name: name))
      selectProject(id); error = nil
    } catch { self.error = error.localizedDescription }
  }
  func selectProject(_ id: String) {
    selectedProjectID = id; selectedRequestID = nil; invalidateMediaSelection()
    selectedArtifactID = snapshot.artifacts.first { $0.projectID == id }?.id
    selectedVersionID = snapshot.versions.last { $0.artifactID == selectedArtifactID }?.id
  }
  func selectArtifact(_ id: String) {
    guard snapshot.artifacts.contains(where: { $0.id == id && $0.projectID == selectedProjectID }) else { return }
    selectedArtifactID = id; selectedRequestID = nil; invalidateMediaSelection()
    selectedVersionID = snapshot.versions.last { $0.artifactID == id }?.id
  }
  func selectRequest(_ id: String) {
    guard let selected = snapshot.requests.first(where: { $0.id == id && $0.artifactID == selectedArtifactID }) else { return }
    invalidateMediaSelection()
    selectedRequestID = id; selectedVersionID = selected.anchor.versionID
  }
  func verifySelectedMedia() async {
    guard let current = version else { availability = .missing; return }
    let token = UUID(); verificationToken = token
    availability = .unreadable
    let result = await OfflineMediaIdentity.verify(URL(fileURLWithPath: current.sourceLocator), expected: .init(sha256: current.fingerprint, byteCount: current.byteCount, durationMs: current.durationMs))
    if verificationToken == token && version == current { availability = result }
  }
  func importVideo(_ url: URL, asNewArtifact: Bool) async {
    guard let pid = project?.id, !busy else { return }
    let existingArtifact = artifact?.id
    busy = true; defer { busy = false }
    do {
      let media = try await inspectMedia(url)
      guard selectedProjectID == pid else { throw CancellationError() }
      let aid: String
      if asNewArtifact || existingArtifact == nil {
        aid = UUID().uuidString
        try await mutate(.createArtifact(id: aid, projectID: pid, name: url.deletingPathExtension().lastPathComponent))
      } else { aid = existingArtifact! }
      let id = UUID().uuidString
      try await mutate(.registerVersion(.init(id: id, artifactID: aid, fingerprint: media.sha256, byteCount: media.byteCount, durationMs: media.durationMs, sourceLocator: url.path)))
      selectedArtifactID = aid; selectedVersionID = id; selectedRequestID = nil; availability = .matching; error = nil
    } catch is CancellationError { } catch { self.error = error.localizedDescription }
  }
  func relink(_ url: URL) async {
    guard let current = version, !busy else { return }
    invalidateMediaSelection()
    let selection = mediaSelectionID
    busy = true; defer { busy = false }
    do {
      let inspected = try await inspectMedia(url)
      guard selection == mediaSelectionID, version == current else { throw CancellationError() }
      guard current.fingerprint == inspected.sha256, current.byteCount == inspected.byteCount, current.durationMs == inspected.durationMs else { throw OfflineError.invalid("원래 기록과 같은 내용의 영상만 다시 연결할 수 있어요.") }
      try await mutate(.relinkVersion(id: current.id, verifiedFingerprint: inspected.sha256, sourceLocator: url.path))
      if selection == mediaSelectionID, version?.id == current.id { invalidateMediaSelection(); availability = .matching; error = nil }
    } catch is CancellationError { } catch { if selection == mediaSelectionID { self.error = error.localizedDescription } }
  }
  func createRequest(anchor: OfflineAnchor, body: String) async {
    guard let current = version, let aid = artifact?.id, anchor.versionID == current.id else { return }
    let selection = mediaSelectionID
    await verifySelectedMedia()
    guard selection == mediaSelectionID, version == current, availability == .matching else { error = "영상 파일이 달라졌거나 없어요. 같은 버전을 다시 선택해 주세요."; return }
    do {
      let id = UUID().uuidString
      try await mutate(.createRequest(id: id, artifactID: aid, anchor: anchor, body: body, supersedesID: nil))
      if composerBodies[current.id] == body { composerBodies.removeValue(forKey: current.id) }
      if selection == mediaSelectionID, version == current { selectedRequestID = id }
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  func saveText(id: String, body: String, expectedRevision: Int) async {
    do {
      try await mutate(.reviseText(id: id, body: body, expectedRevision: expectedRevision))
      drafts.clearSubmitted(id, body: body); error = nil
    } catch { self.error = error.localizedDescription }
  }
  func setResolved(_ request: OfflineRequest) async {
    do { try await mutate(.setResolved(id: request.id, resolved: !request.resolved, expectedRevision: request.revision)); error = nil }
    catch { self.error = error.localizedDescription }
  }
  func recover() async {
    do { snapshot = try await repository.recoverBackup(); error = nil; await load() }
    catch { self.error = error.localizedDescription }
  }
  func flushPendingEdits() async throws {
    guard !composerBodies.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      throw OfflineError.invalid("아직 저장하지 않은 새 메모가 있어요. 메모를 저장하거나 내용을 지운 뒤 종료해 주세요.")
    }
    for request in snapshot.requests {
      if let draft = drafts.bodyIfPresent(request.id), draft != request.body {
        try await mutate(.reviseText(id: request.id, body: draft, expectedRevision: request.revision))
        drafts.clearSubmitted(request.id, body: draft)
      }
    }
  }
}
