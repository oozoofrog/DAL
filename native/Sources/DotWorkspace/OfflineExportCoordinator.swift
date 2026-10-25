import Foundation
import Darwin
import WorkspaceCore

struct ExportPreview {
 let operationID:UUID
 let snapshot:ExportSnapshot
 let captures:[AnnotatedCapture]
 let entries:[GeneratedEntry]
 let archiveURL:URL
 let exactByteCount:Int
 let archiveSHA256:String
}
struct ExportDestinationApproval: Equatable { fileprivate let id:UUID; fileprivate let operationID:UUID; fileprivate let destination:URL }
struct ExportReceipt { let exportID:String;let byteCount:Int;let archiveSHA256:String;let savedAt:Date }
@MainActor final class OfflineExportCoordinator {
 private struct Operation { let preview:ExportPreview;let directory:URL;let device:dev_t;let inode:ino_t }
 private let repository:OfflineRepository
 private let temporaryRoot:URL
 private var operations:[UUID:Operation]=[:]
 private var approvals:[UUID:ExportDestinationApproval]=[:]
 init(repository:OfflineRepository,temporaryRoot:URL=FileManager.default.temporaryDirectory.appendingPathComponent("DAL-Exports")) {
  self.repository=repository;self.temporaryRoot=temporaryRoot.resolvingSymlinksInPath()
 }
 private func verify(_ snapshot:ExportSnapshot) async throws {
  try Task.checkCancellation()
  guard snapshot.isCurrent(in:try await repository.load()) else { throw OfflineError.invalid("선택한 메모가 바뀌었어요. 새로 미리 보기를 만들어 주세요.") }
  for v in snapshot.versions {
   try Task.checkCancellation()
   guard await OfflineMediaIdentity.verify(URL(fileURLWithPath:v.sourceLocator),expected:.init(sha256:v.fingerprint,byteCount:v.byteCount,durationMs:v.durationMs)) == .matching else { throw OfflineError.invalid("원본이 없거나 내용이 달라졌어요. 같은 원본을 확인한 뒤 다시 준비해 주세요.") }
  }
  try Task.checkCancellation()
  guard snapshot.isCurrent(in:try await repository.load()) else { throw OfflineError.invalid("준비 중 메모가 바뀌었어요. 새로 미리 보기를 만들어 주세요.") }
 }
 func prepare(snapshot:ExportSnapshot) async throws -> ExportPreview {
  try await verify(snapshot)
  let id=UUID(),directory=temporaryRoot.appendingPathComponent(id.uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:temporaryRoot,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
  var retained=false
  defer { if !retained { try? FileManager.default.removeItem(at:directory) } }
  var captures:[AnnotatedCapture]=[]
  for request in snapshot.requests {
   guard let version=snapshot.versions.first(where:{$0.id==request.anchor.versionID}) else { throw OfflineError.invalid("원본 버전이 없습니다.") }
   for time in snapshot.captureTimes(for:request.id) {
    try Task.checkCancellation()
    captures.append(try await OfflineFrameExtractor.capture(version:version,request:request,requestedMs:time))
   }
  }
  try await verify(snapshot)
  let entries=try OfflineReportRenderer.render(snapshot:snapshot,captures:captures),archive=try OfflineZIPWriter.archive(entries:entries)
  try Task.checkCancellation()
  let url=directory.appendingPathComponent("bundle.zip")
  let fd=open(url.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
  guard fd>=0 else { throw OfflineError.io("임시 묶음을 만들지 못했어요.") }
  let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
  try handle.write(contentsOf:archive);guard fsync(fd)==0 else { throw OfflineError.io("임시 묶음을 저장하지 못했어요.") };try handle.close()
  try await verify(snapshot)
  var info=stat();guard lstat(directory.path,&info)==0,info.st_mode&S_IFMT==S_IFDIR else { throw OfflineError.io("임시 폴더를 확인하지 못했어요.") }
  let preview=ExportPreview(operationID:id,snapshot:snapshot,captures:captures,entries:entries,archiveURL:url,exactByteCount:archive.count,archiveSHA256:exportSHA256(archive))
  operations[id]=Operation(preview:preview,directory:directory,device:info.st_dev,inode:info.st_ino);retained=true
  return preview
 }
 private func readArchive(_ operation:Operation) throws -> Data {
  let dir=open(operation.directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard dir>=0 else { throw OfflineError.io("준비한 묶음 폴더를 열지 못했어요.") };defer{close(dir)}
  var folder=stat();guard fstat(dir,&folder)==0,folder.st_dev==operation.device,folder.st_ino==operation.inode else { throw OfflineError.io("준비한 묶음 폴더가 달라졌어요.") }
  let fd=openat(dir,"bundle.zip",O_RDONLY|O_NOFOLLOW|O_NONBLOCK);guard fd>=0 else { throw OfflineError.io("준비한 묶음을 안전하게 열지 못했어요.") }
  let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
  var info=stat();guard fstat(fd,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_size==operation.preview.exactByteCount else { throw OfflineError.io("준비한 묶음 크기가 달라졌어요.") }
  let data=try handle.readToEnd() ?? Data();try handle.close()
  guard data.count==operation.preview.exactByteCount,exportSHA256(data)==operation.preview.archiveSHA256 else { throw OfflineError.io("미리 본 묶음과 내용이 달라 저장하지 않았어요.") }
  return data
 }
 private func fileIdentity(_ url:URL) throws -> String? {
  var info=stat()
  if lstat(url.path,&info) != 0 { if errno==ENOENT { return nil };throw OfflineError.io("저장 위치를 확인하지 못했어요.") }
  guard info.st_mode&S_IFMT==S_IFREG else { throw OfflineError.invalid("일반 ZIP 파일로 저장할 위치를 선택해 주세요.") }
  return "\(info.st_dev)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec)|\(info.st_ctimespec.tv_nsec)"
 }
 func approveNewDestination(preview:ExportPreview,destination:URL) throws -> ExportDestinationApproval {
  guard operations[preview.operationID] != nil,destination.isFileURL else { throw OfflineError.invalid("끝난 미리 보기예요. 다시 준비해 주세요.") }
  guard try fileIdentity(destination)==nil else { throw OfflineError.invalid("같은 이름의 파일이 있어요. 다른 이름을 선택해 주세요.") }
  let approval=ExportDestinationApproval(id:UUID(),operationID:preview.operationID,destination:destination.standardizedFileURL)
  approvals[approval.id]=approval
  return approval
 }
 func commit(preview:ExportPreview,destination:URL,approval:ExportDestinationApproval?=nil) async throws -> ExportReceipt {
  guard let operation=operations[preview.operationID],destination.isFileURL else { throw OfflineError.invalid("취소되었거나 끝난 미리 보기예요. 다시 준비해 주세요.") }
  // Capture the new-file decision before the first suspension; never accept a post-await newcomer.
  let decision=try approval ?? approveNewDestination(preview:preview,destination:destination)
  guard approvals[decision.id]==decision,decision.operationID==preview.operationID,decision.destination==destination.standardizedFileURL else { throw OfflineError.invalid("저장 위치를 다시 확인해 주세요.") }
  guard try fileIdentity(destination)==nil else { throw OfflineError.invalid("같은 이름의 파일이 생겼어요. 다른 이름을 선택해 주세요.") }
  let owned=operation.preview
  try await verify(owned.snapshot)
  let bytes=try readArchive(operation)
  let parent=destination.deletingLastPathComponent(),temporary=parent.appendingPathComponent(".DAL-export-\(UUID().uuidString).tmp")
  let fd=open(temporary.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
  guard fd>=0 else { throw OfflineError.io("선택한 위치에 저장하지 못했어요. 다른 위치를 선택해 주세요.") }
  defer{try? FileManager.default.removeItem(at:temporary)}
  let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
  try handle.write(contentsOf:bytes);guard fsync(fd)==0 else { throw OfflineError.io("묶음을 안전하게 저장하지 못했어요.") };try handle.close()
  try await verify(owned.snapshot)
  guard operations[preview.operationID] != nil,try fileIdentity(destination)==nil else { throw OfflineError.invalid("저장 위치에 파일이 생겼어요. 다른 이름을 선택해 주세요.") }
  try Task.checkCancellation()
  guard renamex_np(temporary.path,destination.path,UInt32(RENAME_EXCL))==0 else { throw OfflineError.io("같은 이름의 파일이 생겼거나 저장 위치를 사용할 수 없어요. 다른 이름이나 위치를 선택해 주세요.") }
  let directoryFD=open(parent.path,O_RDONLY|O_DIRECTORY)
  guard directoryFD>=0 else { throw OfflineError.io("ZIP은 생성됐지만 저장 완료를 확인하지 못했어요. 파일을 확인한 뒤 다시 시도해 주세요.") }
  let directorySynced=fsync(directoryFD)==0;close(directoryFD)
  guard directorySynced else { throw OfflineError.io("ZIP은 생성됐지만 저장 완료를 확인하지 못했어요. 파일을 확인한 뒤 다시 시도해 주세요.") }
  let receipt=ExportReceipt(exportID:owned.snapshot.exportID,byteCount:bytes.count,archiveSHA256:owned.archiveSHA256,savedAt:Date())
  cancel(preview:owned)
  return receipt
 }
 func cancel(preview:ExportPreview) {
  guard let operation=operations.removeValue(forKey:preview.operationID) else { return }
  approvals=approvals.filter{$0.value.operationID != preview.operationID}
  var info=stat()
  if lstat(operation.directory.path,&info)==0,info.st_mode&S_IFMT==S_IFDIR,info.st_dev==operation.device,info.st_ino==operation.inode { try? FileManager.default.removeItem(at:operation.directory) }
 }
}
