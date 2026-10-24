import Foundation

public struct Artifact: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let projectId: String
  public let name: String
  public let kind: String
}
public struct Project: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let summary: String
  public let artifactCount: Int
  public let openCount: Int
  public let resultCount: Int
  public let updatedAt: String
  public let artifacts: [Artifact]
}
public struct ProjectList: Codable, Sendable { public let projects: [Project] }
public struct Version: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let label: String
  public let mediaHash: String?
  public let durationMs: Int
  public let fps: Double
  public let createdAt: String?
}
public struct ReviewThread: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let versionId: String
  public let startMs: Int
  public let endMs: Int
  public let annotation: Annotation
  public let intent: String
  public let status: String
  public let resolved: Bool
  public let revision: Int
  public let resultMessageId: String?
  public let resultVersionId: String?
  public let createdBy: String
  public let createdAt: String
  public let updatedAt: String
  public var range: ReviewRange { ReviewRange(startMs: startMs, endMs: endMs) }
}
public struct ReviewMessage: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let threadId: String
  public let kind: String
  public let body: String
  public let versionId: String?
  public let createdBy: String
  public let authorRole: String
  public let createdAt: String
}
public struct ReviewSnapshot: Codable, Sendable {
  public let versions: [Version]
  public let threads: [ReviewThread]
  public let messages: [ReviewMessage]
  public static var empty: Self { Self(versions: [], threads: [], messages: []) }
}
public struct MutationResult: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case threadId, requestId, versionId, projectId, artifactId, messageId, revision
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    threadId = try values.decodeIfPresent(String.self, forKey: .threadId)
    requestId = try values.decodeIfPresent(String.self, forKey: .requestId)
    versionId = try values.decodeIfPresent(String.self, forKey: .versionId)
    projectId = try values.decodeIfPresent(String.self, forKey: .projectId)
    artifactId = try values.decodeIfPresent(String.self, forKey: .artifactId)
    messageId = try values.decodeIfPresent(String.self, forKey: .messageId)
    revision = try values.decodeIfPresent(Int.self, forKey: .revision)
    guard [threadId, requestId, versionId, projectId].contains(where: { $0?.isEmpty == false })
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath, debugDescription: "Missing persisted record identifier"))
    }
  }

  public let threadId: String?
  public let requestId: String?
  public let versionId: String?
  public let projectId: String?
  public let artifactId: String?
  public let messageId: String?
  public let revision: Int?
}
public struct ToolRequest: Codable, Identifiable, Hashable, Sendable {
  public let createdBy: String?
  public let id: String
  public let body: String
  public let status: String
  public let revision: Int
  public let resolved: Bool
  public let proposalId: String?
  public let createdAt: String
  public let updatedAt: String
}
public struct Proposal: Codable, Hashable, Sendable {
  public let rationale: String
  public let summary: String
  public let scope: String
}
public struct ToolMessage: Codable, Identifiable, Hashable, Sendable {
  public let createdBy: String?
  public let id: String
  public let requestId: String
  public let kind: String
  public let body: String
  public let proposal: Proposal?
  public let authorRole: String
  public let createdAt: String
}
public struct ToolSnapshot: Codable, Sendable {
  public let requests: [ToolRequest]
  public let messages: [ToolMessage]
  public static var empty: Self { Self(requests: [], messages: []) }
}
public struct ServerFailure: Decodable { public let error: String }
public enum ConnectionError: LocalizedError {
  case notConnected, invalidOrigin, authenticationExpired, invalidResponse
  case server(String)
  public var errorDescription: String? {
    switch self {
    case .notConnected: return "현재 DAL에는 서버 연결 통로가 없습니다."
    case .invalidOrigin: return "허용된 작업실 주소만 연결할 수 있습니다."
    case .authenticationExpired: return "서버 연결을 사용할 수 없습니다."
    case .invalidResponse: return "서버 응답을 확인하지 못했습니다. 연결을 다시 확인해 주세요."
    case .server(let value): return value
    }
  }
}
