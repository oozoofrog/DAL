import Foundation

public struct OfflineProject: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
}
public struct OfflineArtifact: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let projectID: String
  public let name: String
}
public struct OfflineVersion: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let artifactID: String
  public let fingerprint: String
  public let byteCount: Int64
  public let durationMs: Int
  public var sourceLocator: String
  public init(id: String, artifactID: String, fingerprint: String, byteCount: Int64, durationMs: Int, sourceLocator: String) {
    self.id = id; self.artifactID = artifactID; self.fingerprint = fingerprint
    self.byteCount = byteCount; self.durationMs = durationMs; self.sourceLocator = sourceLocator
  }
}
public struct OfflineAnchor: Codable, Equatable, Sendable {
  public let versionID: String
  public let startMs: Int
  public let endMs: Int
  public let annotation: Annotation
  public init(versionID: String, startMs: Int, endMs: Int, annotation: Annotation) {
    self.versionID = versionID; self.startMs = startMs; self.endMs = endMs; self.annotation = annotation
  }
}
public struct OfflineRequest: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let artifactID: String
  public let anchor: OfflineAnchor
  public let supersedesID: String?
  public var body: String
  public var revision: Int
  public var resolved: Bool
  public var currentResultEventID: String?
  public var approvedResultEventID: String?
}
public enum OfflineEventKind: String, Codable, Sendable {
  case request, textRevision, proposal, result, decisionApprove, decisionReject, resolved, reopened
}
public struct OfflineEvent: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let requestID: String
  public let kind: OfflineEventKind
  public let body: String
  public let resultVersionID: String?
  public let resultEventID: String?
  public let sourceLabel: String
  public let createdAt: String
}
public struct OfflineOperation: Codable, Equatable, Sendable {
  public let key: String
  public let fingerprint: String
}
public struct OfflineWorkspace: Codable, Equatable, Sendable {
  public var schemaVersion = 1
  public var revision = 0
  public var projects: [OfflineProject] = []
  public var artifacts: [OfflineArtifact] = []
  public var versions: [OfflineVersion] = []
  public var requests: [OfflineRequest] = []
  public var events: [OfflineEvent] = []
  public var operations: [OfflineOperation] = []
  public init() {}
}
public enum OfflineMutation: Codable, Sendable {
  case createProject(id: String, name: String)
  case createArtifact(id: String, projectID: String, name: String)
  case registerVersion(OfflineVersion)
  case relinkVersion(id: String, verifiedFingerprint: String, sourceLocator: String)
  case createRequest(id: String, artifactID: String, anchor: OfflineAnchor, body: String, supersedesID: String?)
  case reviseText(id: String, body: String, expectedRevision: Int)
  case appendEvent(id: String, kind: OfflineEventKind, body: String, resultVersionID: String?, resultEventID: String?, expectedRevision: Int)
  case setResolved(id: String, resolved: Bool, expectedRevision: Int)
}
public enum OfflineError: Error, LocalizedError {
  case invalid(String), conflict, corrupt, io(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    case .conflict: return "기록이 바뀌었어요. 새로 불러온 뒤 다시 저장해 주세요."
    case .corrupt: return "저장 기록을 읽지 못했어요. 마지막 정상 사본을 확인해 복구할 수 있어요."
    case .io(let message): return message
    }
  }
}
