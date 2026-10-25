import Foundation
import Testing
import WorkspaceCore
@testable import DotWorkspace

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineNativeCreateSelectSaveAndReload() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath();defer{try? FileManager.default.removeItem(at:root)}
 let store=try OfflineWorkspaceStore(directory:root)
 await store.load();await store.createProject(name:"DAL_TEST_FIXTURE 프로젝트")
 await store.importVideo(URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"])),asNewArtifact:true)
 let version=try #require(store.version)
 let anchor=OfflineAnchor(versionID:version.id,startMs:1000,endMs:2000,annotation:Annotation(type:"point",x:0.4,y:0.5))
 await store.createRequest(anchor:anchor,body:"DAL_TEST_FIXTURE 메모")
 let request=try #require(store.request)
 store.selectRequest(request.id)
 await store.verifySelectedMedia()
 #expect(store.canUseVerifiedSource)
 await store.saveText(id:request.id,body:"DAL_TEST_FIXTURE 수정 메모",expectedRevision:request.revision)
 #expect(store.error==nil)
 await store.importVideo(URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"])),asNewArtifact:false)
 store.selectedVersionID = version.id
 #expect(!store.canUseVerifiedSource)
 await store.verifySelectedMedia()
 #expect(store.canUseVerifiedSource)
 let reopened=try OfflineWorkspaceStore(directory:root);await reopened.load();reopened.selectRequest(request.id)
 #expect(reopened.request?.anchor==anchor)
 #expect(reopened.request?.body=="DAL_TEST_FIXTURE 수정 메모")
 #expect(reopened.snapshot.events.count==2)
}
@MainActor @Test func offlineEmptyArtifactNeverInheritsPriorSelection() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath();defer{try? FileManager.default.removeItem(at:root)}
 let store=try OfflineWorkspaceStore(directory:root);await store.load();await store.createProject(name:"첫 프로젝트")
 let first=try #require(store.project?.id)
 await store.createProject(name:"빈 프로젝트")
 #expect(store.project?.id != first)
 #expect(store.version==nil)
 #expect(store.request==nil)
 #expect(!store.canUseVerifiedSource)
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineDecodedGeometryAndSameRequestReselectionGateMarks() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 let source=root.appendingPathComponent("source.mp4")
 try FileManager.default.copyItem(at:URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"])),to:source)
 let store=try OfflineWorkspaceStore(directory:root.appendingPathComponent("store"));await store.load();await store.createProject(name:"DAL_TEST_FIXTURE")
 await store.importVideo(source,asNewArtifact:true)
 let media=MediaController(),version=try #require(store.version)
 #expect(!store.canAnnotate(using:media))
 await store.prepareMedia(media)
 #expect(media.size.width>0 && media.size.height>0)
 #expect(store.canAnnotate(using:media))
 await store.createRequest(anchor:.init(versionID:version.id,startMs:0,endMs:1000,annotation:.init(type:"arrow",x:0.2,y:0.3,x2:0.7,y2:0.8)),body:"DAL_TEST_FIXTURE")
 let id=try #require(store.request?.id)
 store.selectRequest(id);#expect(!store.canAnnotate(using:media));await store.prepareMedia(media);#expect(store.canAnnotate(using:media))
 try FileManager.default.removeItem(at:source)
 store.selectRequest(id);#expect(!store.canAnnotate(using:media));await store.prepareMedia(media)
 #expect(media.player.currentItem==nil);#expect(media.duration==0);#expect(!store.canAnnotate(using:media))
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineComposerKeepsVersionOwnershipAndNewerSubmittedText() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
 let store=try OfflineWorkspaceStore(directory:root);await store.load();await store.createProject(name:"DAL_TEST_FIXTURE")
 let source=URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"]))
 await store.importVideo(source,asNewArtifact:true);let a=try #require(store.version)
 store.setComposerBody(a.id,body:"submitted A")
 await store.importVideo(source,asNewArtifact:false);let b=try #require(store.version)
 store.setComposerBody(b.id,body:"draft B");store.selectedVersionID=a.id
 #expect(store.composerBody(a.id)=="submitted A")
 let saving=Task { await store.createRequest(anchor:.init(versionID:a.id,startMs:0,endMs:1000,annotation:.init(type:"point",x:0.4,y:0.5)),body:"submitted A") }
 await Task.yield()
 store.setComposerBody(a.id,body:"newer A")
 await saving.value
 #expect(store.request?.body=="submitted A")
 #expect(store.composerBody(a.id)=="newer A");#expect(store.composerBody(b.id)=="draft B")
 do { try await store.flushPendingEdits();Issue.record("Unsaved composer must prevent silent quit") } catch {}
}

@MainActor private final class OfflineInspectionGate {
 var pending: CheckedContinuation<MediaFingerprint, Error>?
 func inspect(_ url: URL) async throws -> MediaFingerprint { try await withCheckedThrowingContinuation { pending=$0 } }
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineRelinkCompletionCannotMakeAnotherMissingVersionReady() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
 let initial=try OfflineWorkspaceStore(directory:root);await initial.load();await initial.createProject(name:"DAL_TEST_FIXTURE")
 let source=URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"]))
 await initial.importVideo(source,asNewArtifact:true);let a=try #require(initial.version)
 let missing=OfflineVersion(id:UUID().uuidString,artifactID:a.artifactID,fingerprint:a.fingerprint,byteCount:a.byteCount,durationMs:a.durationMs,sourceLocator:root.appendingPathComponent("missing.mp4").path)
 _=try await initial.repository.transact(expectedWorkspaceRevision:initial.snapshot.revision,mutation:.registerVersion(missing))
 let gate=OfflineInspectionGate(),store=try OfflineWorkspaceStore(directory:root,inspectMedia:gate.inspect)
 await store.load();store.selectedVersionID=a.id
 let relinking=Task { await store.relink(root.appendingPathComponent("replacement.mp4")) }
 while gate.pending == nil { await Task.yield() }
 store.selectedVersionID=missing.id;await store.verifySelectedMedia()
 gate.pending?.resume(returning:.init(sha256:a.fingerprint,byteCount:a.byteCount,durationMs:a.durationMs));gate.pending=nil
 await relinking.value
 #expect(store.version?.id==missing.id);#expect(store.availability == .missing)
 #expect(store.snapshot.versions.first(where:{$0.id==a.id})?.sourceLocator==a.sourceLocator)
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineSuccessfulRelinkStartsFreshDecodedMediaSelection() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 let source=URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"]))
 let copy=root.appendingPathComponent("same bytes.mp4");try FileManager.default.copyItem(at:source,to:copy)
 let store=try OfflineWorkspaceStore(directory:root.appendingPathComponent("store"));await store.load();await store.createProject(name:"DAL_TEST_FIXTURE");await store.importVideo(source,asNewArtifact:true)
 let gate=OfflineInspectionGate(),controlled=try OfflineWorkspaceStore(directory:root.appendingPathComponent("store"),inspectMedia:gate.inspect);await controlled.load()
 let v=try #require(controlled.version)
 let relinking=Task { await controlled.relink(copy) }
 while gate.pending == nil { await Task.yield() }
 let pendingSelection=controlled.mediaSelectionID
 gate.pending?.resume(returning:.init(sha256:v.fingerprint,byteCount:v.byteCount,durationMs:v.durationMs));gate.pending=nil
 await relinking.value
 #expect(controlled.mediaSelectionID != pendingSelection)
 let media=MediaController();await controlled.prepareMedia(media)
 #expect(controlled.canAnnotate(using:media));#expect(media.localURL==copy)
}
