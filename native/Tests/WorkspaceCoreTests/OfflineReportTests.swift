import Foundation
import Testing
@testable import WorkspaceCore

func exportFixture() -> OfflineWorkspace {
 var s=OfflineWorkspace();s.projects=[.init(id:"p",name:"합성 프로젝트")];s.artifacts=[.init(id:"a",projectID:"p",name:"합성 작업물")]
 s.versions=[.init(id:"v",artifactID:"a",fingerprint:String(repeating:"2",count:64),byteCount:100,durationMs:12000,sourceLocator:"/synthetic/private/source.mp4")]
 let anchor=OfflineAnchor(versionID:"v",startMs:1000,endMs:2000,annotation:.init(type:"rectangle",x:0.2,y:0.3,x2:0.6,y2:0.7))
 s.requests=[.init(id:"r1",artifactID:"a",anchor:anchor,supersedesID:nil,body:"<script>alert('x')</script> & \"메모\"",revision:1,resolved:false,currentResultEventID:nil,approvedResultEventID:nil),.init(id:"r2",artifactID:"a",anchor:anchor,supersedesID:nil,body:"UNSELECTED_PRIVATE_TEXT",revision:0,resolved:false,currentResultEventID:nil,approvedResultEventID:nil)]
 s.events=[.init(id:"e",requestID:"r1",kind:.textRevision,body:"$(do-not-execute)",resultVersionID:nil,resultEventID:nil,sourceLabel:"local-entry-unverified",createdAt:"2026-10-24T00:00:00Z")]
 return s
}
func captureFixture(requestedMs:Int,actualMs:Double) -> AnnotatedCapture {
 .init(requestID:"r1",versionID:"v",sourceFingerprint:String(repeating:"2",count:64),requestedMs:requestedMs,actualMs:actualMs,pixelWidth:1,pixelHeight:1,png:Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6eSAAAAAASUVORK5CYII=")!)
}
@Test func offlineReportSelectsEscapesAndKeepsExactProvenance() throws {
 let snapshot=try ExportSnapshot(workspace:exportFixture(),artifactID:"a",selectedRequestIDs:["r1"])
 #expect(snapshot.requests.map(\.id)==["r1"]);#expect(snapshot.captureTimes(for:"r1")==[1000,1999])
 let entries=try OfflineReportRenderer.render(snapshot:snapshot,captures:[captureFixture(requestedMs:1000,actualMs:958.333),captureFixture(requestedMs:1999,actualMs:1958.333)])
 let html=String(decoding:try #require(entries.first{$0.path=="review.html"}).data,as:UTF8.self)
 #expect(html.contains("&lt;script&gt;"));#expect(!html.contains("<script>"));#expect(html.contains("$(do-not-execute)"));#expect(!html.contains("UNSELECTED_PRIVATE_TEXT"));#expect(html.contains("958.333"));#expect(html.contains("1000"));#expect(html.contains("r1"))
 let manifest=String(decoding:try #require(entries.first{$0.path=="manifest.json"}).data,as:UTF8.self)
 #expect(!manifest.contains("sourceLocator"));#expect(!manifest.contains("/synthetic"));#expect(!manifest.contains("UNSELECTED_PRIVATE_TEXT"));#expect(!manifest.contains("local-entry-unverified"))
 let parsed=try JSONSerialization.jsonObject(with:Data(manifest.utf8)) as! [String:Any]
 let content=parsed["entries"] as! [[String:Any]]
 #expect(Set(content.compactMap{$0["path"] as? String})==Set(entries.filter{$0.path != "manifest.json"}.map(\.path)))
}
@Test func offlineSnapshotRejectsWrongSelectionAndDetectsSelectedChanges() throws {
 let original=exportFixture(),snapshot=try ExportSnapshot(workspace:exportFixture(),artifactID:"a",selectedRequestIDs:["r1"])
 #expect(throws:OfflineError.self){try ExportSnapshot(workspace:original,artifactID:"a",selectedRequestIDs:["missing"])}
 #expect(throws:OfflineError.self){try ExportSnapshot(workspace:original,artifactID:"a",selectedRequestIDs:["r1","r1"])}
 var changed=original;changed.requests[0].body="changed";changed.requests[0].revision+=1
 #expect(!snapshot.isCurrent(in:changed));#expect(snapshot.isCurrent(in:original))
 changed=original;changed.requests[1].body="unselected change";#expect(snapshot.isCurrent(in:changed))
 #expect(throws:OfflineError.self){try OfflineReportRenderer.render(snapshot:snapshot,captures:[captureFixture(requestedMs:1000,actualMs:1000)])}
}
@Test func offlineSnapshotCreationTimeIsFrozenAcrossReportManifestAndChecks() throws {
 let creation=Date(timeIntervalSince1970:1234567890)
 let snapshot=try ExportSnapshot(workspace:exportFixture(),artifactID:"a",selectedRequestIDs:["r1"],creationDate:creation)
 let captures=[captureFixture(requestedMs:1000,actualMs:1000),captureFixture(requestedMs:1999,actualMs:1958.333)]
 let first=try OfflineReportRenderer.render(snapshot:snapshot,captures:captures)
 let second=try OfflineReportRenderer.render(snapshot:snapshot,captures:captures)
 #expect(snapshot.createdAt==creation);#expect(snapshot.isCurrent(in:exportFixture()))
 let manifest=try JSONSerialization.jsonObject(with:try #require(first.first{$0.path=="manifest.json"}).data) as! [String:Any]
 #expect(manifest["createdAt"] as? String==snapshot.createdAtText)
 #expect(String(decoding:try #require(first.first{$0.path=="review.html"}).data,as:UTF8.self).contains(snapshot.createdAtText))
 #expect(first.map{exportSHA256($0.data)}==second.map{exportSHA256($0.data)})
}
