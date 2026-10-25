import Foundation
import CryptoKit

/// Local frozen selection. Deliberately not Codable: private source locators never become a manifest.
public struct ExportSnapshot: Equatable, Sendable {
 public let exportID: String
 public let createdAt: Date
 public var createdAtText: String { ISO8601DateFormatter().string(from: createdAt) }
 public let projectID: String
 public let projectName: String
 public let artifactID: String
 public let artifactName: String
 public let requests: [OfflineRequest]
 public let events: [OfflineEvent]
 public let versions: [OfflineVersion]
 public init(workspace: OfflineWorkspace, artifactID: String, selectedRequestIDs: [String], exportID: String = UUID().uuidString, creationDate: Date = Date()) throws {
  let selected=Set(selectedRequestIDs)
  guard !selected.isEmpty, selected.count==selectedRequestIDs.count,
   let artifact=workspace.artifacts.first(where:{$0.id==artifactID}),let project=workspace.projects.first(where:{$0.id==artifact.projectID}) else { throw OfflineError.invalid("내보낼 메모를 선택해 주세요.") }
  let requests=workspace.requests.filter{selected.contains($0.id) && $0.artifactID==artifactID}.sorted{($0.anchor.startMs,$0.id)<($1.anchor.startMs,$1.id)}
  guard requests.count==selected.count else { throw OfflineError.invalid("선택한 메모와 작업물을 확인해 주세요.") }
  let versionIDs=Set(requests.map{$0.anchor.versionID})
  let versions=workspace.versions.filter{versionIDs.contains($0.id) && $0.artifactID==artifactID}.sorted{$0.id<$1.id}
  guard versions.count==versionIDs.count else { throw OfflineError.invalid("원본 버전 기록을 확인하지 못했어요.") }
  for r in requests {
   guard let v=versions.first(where:{$0.id==r.anchor.versionID}),r.anchor.startMs>=0,r.anchor.endMs>r.anchor.startMs,r.anchor.endMs<=v.durationMs,r.anchor.annotation.isValid else { throw OfflineError.invalid("메모의 원본 구간이나 표시가 올바르지 않아요.") }
  }
  self.exportID=exportID;createdAt=creationDate;projectID=project.id;projectName=project.name;self.artifactID=artifactID;artifactName=artifact.name;self.requests=requests;self.versions=versions
  events=workspace.events.filter{selected.contains($0.requestID)}
 }
 public func captureTimes(for requestID: String) -> [Int] {
  guard let request=requests.first(where:{$0.id==requestID}) else { return [] }
  let a=request.anchor
  return a.annotation.type=="point" || a.endMs-1==a.startMs ? [a.startMs] : [a.startMs,a.endMs-1]
 }
 public func isCurrent(in workspace: OfflineWorkspace) -> Bool {
  (try? ExportSnapshot(workspace:workspace,artifactID:artifactID,selectedRequestIDs:requests.map(\.id),exportID:exportID,creationDate:createdAt)) == self
 }
}
public struct AnnotatedCapture: Sendable {
 public let requestID: String
 public let versionID: String
 public let sourceFingerprint: String
 public let requestedMs: Int
 public let actualMs: Double
 public let pixelWidth: Int
 public let pixelHeight: Int
 public let png: Data
 public init(requestID:String,versionID:String,sourceFingerprint:String,requestedMs:Int,actualMs:Double,pixelWidth:Int,pixelHeight:Int,png:Data) {
  self.requestID=requestID;self.versionID=versionID;self.sourceFingerprint=sourceFingerprint;self.requestedMs=requestedMs;self.actualMs=actualMs;self.pixelWidth=pixelWidth;self.pixelHeight=pixelHeight;self.png=png
 }
}
/// In-memory generated content only. No file URL or recursive directory input.
public struct GeneratedEntry: Sendable {
 public let path: String
 public let data: Data
 public init(path:String,data:Data) { self.path=path;self.data=data }
}
public struct PublicExportManifest: Codable, Sendable {
 public struct Content: Codable, Sendable { public let path:String;public let byteCount:Int;public let sha256:String }
 public struct Source: Codable, Sendable { public let versionID:String;public let fingerprint:String;public let byteCount:Int64;public let durationMs:Int }
 public struct History: Codable, Sendable { public let id:String;public let requestID:String;public let kind:OfflineEventKind;public let body:String;public let resultVersionID:String?;public let resultEventID:String?;public let createdAt:String }
 public struct Request: Codable, Sendable { public let id:String;public let revision:Int;public let body:String;public let anchor:OfflineAnchor;public let resolved:Bool;public let currentResultEventID:String?;public let approvedResultEventID:String? }
 public struct Image: Codable, Sendable { public let path:String;public let requestID:String;public let versionID:String;public let sourceFingerprint:String;public let requestedMs:Int;public let actualCapturedMs:Double;public let pixelWidth:Int;public let pixelHeight:Int }
 public let schemaVersion:Int
 public let exportID:String
 public let createdAt:String
 public let projectID:String
 public let projectName:String
 public let artifactID:String
 public let artifactName:String
 public let provenance:String
 public let requests:[Request]
 public let history:[History]
 public let sources:[Source]
 public let images:[Image]
 public let entries:[Content]
}
public func exportSHA256(_ data:Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
