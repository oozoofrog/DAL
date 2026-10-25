import Foundation
import Testing
@testable import WorkspaceCore

private func offlineFixture() throws ->(URL,OfflineRepository){
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
 return(root,try OfflineRepository(directory:root))
}
private func seedOffline(_ repository:OfflineRepository) async throws ->OfflineWorkspace {
 var state=try await repository.load()
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.createProject(id:"project",name:"합성 프로젝트"))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.createArtifact(id:"artifact",projectID:"project",name:"합성 영상"))
 return try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.registerVersion(OfflineVersion(id:"version",artifactID:"artifact",fingerprint:String(repeating:"1",count:64),byteCount:100,durationMs:12000,sourceLocator:"/synthetic/local-only.mp4")))
}
@Test func offlineStableAnchorsHistoryAndResolveSurviveReload() async throws {
 let(root,repository)=try offlineFixture();defer{try? FileManager.default.removeItem(at:root)}
 var state=try await seedOffline(repository)
 let anchor=OfflineAnchor(versionID:"version",startMs:1000,endMs:2000,annotation:Annotation(type:"point",x:0.25,y:0.5))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.createRequest(id:"request",artifactID:"artifact",anchor:anchor,body:"합성 시험 메모",supersedesID:nil))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.reviseText(id:"request",body:"수정한 합성 메모",expectedRevision:0))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.setResolved(id:"request",resolved:true,expectedRevision:1))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.setResolved(id:"request",resolved:false,expectedRevision:2))
 let loaded=try await OfflineRepository(directory:root).load()
 #expect(loaded==state)
 #expect(loaded.requests.first?.anchor==anchor)
 #expect(loaded.requests.first?.resolved==false)
 #expect(loaded.events.map(\.kind)==[.request,.textRevision,.resolved,.reopened])
}
@Test func offlineCASAndOperationReplayNeverOverwrite() async throws {
 let(root,repository)=try offlineFixture();defer{try? FileManager.default.removeItem(at:root)}
 let initial=try await repository.load();let action=OfflineMutation.createProject(id:"stable",name:"합성")
 let saved=try await repository.transact(expectedWorkspaceRevision:initial.revision,mutation:action,operationKey:"same-operation")
 #expect(try await repository.transact(expectedWorkspaceRevision:initial.revision,mutation:action,operationKey:"same-operation")==saved)
 await #expect(throws:OfflineError.self){try await repository.transact(expectedWorkspaceRevision:initial.revision,mutation:.createProject(id:"other",name:"different"),operationKey:"same-operation")}
 await #expect(throws:OfflineError.self){try await OfflineRepository(directory:root).transact(expectedWorkspaceRevision:initial.revision,mutation:.createProject(id:"stale",name:"stale"))}
}
@Test func offlineDeliveredResultIsNotApprovalAndOldResultCannotBeApproved() async throws {
 let(root,repository)=try offlineFixture();defer{try? FileManager.default.removeItem(at:root)}
 var state=try await seedOffline(repository)
 let anchor=OfflineAnchor(versionID:"version",startMs:1000,endMs:2000,annotation:Annotation(type:"rectangle",x:0.2,y:0.2,x2:0.5,y2:0.5))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.createRequest(id:"r",artifactID:"artifact",anchor:anchor,body:"합성",supersedesID:nil))
 await #expect(throws:OfflineError.self){try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.appendEvent(id:"r",kind:.decisionApprove,body:"cannot approve",resultVersionID:"version",resultEventID:nil,expectedRevision:0))}
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.appendEvent(id:"r",kind:.proposal,body:"직접 기록한 미검증 제안",resultVersionID:nil,resultEventID:nil,expectedRevision:0))
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.appendEvent(id:"r",kind:.result,body:"직접 기록한 결과",resultVersionID:"version",resultEventID:nil,expectedRevision:1))
 let first=try #require(state.requests.first?.currentResultEventID)
 #expect(state.requests.first?.approvedResultEventID==nil)
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.appendEvent(id:"r",kind:.decisionApprove,body:"이 결과에 대한 로컬 결정",resultVersionID:"version",resultEventID:first,expectedRevision:2))
 #expect(state.requests.first?.approvedResultEventID==first)
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.appendEvent(id:"r",kind:.result,body:"새 결과",resultVersionID:"version",resultEventID:nil,expectedRevision:3))
 #expect(state.requests.first?.approvedResultEventID==nil)
 await #expect(throws:OfflineError.self){try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.appendEvent(id:"r",kind:.decisionApprove,body:"old result",resultVersionID:"version",resultEventID:first,expectedRevision:4))}
 #expect(state.events.filter{$0.kind == .decisionApprove}.count==1)
}
@Test func offlineCorruptPrimaryRequiresExplicitLastGoodRecovery() async throws {
 let(root,repository)=try offlineFixture();defer{try? FileManager.default.removeItem(at:root)}
 let prior=try await seedOffline(repository)
 _ = try await repository.transact(expectedWorkspaceRevision:prior.revision,mutation:.createProject(id:"last",name:"마지막 변경"))
 try Data("malformed".utf8).write(to:root.appendingPathComponent("workspace.json"))
 await #expect(throws:OfflineError.self){try await repository.load()}
 let recovered=try await repository.recoverBackup()
 #expect(recovered==prior)
 let retained=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("workspace.retained-")}
 #expect(retained.count==1)
 #expect(try Data(contentsOf:retained[0])==Data("malformed".utf8))
 #expect(try await OfflineRepository(directory:root).load()==prior)
}
@Test func offlineCrossArtifactAnchorAndVersionMutationAreRejected() async throws {
 let(root,repository)=try offlineFixture();defer{try? FileManager.default.removeItem(at:root)}
 var state=try await seedOffline(repository)
 state=try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.createArtifact(id:"other",projectID:"project",name:"다른 작업물"))
 let anchor=OfflineAnchor(versionID:"version",startMs:0,endMs:1000,annotation:Annotation(type:"point",x:0.5,y:0.5))
 await #expect(throws:OfflineError.self){try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.createRequest(id:"wrong",artifactID:"other",anchor:anchor,body:"wrong",supersedesID:nil))}
 await #expect(throws:OfflineError.self){try await repository.transact(expectedWorkspaceRevision:state.revision,mutation:.registerVersion(OfflineVersion(id:"version",artifactID:"other",fingerprint:String(repeating:"1",count:64),byteCount:100,durationMs:12000,sourceLocator:"/synthetic/other.mp4")))}
 #expect(try await repository.load()==state)
}
