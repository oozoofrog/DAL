import Foundation
import ImageIO
import Testing
import WorkspaceCore
@testable import DotWorkspace

@MainActor func exportNativeFixture() async throws -> (URL, OfflineWorkspaceStore) {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 let copy=root.appendingPathComponent("합성 시험 원본.mp4")
 try FileManager.default.copyItem(at:URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"])),to:copy)
 let store=try OfflineWorkspaceStore(directory:root.appendingPathComponent("store"));await store.load();await store.createProject(name:"DAL_TEST_FIXTURE")
 await store.importVideo(copy,asNewArtifact:true);let version=try #require(store.version)
 await store.createRequest(anchor:.init(versionID:version.id,startMs:1000,endMs:2000,annotation:.init(type:"rectangle",x:0.2,y:0.3,x2:0.6,y2:0.7)),body:"DAL_TEST_FIXTURE · <script>plain text</script>")
 #expect(store.error==nil);return (root,store)
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineCaptureUsesMatchedActualSourceAndRetainsRequestedActualTime() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let v=try #require(store.version),r=try #require(store.request)
 let captured=try await OfflineFrameExtractor.capture(version:v,request:r,requestedMs:1001)
 #expect(captured.requestID==r.id && captured.versionID==v.id && captured.sourceFingerprint==v.fingerprint)
 #expect(captured.requestedMs==1001);#expect(captured.actualMs.isFinite && captured.actualMs>=0 && captured.actualMs<Double(v.durationMs))
 let source=try #require(CGImageSourceCreateWithData(captured.png as CFData,nil));let image=try #require(CGImageSourceCreateImageAtIndex(source,0,nil))
 #expect(image.width==captured.pixelWidth && image.height==captured.pixelHeight);#expect(image.width>0 && image.height>0)
 #expect(await OfflineMediaIdentity.verify(URL(fileURLWithPath:v.sourceLocator),expected:.init(sha256:v.fingerprint,byteCount:v.byteCount,durationMs:v.durationMs)) == .matching)
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineCaptureRejectsSameNameChangedBytesMissingAndOutsideRange() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let v=try #require(store.version),r=try #require(store.request),url=URL(fileURLWithPath:v.sourceLocator)
 await #expect(throws:OfflineError.self){try await OfflineFrameExtractor.capture(version:v,request:r,requestedMs:2000)}
 let handle=try FileHandle(forWritingTo:url);try handle.seekToEnd();try handle.write(contentsOf:Data("changed bytes".utf8));try handle.close()
 await #expect(throws:OfflineError.self){try await OfflineFrameExtractor.capture(version:v,request:r,requestedMs:1000)}
 try FileManager.default.removeItem(at:url)
 await #expect(throws:OfflineError.self){try await OfflineFrameExtractor.capture(version:v,request:r,requestedMs:1000)}
 #expect(store.request?.anchor==r.anchor)
}
