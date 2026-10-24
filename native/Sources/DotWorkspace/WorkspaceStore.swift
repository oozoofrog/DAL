import AVFoundation
import SwiftUI
import WorkspaceCore

@MainActor final class WorkspaceStore: ObservableObject {

  let client: SiteSession
  @Published private(set) var connected = false
  @Published var showingConnectionStatus = false
  func showConnectionStatus() { showingConnectionStatus = true }
  func dismissConnectionStatus() { showingConnectionStatus = false }
  @Published var error: String?
  @Published var busy = false
  @Published var projects: [Project] = []
  @Published var project: Project?
  @Published var artifact: Artifact?
  @Published var snapshot = ReviewSnapshot.empty
  @Published var tools = ToolSnapshot.empty
  @Published var destination = "home"
  @Published var drafts = DraftStore()
  var operations = OperationKeys()
  var stopPlayback: (() -> Void)?
  init(configuredOrigin: URL? = nil) {
    let configured =
      configuredOrigin
      ?? (Bundle.main.object(forInfoDictionaryKey: "DotBackendOrigin") as? String).flatMap(
        URL.init(string:))
    let origin = configured ?? URL(string: "https://example.invalid")!
    client = SiteSession(origin: origin)
    client.onExpired = {
      [weak self] in
      self?.connected = false
      self?.projects = []
      self?.snapshot = .empty
      self?.tools = .empty
      self?.stopPlayback?()
    }
  }

  func disconnect() {
    client.disconnect()
    showingConnectionStatus = false
    project = nil
    artifact = nil
    destination = "home"
    error = nil
  }

  func refresh() async {
    guard connected else {
      return
    }
    busy = true
    defer {
      busy = false
    }
    do {
      let body: ProjectList = try await client.request(path: "/api/projects")
      projects = body.projects
      if destination == "project" {
        try await loadReview()
      }
      if destination == "tool" {
        try await loadTools()
      }
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  func select(_ project: Project, artifact: Artifact? = nil) async {
    self.project = project
    self.artifact = artifact ?? project.artifacts.first
    destination = "project"
    snapshot = .empty
    do {
      try await loadReview()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func loadReview() async throws {
    guard let project, let artifact else {
      return
    }
    let pid = project.id
    let aid = artifact.id
    var components = URLComponents()
    components.path = "/api/review"
    components.queryItems = [
      .init(name: "projectId", value: pid), .init(name: "artifactId", value: aid),
    ]
    let result: ReviewSnapshot = try await client.request(path: components.string!)
    if self.project?.id == pid && self.artifact?.id == aid {
      snapshot = result
    }
  }

  func loadTools() async throws {
    tools = try await client.request(path: "/api/tool")
  }

  func showTools() async {
    destination = "tool"
    do {
      try await loadTools()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func mutate(path: String, payload: [String: Any]) async throws -> MutationResult {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let fingerprint = path + data.base64EncodedString()
    var body = payload
    body["operationKey"] = operations.key(for: fingerprint)
    do {
      let result: MutationResult = try await client.request(path: path, method: "POST", body: body)
      operations.confirm(fingerprint)
      return result
    } catch {
      self.error = error.localizedDescription
      throw error
    }
  }

  func createProject(name: String, summary: String) async throws {
    _ = try await mutate(
      path: "/api/projects", payload: ["project": ["name": name, "summary": summary]])
    await refresh()
  }

  func createThread(version: Version, start: Int, end: Int, annotation: Annotation, intent: String)
    async throws -> String?
  {
    guard let project, let artifact, annotation.isValid,
      ReviewRange(startMs: start, endMs: end).fits(
        actualDuration: Double(version.durationMs) / 1000)
    else {
      throw ConnectionError.server("영상 안의 구간과 표시를 확인해 주세요.")
    }
    let result = try await mutate(
      path: "/api/threads",
      payload: [
        "projectId": project.id, "artifactId": artifact.id,
        "anchor": [
          "versionId": version.id, "startMs": start, "endMs": end, "annotation": annotation.json,
          "intent": intent,
        ],
      ])
    try await loadReview()
    return result.threadId
  }

  func threadAction(_ thread: ReviewThread, kind: String, body: String? = nil) async throws {
    guard let project, let artifact else {
      return
    }
    var action: [String: Any] = ["kind": kind, "expectedRevision": thread.revision]
    if let body {
      action["body"] = body
    }
    if kind == "approve" {
      guard thread.status == "completed", let result = thread.resultMessageId else {
        throw ConnectionError.server("실제 전달된 결과를 확인해 주세요.")
      }
      action["resultMessageId"] = result
    }
    _ = try await mutate(
      path: "/api/threads/\(thread.id)/actions",
      payload: ["projectId": project.id, "artifactId": artifact.id, "action": action])
    try await loadReview()
  }

  func upload(file: URL, duration: Double, fps: Double) async throws -> String? {
    guard let project, let artifact else {
      return nil
    }
    busy = true
    defer {
      busy = false
    }
    let scope = file.startAccessingSecurityScopedResource()
    defer {
      if scope {
        file.stopAccessingSecurityScopedResource()
      }
    }
    let result = try await client.upload(
      file: file, label: file.deletingPathExtension().lastPathComponent,
      durationMs: Int((duration * 1000).rounded()), fps: fps, projectId: project.id,
      artifactId: artifact.id)
    try await loadReview()
    return result.versionId
  }

  func createToolRequest(_ body: String) async throws -> String? {
    let r = try await mutate(path: "/api/tool", payload: ["body": body])
    try await loadTools()
    return r.requestId
  }

  func toolAction(_ request: ToolRequest, kind: String, body: String? = nil) async throws {
    var a: [String: Any] = ["kind": kind, "expectedRevision": request.revision]
    if let body {
      a["body"] = body
    }
    if ["approve", "defer"].contains(kind), let proposal = request.proposalId {
      a["proposalId"] = proposal
    }
    _ = try await mutate(path: "/api/tool/\(request.id)/actions", payload: ["action": a])
    try await loadTools()
  }

}
