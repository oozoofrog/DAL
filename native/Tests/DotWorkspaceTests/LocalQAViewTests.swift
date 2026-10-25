import Foundation
import Testing
import WorkspaceCore
@testable import DotWorkspace
@MainActor @Test func localQAPanelRefreshPersistsWithoutConnecting() throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
 let panel=QAProofModel(directory:root);let store=WorkspaceStore()
 panel.createRequest();let request=try #require(panel.record?.request)
 #expect(panel.record?.reply==nil)
 _ = try LocalQAStore(directory:root).reply(id:request.id,nonce:request.nonce,expectedRevision:0,operationKey:UUID().uuidString.lowercased(),body:"synthetic unit reply")
 #expect(panel.record?.reply==nil)
 panel.refresh();#expect(panel.record?.reply?.body=="synthetic unit reply")
 let reopened=QAProofModel(directory:root);#expect(reopened.record?.reply==panel.record?.reply)
 #expect(!store.connected)
}
