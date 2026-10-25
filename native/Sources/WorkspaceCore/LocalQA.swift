import Foundation
import Darwin

public enum LocalQAError: Error, LocalizedError {
 case invalid(String)
 public var errorDescription:String? { if case let .invalid(message)=self{return message};return nil }
}
public struct LocalQARequest: Codable,Equatable {
 public let schemaVersion:Int,id:String,nonce:String,kind:String,author:String,createdAt:String,revision:Int
}
public struct LocalQAReply: Codable,Equatable {
 public let schemaVersion:Int,requestId:String,nonce:String,operationKey:String,expectedRevision:Int,body:String,createdAt:String,roleClaim:String,source:String
}
public struct LocalQARecord: Codable,Equatable {
 public let request:LocalQARequest
 public let reply:LocalQAReply?
}
/// Isolated QA data exchange. Local author labels are claims, not authenticated host identity.
public final class LocalQAStore {
 public let directory:URL
 public init(directory:URL) throws {
  let root=directory.standardizedFileURL
  guard root.isFileURL,root.path==root.resolvingSymlinksInPath().path,
   (try? FileManager.default.attributesOfItem(atPath:root.path)[.type] as? FileAttributeType) == .typeDirectory else {throw LocalQAError.invalid("QA 폴더를 확인해 주세요.")}
  self.directory=root
 }
 private func uuid(_ value:String) throws {
  guard UUID(uuidString:value)?.uuidString.lowercased()==value else {throw LocalQAError.invalid("UUID 형식이 아닙니다.")}
 }
 private func locked<T>(_ work:() throws ->T) throws ->T {
  // Recheck the root before every access. No links are followed for the lock or records.
  guard directory.path==directory.resolvingSymlinksInPath().path else {throw LocalQAError.invalid("QA 폴더 링크는 사용할 수 없습니다.")}
  let fd=open(directory.appendingPathComponent(".qa.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
  guard fd>=0 else {throw LocalQAError.invalid("QA 잠금 파일을 열지 못했습니다.")}
  defer{close(fd)}
  var info=stat();guard fstat(fd,&info)==0,info.st_mode & S_IFMT == S_IFREG,flock(fd,LOCK_EX)==0 else {throw LocalQAError.invalid("QA 파일 잠금에 실패했습니다.")}
  defer{flock(fd,LOCK_UN)}
  return try work()
 }
 private func data(_ name:String,optional:Bool=false) throws ->Data? {
  let fd=open(directory.appendingPathComponent(name).path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
  if fd<0 {if optional && errno==ENOENT{return nil};throw LocalQAError.invalid("QA 파일을 안전하게 열지 못했습니다.")}
  let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
  var info=stat();guard fstat(fd,&info)==0,info.st_mode & S_IFMT == S_IFREG,info.st_size<=16384 else {throw LocalQAError.invalid("QA 파일 형식이나 크기를 확인해 주세요.")}
  let bytes=try handle.read(upToCount:16385) ?? Data()
  guard bytes.count<=16384 else {throw LocalQAError.invalid("QA 파일이 너무 큽니다.")}
  return bytes
 }
 private func write<T:Encodable>(_ value:T,name:String) throws {
  let target=directory.appendingPathComponent(name)
  var existing=stat();guard lstat(target.path,&existing) != 0,errno==ENOENT else {throw LocalQAError.invalid("이미 저장된 QA 파일은 바꿀 수 없습니다.")}
  let temporary=directory.appendingPathComponent("."+UUID().uuidString+".tmp")
  let fd=open(temporary.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0o600)
  guard fd>=0 else {throw LocalQAError.invalid("QA 임시 파일을 만들지 못했습니다.")}
  defer{close(fd);try? FileManager.default.removeItem(at:temporary)}
  let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
  let bytes=try encoder.encode(value);guard bytes.count<=16384 else {throw LocalQAError.invalid("QA 파일이 너무 큽니다.")}
  try FileHandle(fileDescriptor:fd,closeOnDealloc:false).write(contentsOf:bytes)
  guard fsync(fd)==0,rename(temporary.path,target.path)==0 else {throw LocalQAError.invalid("QA 파일을 저장하지 못했습니다.")}
  let rootfd=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if rootfd>=0{_ = fsync(rootfd);close(rootfd)}
 }
 private func readUnlocked(_ id:String) throws ->LocalQARecord {
  try uuid(id)
  do {
   let request=try JSONDecoder().decode(LocalQARequest.self,from:try data(id+".request.json")!)
   try uuid(request.nonce)
   guard request.schemaVersion==1,request.id==id,request.kind=="qa_request",request.author=="DAL_QA",request.revision==0,ISO8601DateFormatter().date(from:request.createdAt) != nil else {throw LocalQAError.invalid("QA 요청이 일치하지 않습니다.")}
   var reply:LocalQAReply?
   if let raw=try data(id+".reply.json",optional:true){
    let value=try JSONDecoder().decode(LocalQAReply.self,from:raw);try uuid(value.operationKey)
    guard value.schemaVersion==1,value.requestId==id,value.nonce==request.nonce,value.expectedRevision==0,value.roleClaim=="dot",value.source=="selected_mac_executor",!value.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,value.body.utf8.count<=4096,ISO8601DateFormatter().date(from:value.createdAt) != nil else {throw LocalQAError.invalid("QA 답변이 요청과 일치하지 않습니다.")};reply=value
   }
   return LocalQARecord(request:request,reply:reply)
  }catch let error as LocalQAError{throw error}catch{throw LocalQAError.invalid("QA JSON 형식이 올바르지 않습니다.")}
 }
 public func createRequest() throws ->LocalQARequest {
  try locked {
   let request=LocalQARequest(schemaVersion:1,id:UUID().uuidString.lowercased(),nonce:UUID().uuidString.lowercased(),kind:"qa_request",author:"DAL_QA",createdAt:ISO8601DateFormatter().string(from:Date()),revision:0)
   try write(request,name:request.id+".request.json");return request
  }
 }
 public func read(_ id:String) throws ->LocalQARecord {try locked{try readUnlocked(id)}}
 public func latest() throws ->LocalQARecord? {
  try locked {
   let ids=try FileManager.default.contentsOfDirectory(atPath:directory.path).filter{$0.hasSuffix(".request.json")}.map{String($0.dropLast(13))}
   let records=try ids.map{try readUnlocked($0)}
   return records.sorted{if $0.request.createdAt==$1.request.createdAt{return $0.request.id>$1.request.id};return $0.request.createdAt>$1.request.createdAt}.first
  }
 }
 public func reply(id:String,nonce:String,expectedRevision:Int,operationKey:String,body:String) throws ->LocalQAReply {
  try locked {
   try uuid(operationKey);let record=try readUnlocked(id)
   guard nonce==record.request.nonce,expectedRevision==0,!body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,body.utf8.count<=4096 else {throw LocalQAError.invalid("nonce, revision 또는 답변 내용을 확인해 주세요.")}
   if let old=record.reply{
    guard old.operationKey==operationKey,old.body==body else{throw LocalQAError.invalid("이미 다른 QA 답변이 저장되었습니다.")};return old
   }
   let result=LocalQAReply(schemaVersion:1,requestId:id,nonce:nonce,operationKey:operationKey,expectedRevision:expectedRevision,body:body,createdAt:ISO8601DateFormatter().string(from:Date()),roleClaim:"dot",source:"selected_mac_executor")
   try write(result,name:id+".reply.json");return result
  }
 }
}
