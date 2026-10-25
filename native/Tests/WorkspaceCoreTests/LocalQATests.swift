import Foundation
import Testing
@testable import WorkspaceCore

private func qaFixture() throws -> (URL, LocalQAStore) {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
 return (root,try LocalQAStore(directory:root))
}
@Test func localQARequestAndManualReloadAreDurable() throws {
 let (root,store)=try qaFixture();defer{try? FileManager.default.removeItem(at:root)}
 let request=try store.createRequest()
 #expect(request.kind=="qa_request")
 #expect(request.author=="DAL_QA")
 #expect(request.revision==0)
 #expect(try store.read(request.id).reply==nil)
 let reopened=try LocalQAStore(directory:root)
 #expect(try reopened.read(request.id).request==request)
}
@Test func localQAReplyValidatesNonceRevisionAndReplay() throws {
 let (root,store)=try qaFixture();defer{try? FileManager.default.removeItem(at:root)}
 let request=try store.createRequest();let operation=UUID().uuidString.lowercased()
 #expect(throws:LocalQAError.self){try store.reply(id:request.id,nonce:"wrong",expectedRevision:0,operationKey:operation,body:"synthetic test reply")}
 #expect(throws:LocalQAError.self){try store.reply(id:request.id,nonce:request.nonce,expectedRevision:1,operationKey:operation,body:"synthetic test reply")}
 let reply=try store.reply(id:request.id,nonce:request.nonce,expectedRevision:0,operationKey:operation,body:"synthetic test reply")
 #expect(try store.reply(id:request.id,nonce:request.nonce,expectedRevision:0,operationKey:operation,body:"synthetic test reply")==reply)
 #expect(throws:LocalQAError.self){try store.reply(id:request.id,nonce:request.nonce,expectedRevision:0,operationKey:operation,body:"changed")}
 #expect(throws:LocalQAError.self){try store.reply(id:request.id,nonce:request.nonce,expectedRevision:0,operationKey:UUID().uuidString.lowercased(),body:"other operation")}
 #expect(try LocalQAStore(directory:root).read(request.id).reply==reply)
}
@Test func localQARejectsMalformedPathsSymlinksAndOversizedRecords() throws {
 let (root,store)=try qaFixture();defer{try? FileManager.default.removeItem(at:root)}
 #expect(throws:LocalQAError.self){try store.read("../outside")}
 let id=UUID().uuidString.lowercased()
 let file=root.appendingPathComponent(id+".request.json")
 try FileManager.default.createSymbolicLink(at:file,withDestinationURL:URL(fileURLWithPath:"/etc/hosts"))
 #expect(throws:LocalQAError.self){try store.read(id)}
 try FileManager.default.removeItem(at:file)
 try Data(repeating:65,count:20000).write(to:file)
 #expect(throws:LocalQAError.self){try store.read(id)}
 try Data("{}".utf8).write(to:file)
 #expect(throws:LocalQAError.self){try store.read(id)}
 let request=try store.createRequest()
 #expect(throws:LocalQAError.self){try store.reply(id:request.id,nonce:request.nonce,expectedRevision:0,operationKey:UUID().uuidString.lowercased(),body:String(repeating:"x",count:5000))}
}
@Test func localQADataCommandIsStrictAndReturnsOnlyScopedRecord() throws {
 let (root,store)=try qaFixture();defer{try? FileManager.default.removeItem(at:root)}
 let request=try store.createRequest()
 let args=["read","--directory",root.path,"--request",request.id]
 let raw=try LocalQACommand.run(arguments:args,input:{Data()})
 #expect(try JSONDecoder().decode(LocalQARecord.self,from:Data(raw.utf8)).request==request)
 #expect(throws:LocalQAError.self){try LocalQACommand.run(arguments:args+["--unknown","x"],input:{Data()})}
 #expect(throws:LocalQAError.self){try LocalQACommand.run(arguments:["create","--directory",root.path],input:{Data()})}
 let replyArgs=["reply","--directory",root.path,"--request",request.id,"--nonce",request.nonce,"--expected-revision","0","--operation-key",UUID().uuidString.lowercased(),"--body-stdin"]
 let reply=try LocalQACommand.run(arguments:replyArgs,input:{Data("synthetic unit reply".utf8)})
 #expect(try JSONDecoder().decode(LocalQAReply.self,from:Data(reply.utf8)).body=="synthetic unit reply")
}
@Test func localQAStdinDrainsMultipleWritesIncludingSplitUTF8() throws {
 let pipe=Pipe();let complete=Data("안녕하세요. parent-authored pipe body\n끝".utf8);let group=DispatchGroup();group.enter()
 DispatchQueue.global().async {
  defer{try? pipe.fileHandleForWriting.close();group.leave()}
  try? pipe.fileHandleForWriting.write(contentsOf:complete.prefix(1))
  Thread.sleep(forTimeInterval:0.03)
  try? pipe.fileHandleForWriting.write(contentsOf:complete.dropFirst(1).prefix(2))
  Thread.sleep(forTimeInterval:0.03)
  try? pipe.fileHandleForWriting.write(contentsOf:complete.dropFirst(3))
 }
 let received=try LocalQACommand.readInput(pipe.fileHandleForReading);group.wait()
 #expect(received==complete)
 #expect(String(data:received,encoding:.utf8)==String(data:complete,encoding:.utf8))
}
@Test func localQAStdinRejectsCumulativeOversizeBeforeReplyPersistence() throws {
 let pipe=Pipe();let group=DispatchGroup();group.enter()
 DispatchQueue.global().async {
  defer{try? pipe.fileHandleForWriting.close();group.leave()}
  try? pipe.fileHandleForWriting.write(contentsOf:Data(repeating:65,count:2048))
  Thread.sleep(forTimeInterval:0.03)
  try? pipe.fileHandleForWriting.write(contentsOf:Data(repeating:66,count:2049))
 }
 let (root,store)=try qaFixture();defer{try? FileManager.default.removeItem(at:root)}
 let request=try store.createRequest()
 let args=["reply","--directory",root.path,"--request",request.id,"--nonce",request.nonce,"--expected-revision","0","--operation-key",UUID().uuidString.lowercased(),"--body-stdin"]
 #expect(throws:LocalQAError.self){try LocalQACommand.run(arguments:args,input:{try LocalQACommand.readInput(pipe.fileHandleForReading)})}
 group.wait()
 #expect(try store.read(request.id).reply==nil)
}
