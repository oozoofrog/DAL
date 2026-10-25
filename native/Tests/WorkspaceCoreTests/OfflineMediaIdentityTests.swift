import Foundation
import Testing
@testable import WorkspaceCore

@Test func offlineMediaFullFingerprintRejectsLinksAndChangedBytes() throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
 let file=root.appendingPathComponent("같은 이름.mp4");try Data("abc".utf8).write(to:file)
 let first=try OfflineMediaIdentity.hashFile(file)
 #expect(first.sha256=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
 try Data("abd".utf8).write(to:file)
 #expect(try OfflineMediaIdentity.hashFile(file).sha256 != first.sha256)
 let link=root.appendingPathComponent("link.mp4");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
 #expect(throws:OfflineError.self){try OfflineMediaIdentity.hashFile(link)}
}
@Test(.enabled(if:ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func offlineRealMediaMatchingMissingMismatchAndCancellation() async throws {
 let source=URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"]))
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
 let file=root.appendingPathComponent("한글 영상.mp4");try FileManager.default.copyItem(at:source,to:file)
 let expected=try await OfflineMediaIdentity.inspect(file)
 #expect(expected.durationMs>0)
 #expect(await OfflineMediaIdentity.verify(file,expected:expected) == .matching)
 try Data("changed bytes".utf8).write(to:file)
 #expect(await OfflineMediaIdentity.verify(file,expected:expected) == .mismatched)
 try FileManager.default.removeItem(at:file)
 #expect(await OfflineMediaIdentity.verify(file,expected:expected) == .missing)
 let cancelled=Task{try await OfflineMediaIdentity.inspect(source)};cancelled.cancel()
 await #expect(throws:CancellationError.self){try await cancelled.value}
}
