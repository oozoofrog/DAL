import Foundation
import Darwin
import Testing
import WorkspaceCore
@testable import DotWorkspace
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineExactPreviewBytesSaveAndIndependentZIPReadback() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let request=try #require(store.request),artifact=try #require(store.artifact)
 let frozen=try ExportSnapshot(workspace:store.snapshot,artifactID:artifact.id,selectedRequestIDs:[request.id])
 let coordinator=OfflineExportCoordinator(repository:store.repository,temporaryRoot:root.appendingPathComponent("staging"))
 let preview=try await coordinator.prepare(snapshot:frozen)
 let stagedBytes=try Data(contentsOf:preview.archiveURL);#expect(preview.exactByteCount==stagedBytes.count)
 #expect(preview.entries.map(\.path)==["review.html","images/001-01.png","images/001-02.png","manifest.json"])
 let destination=root.appendingPathComponent("선택 메모.zip")
 let receipt=try await coordinator.commit(preview:preview,destination:destination)
 let bytes=try Data(contentsOf:destination);#expect(bytes.count==preview.exactByteCount);#expect(exportSHA256(bytes)==preview.archiveSHA256);#expect(receipt.byteCount==bytes.count)
 let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/env");process.arguments=["python3","-c","import zipfile,json,hashlib,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; m=json.loads(z.read('manifest.json')); assert len(m['requests'])==1; assert len(m['images'])==2; assert set(z.namelist())=={'review.html','images/001-01.png','images/001-02.png','manifest.json'}; assert all(hashlib.sha256(z.read(e['path'])).hexdigest()==e['sha256'] for e in m['entries']); assert b'<script>' not in z.read('review.html')",destination.path];try process.run();process.waitUntilExit();#expect(process.terminationStatus==0)
 #expect(try await store.repository.load()==store.snapshot)
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineStalePreviewCancelAndSaveFailurePreserveNotesAndDestination() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let r=try #require(store.request),a=try #require(store.artifact)
 let coordinator=OfflineExportCoordinator(repository:store.repository,temporaryRoot:root.appendingPathComponent("staging"))
 let snapshot=try ExportSnapshot(workspace:store.snapshot,artifactID:a.id,selectedRequestIDs:[r.id]);let preview=try await coordinator.prepare(snapshot:snapshot)
 let destination=root.appendingPathComponent("unchanged.zip");let prior=Data("existing user file".utf8);try prior.write(to:destination)
 await #expect(throws:OfflineError.self){try await coordinator.commit(preview:preview,destination:destination)}
 #expect(try Data(contentsOf:destination)==prior)
 await store.saveText(id:r.id,body:"DAL_TEST_FIXTURE changed after preview",expectedRevision:r.revision)
 await #expect(throws:OfflineError.self){try await coordinator.commit(preview:preview,destination:root.appendingPathComponent("stale.zip"))}
 #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("stale.zip").path))
 coordinator.cancel(preview:preview)
 #expect(!FileManager.default.fileExists(atPath:preview.archiveURL.path))
 await #expect(throws:OfflineError.self){try await coordinator.commit(preview:preview,destination:root.appendingPathComponent("cancelled.zip"))}
 #expect(try await store.repository.load()==store.snapshot);#expect(try Data(contentsOf:destination)==prior)
 let latest=try ExportSnapshot(workspace:store.snapshot,artifactID:a.id,selectedRequestIDs:[r.id])
 let cancelled=Task {try await coordinator.prepare(snapshot:latest)};cancelled.cancel()
 await #expect(throws:CancellationError.self){try await cancelled.value}
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlinePreviewChangedSourceAndLinkedArchiveCannotBeSaved() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let r=try #require(store.request),a=try #require(store.artifact),v=try #require(store.version)
 let coordinator=OfflineExportCoordinator(repository:store.repository,temporaryRoot:root.appendingPathComponent("staging"))
 let snapshot=try ExportSnapshot(workspace:store.snapshot,artifactID:a.id,selectedRequestIDs:[r.id]);let preview=try await coordinator.prepare(snapshot:snapshot)
 let secret=root.appendingPathComponent("unselected-private.txt");try Data("never include this file".utf8).write(to:secret)
 try FileManager.default.removeItem(at:preview.archiveURL);try FileManager.default.createSymbolicLink(at:preview.archiveURL,withDestinationURL:secret)
 let destination=root.appendingPathComponent("linked.zip")
 await #expect(throws:OfflineError.self){try await coordinator.commit(preview:preview,destination:destination)}
 #expect(!FileManager.default.fileExists(atPath:destination.path));coordinator.cancel(preview:preview)
 #expect(try String(contentsOf:secret,encoding:.utf8)=="never include this file")
 let second=try await coordinator.prepare(snapshot:snapshot)
 let source=try FileHandle(forWritingTo:URL(fileURLWithPath:v.sourceLocator));try source.seekToEnd();try source.write(contentsOf:Data("source changed after preview".utf8));try source.close()
 await #expect(throws:OfflineError.self){try await coordinator.commit(preview:second,destination:destination)}
 #expect(!FileManager.default.fileExists(atPath:destination.path));#expect(try await store.repository.load()==store.snapshot);coordinator.cancel(preview:second)
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineFailedDestinationCanRetryExactPreparedBytes() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let r=try #require(store.request),a=try #require(store.artifact)
 let coordinator=OfflineExportCoordinator(repository:store.repository,temporaryRoot:root.appendingPathComponent("staging"))
 let preview=try await coordinator.prepare(snapshot:ExportSnapshot(workspace:store.snapshot,artifactID:a.id,selectedRequestIDs:[r.id]))
 let impossible=root.appendingPathComponent("not-created/output.zip")
 await #expect(throws:OfflineError.self){try await coordinator.commit(preview:preview,destination:impossible)}
 #expect(!FileManager.default.fileExists(atPath:impossible.path));#expect(FileManager.default.fileExists(atPath:preview.archiveURL.path))
 let output=root.appendingPathComponent("retry.zip"),receipt=try await coordinator.commit(preview:preview,destination:output)
 #expect(receipt.archiveSHA256==preview.archiveSHA256);#expect(exportSHA256(try Data(contentsOf:output))==preview.archiveSHA256)
 #expect(try await store.repository.load()==store.snapshot)
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineTargetAppearingDuringValidationIsNeverOverwritten() async throws {
 let(root,store)=try await exportNativeFixture();defer{try? FileManager.default.removeItem(at:root)}
 let r=try #require(store.request),a=try #require(store.artifact)
 let coordinator=OfflineExportCoordinator(repository:store.repository,temporaryRoot:root.appendingPathComponent("staging"))
 let preview=try await coordinator.prepare(snapshot:ExportSnapshot(workspace:store.snapshot,artifactID:a.id,selectedRequestIDs:[r.id]))
 let destination=root.appendingPathComponent("new-file-only.zip")
 let approval=try coordinator.approveNewDestination(preview:preview,destination:destination)
 // Real repository contention holds asynchronous validation; no fake or slowed media.
 let lock=open(root.appendingPathComponent("store/.workspace.lock").path,O_RDWR)
 #expect(lock>=0);#expect(flock(lock,LOCK_EX)==0);defer{flock(lock,LOCK_UN);close(lock)}
 var entered=false
 let pending=Task { @MainActor () -> Result<ExportReceipt,Error> in
  entered=true
  do{return .success(try await coordinator.commit(preview:preview,destination:destination,approval:approval))}catch{return .failure(error)}
 }
 while !entered {await Task.yield()}
 let newcomer=Data("unconfirmed file created while validation awaits".utf8);try newcomer.write(to:destination)
 flock(lock,LOCK_UN)
 let result=await pending.value
 if case .success=result {Issue.record("A post-confirmation newcomer must never be replaced")}
 #expect(try Data(contentsOf:destination)==newcomer)
 coordinator.cancel(preview:preview)
}
