import Foundation
import CryptoKit
import Darwin

/// Local authority only. Source labels do not authenticate a user, agent or imported text.
public actor OfflineRepository {
  public let directory: URL
  private let maximumBytes = 32 * 1024 * 1024
  public init(directory: URL) throws {
    let root = directory.standardizedFileURL
    guard root.isFileURL, root.path == root.resolvingSymlinksInPath().path else { throw OfflineError.io("저장 폴더 링크를 사용할 수 없습니다.") }
    if !FileManager.default.fileExists(atPath: root.path) {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    guard (try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType) == .typeDirectory else { throw OfflineError.io("저장 폴더를 확인해 주세요.") }
    self.directory = root
  }
  private func locked<T>(_ work: () throws -> T) throws -> T {
    guard directory.path == directory.resolvingSymlinksInPath().path else { throw OfflineError.io("저장 폴더가 바뀌었습니다.") }
    let fd = open(directory.appendingPathComponent(".workspace.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw OfflineError.io("저장 기록을 잠그지 못했습니다.") }
    defer { close(fd) }
    var st = stat()
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, flock(fd, LOCK_EX) == 0 else { throw OfflineError.io("저장 잠금이 유효하지 않습니다.") }
    defer { flock(fd, LOCK_UN) }
    return try work()
  }
  private func readFile(_ name: String) throws -> Data? {
    let fd = open(directory.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    if fd < 0 {
      if errno == ENOENT { return nil }
      throw OfflineError.io("저장 파일을 안전하게 열지 못했습니다.")
    }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var st = stat()
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size <= maximumBytes else { throw OfflineError.corrupt }
    let bytes = try file.read(upToCount: maximumBytes + 1) ?? Data()
    guard bytes.count <= maximumBytes else { throw OfflineError.corrupt }
    return bytes
  }
  private func decode(_ data: Data) throws -> OfflineWorkspace {
    do {
      let state = try JSONDecoder().decode(OfflineWorkspace.self, from: data)
      try validate(state)
      return state
    } catch { throw OfflineError.corrupt }
  }
  private func current() throws -> (OfflineWorkspace, Data?) {
    if let data = try readFile("workspace.json") { return (try decode(data), data) }
    guard try readFile("workspace.backup.json") == nil else { throw OfflineError.corrupt }
    return (OfflineWorkspace(), nil)
  }
  public func load() throws -> OfflineWorkspace { try locked { try current().0 } }
  private func atomicWrite(_ data: Data, name: String) throws {
    guard data.count <= maximumBytes else { throw OfflineError.io("저장 기록이 허용 크기를 넘었습니다.") }
    let destination = directory.appendingPathComponent(name)
    if let _ = try readFile(name) { } // Refuse links/special files before replacement.
    let temporary = directory.appendingPathComponent(".workspace-" + UUID().uuidString + ".tmp")
    let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw OfflineError.io("임시 저장 파일을 만들지 못했습니다.") }
    defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
    try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
    guard fsync(fd) == 0, rename(temporary.path, destination.path) == 0 else { throw OfflineError.io("저장하지 못했습니다. 기존 기록은 유지됩니다.") }
    let rootFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    if rootFD >= 0 { _ = fsync(rootFD); close(rootFD) }
  }
  public func recoverBackup() throws -> OfflineWorkspace {
    try locked {
      guard let backup = try readFile("workspace.backup.json") else { throw OfflineError.corrupt }
      let restored = try decode(backup)
      if let current = try readFile("workspace.json") {
        try atomicWrite(current, name: "workspace.retained-" + UUID().uuidString + ".json")
      }
      try atomicWrite(backup, name: "workspace.json")
      return restored
    }
  }
  public func transact(expectedWorkspaceRevision: Int, mutation: OfflineMutation, operationKey: String = UUID().uuidString) throws -> OfflineWorkspace {
    try locked {
      let (saved, originalBytes) = try current()
      let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
      let payload = try encoder.encode(mutation) + Data("|\(expectedWorkspaceRevision)".utf8)
      let fingerprint = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
      guard !operationKey.isEmpty, operationKey.utf8.count <= 150 else { throw OfflineError.invalid("저장 요청 키를 확인해 주세요.") }
      if let receipt = saved.operations.first(where: { $0.key == operationKey }) {
        guard receipt.fingerprint == fingerprint else { throw OfflineError.conflict }
        return saved
      }
      guard saved.revision == expectedWorkspaceRevision else { throw OfflineError.conflict }
      var next = saved
      try apply(mutation, to: &next)
      next.revision += 1
      next.operations.append(.init(key: operationKey, fingerprint: fingerprint))
      try validate(next)
      let bytes = try encoder.encode(next)
      if let originalBytes { try atomicWrite(originalBytes, name: "workspace.backup.json") }
      try atomicWrite(bytes, name: "workspace.json")
      return next
    }
  }
  private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw OfflineError.invalid(message) }
  }
  private func label(_ text: String) throws {
    try require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 65536, "내용을 확인해 주세요.")
  }
  private func append(_ kind: OfflineEventKind, requestID: String, body: String, versionID: String? = nil, resultID: String? = nil, state: inout OfflineWorkspace) -> String {
    let id = UUID().uuidString
    let source = (kind == .proposal || kind == .result) ? "local-reference-unverified" : "local-entry-unverified"
    state.events.append(.init(id: id, requestID: requestID, kind: kind, body: body, resultVersionID: versionID, resultEventID: resultID, sourceLabel: source, createdAt: ISO8601DateFormatter().string(from: Date())))
    return id
  }
  private func requestIndex(_ id: String, revision: Int, state: OfflineWorkspace) throws -> Int {
    guard let index = state.requests.firstIndex(where: { $0.id == id }) else { throw OfflineError.invalid("요청을 찾지 못했습니다.") }
    guard state.requests[index].revision == revision else { throw OfflineError.conflict }
    return index
  }
  private func apply(_ mutation: OfflineMutation, to state: inout OfflineWorkspace) throws {
    switch mutation {
    case .createProject(let id, let name):
      try label(name); try require(!state.projects.contains(where: { $0.id == id }), "프로젝트 ID가 이미 있습니다.")
      state.projects.append(.init(id: id, name: name))
    case .createArtifact(let id, let projectID, let name):
      try label(name); try require(state.projects.contains(where: { $0.id == projectID }) && !state.artifacts.contains(where: { $0.id == id }), "프로젝트와 작업물을 확인해 주세요.")
      state.artifacts.append(.init(id: id, projectID: projectID, name: name))
    case .registerVersion(let version):
      try require(state.artifacts.contains(where: { $0.id == version.artifactID }), "작업물을 찾지 못했습니다.")
      if let existing = state.versions.first(where: { $0.id == version.id }) { try require(existing == version, "버전 기록은 바꿀 수 없습니다.") }
      else { state.versions.append(version) }
    case .relinkVersion(let id, let fingerprint, let locator):
      guard let index = state.versions.firstIndex(where: { $0.id == id && $0.fingerprint == fingerprint }) else { throw OfflineError.invalid("같은 영상 버전을 선택해 주세요.") }
      state.versions[index].sourceLocator = locator
    case .createRequest(let id, let artifactID, let anchor, let body, let supersedesID):
      try label(body); try require(!state.requests.contains(where: { $0.id == id }), "요청 ID가 이미 있습니다.")
      if let supersedesID { try require(state.requests.contains(where: { $0.id == supersedesID && $0.artifactID == artifactID }), "이전 요청과 작업물이 다릅니다.") }
      state.requests.append(.init(id: id, artifactID: artifactID, anchor: anchor, supersedesID: supersedesID, body: body, revision: 0, resolved: false))
      _ = append(.request, requestID: id, body: body, state: &state)
    case .reviseText(let id, let body, let expected):
      try label(body); let index = try requestIndex(id, revision: expected, state: state)
      state.requests[index].body = body; state.requests[index].revision += 1
      _ = append(.textRevision, requestID: id, body: body, state: &state)
    case .setResolved(let id, let resolved, let expected):
      let index = try requestIndex(id, revision: expected, state: state)
      try require(state.requests[index].resolved != resolved, "현재 상태와 같습니다.")
      state.requests[index].resolved = resolved; state.requests[index].revision += 1
      _ = append(resolved ? .resolved : .reopened, requestID: id, body: resolved ? "닫음" : "다시 열음", state: &state)
    case .appendEvent(let id, let kind, let body, let versionID, let resultID, let expected):
      try label(body)
      let index = try requestIndex(id, revision: expected, state: state)
      try require([.proposal, .result, .decisionApprove, .decisionReject].contains(kind), "기록 종류를 확인해 주세요.")
      if kind == .proposal { try require(versionID == nil && resultID == nil, "제안은 결과 전달이나 승인이 아닙니다.") }
      if kind == .result {
        guard resultID == nil, let version = state.versions.first(where: {
          $0.id == versionID && $0.artifactID == state.requests[index].artifactID
        }) else { throw OfflineError.invalid("같은 작업물의 결과 버전을 선택해 주세요.") }
        try require(state.requests[index].anchor.endMs <= version.durationMs, "결과 영상이 요청 구간보다 짧습니다.")
      }
      if kind == .decisionApprove || kind == .decisionReject {
        guard let currentID = state.requests[index].currentResultEventID, currentID == resultID,
          let result = state.events.first(where: { $0.id == currentID && $0.requestID == id && $0.kind == .result }),
          result.resultVersionID == versionID else { throw OfflineError.invalid("현재 결과에 대한 결정만 기록할 수 있습니다.") }
      }
      let eventID = append(kind, requestID: id, body: body, versionID: versionID, resultID: resultID, state: &state)
      if kind == .result {
        state.requests[index].currentResultEventID = eventID
        state.requests[index].approvedResultEventID = nil
      }
      if kind == .decisionApprove { state.requests[index].approvedResultEventID = resultID }
      if kind == .decisionReject { state.requests[index].approvedResultEventID = nil }
      state.requests[index].revision += 1
    }
  }
  private func validate(_ state: OfflineWorkspace) throws {
    try require(state.schemaVersion == 1 && state.revision >= 0, "지원하지 않는 저장 형식입니다.")
    for ids in [state.projects.map(\.id), state.artifacts.map(\.id), state.versions.map(\.id), state.requests.map(\.id), state.events.map(\.id), state.operations.map(\.key)] {
      try require(Set(ids).count == ids.count && ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 150 }, "중복되거나 잘못된 ID입니다.")
    }
    for artifact in state.artifacts { try require(state.projects.contains { $0.id == artifact.projectID }, "작업물의 프로젝트가 없습니다.") }
    for version in state.versions {
      try require(state.artifacts.contains { $0.id == version.artifactID } && version.fingerprint.count == 64 && version.fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase } && version.byteCount >= 0 && version.durationMs > 0 && version.sourceLocator.hasPrefix("/") && !version.sourceLocator.contains("\0"), "영상 버전 정보가 잘못됐습니다.")
    }
    for request in state.requests {
      guard let version = state.versions.first(where: { $0.id == request.anchor.versionID && $0.artifactID == request.artifactID }) else { throw OfflineError.invalid("요청의 영상 버전이 없습니다.") }
      try require(request.revision >= 0 && request.anchor.annotation.isValid && ReviewRange(startMs: request.anchor.startMs, endMs: request.anchor.endMs).fits(actualDuration: Double(version.durationMs) / 1000), "요청 위치나 구간이 영상과 맞지 않습니다.")
    }
    for event in state.events { try require(state.requests.contains { $0.id == event.requestID }, "기록의 요청이 없습니다.") }
  }
}
