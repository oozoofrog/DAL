import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WorkspaceCore

struct OfflineExportView: View {
 @EnvironmentObject var store:OfflineWorkspaceStore
 @Environment(\.dismiss) private var dismiss
 let artifactID:String
 let selectedRequestIDs:[String]
 @State private var coordinator:OfflineExportCoordinator?
 @State private var preview:ExportPreview?
 @State private var receipt:ExportReceipt?
 @State private var error:String?
 @State private var preparing=false
 @State private var saving=false
 @State private var generation=UUID()
 @State private var work:Task<Void,Never>?
 var body:some View {
  VStack(alignment:.leading,spacing:18) {
   HStack {
    VStack(alignment:.leading,spacing:8) {
     Text("선택한 메모 미리 보기").font(.system(size:27,weight:.semibold))
     Text("실제 캡처와 문서를 확인한 뒤 ZIP으로 저장하세요. 원본 영상은 포함하지 않아요.").font(.system(size:16)).foregroundStyle(mutedInk)
    }
    Spacer()
    Button("닫기") { close() }.buttonStyle(WorkspaceButtonStyle())
   }
   if let error { Text(error).font(.system(size:16)).foregroundStyle(.red).textSelection(.enabled) }
   if preparing { ProgressView("같은 원본을 확인하고 실제 캡처를 만드는 중…").font(.system(size:17)).frame(maxWidth:.infinity,minHeight:180) }
   if let preview {
    HStack {
     Text("\(preview.snapshot.requests.count)개 메모 · \(preview.entries.count)개 파일 · 정확히 \(preview.exactByteCount.formatted())바이트").font(.system(size:18,weight:.semibold))
     Spacer()
    }
    if !preview.snapshot.isCurrent(in:store.snapshot) { Text("메모가 바뀌었어요. 새로 미리 보기를 만들어 주세요.").font(.system(size:16)).foregroundStyle(.red) }
    ScrollView { document(preview).padding(.trailing,8) }.accessibilityLabel("내보낼 문서와 실제 캡처")
   } else if !preparing { Spacer() }
   Divider()
   HStack {
    if let receipt {
     Text("\(receipt.byteCount.formatted())바이트를 저장했어요. 파일을 직접 첨부해 전달하세요.").font(.system(size:16))
    } else { Text("선택한 메모·캡처·버전 정보를 새 ZIP 파일로 저장해요.").font(.system(size:14)).foregroundStyle(mutedInk) }
    Spacer()
    Button("다시 준비") { startPreparation() }.buttonStyle(WorkspaceButtonStyle()).disabled(preparing || saving)
    Button(saving ? "저장 확인 중…" : "확인한 ZIP 저장") { save() }.buttonStyle(WorkspaceButtonStyle(prominent:true)).disabled(preview==nil || preparing || saving || receipt != nil || preview.map{!$0.snapshot.isCurrent(in:store.snapshot)} == true)
   }
  }.padding(26).frame(minWidth:1000,minHeight:760).background(ivory).foregroundStyle(ink)
  .task { startPreparation() }
  .onDisappear { work?.cancel();if let preview {coordinator?.cancel(preview:preview)} }
 }
 @ViewBuilder private func document(_ preview:ExportPreview) -> some View {
  VStack(alignment:.leading,spacing:24) {
   Text(preview.snapshot.artifactName).font(.system(size:25,weight:.semibold))
   Text("스냅샷 (UTC) \(preview.snapshot.createdAtText)").font(.system(size:14))
   Text("내보내기 ID \(preview.snapshot.exportID)").font(.system(size:14,design:.monospaced)).textSelection(.enabled)
   Text("캡처는 최대 1920×1080이에요. 요청 시각과 실제 캡처 시각을 따로 기록해요.").font(.system(size:14)).foregroundStyle(mutedInk)
   ForEach(preview.snapshot.requests) { request in
    VStack(alignment:.leading,spacing:13) {
     Text(request.body).font(.system(size:18)).textSelection(.enabled)
     Text("요청 \(request.id) · 수정 \(request.revision)").font(.system(size:14,design:.monospaced)).textSelection(.enabled)
     Text("버전 \(request.anchor.versionID) · 선택 구간 \(request.anchor.startMs)–\(request.anchor.endMs) ms").font(.system(size:14)).textSelection(.enabled)
     if let version=preview.snapshot.versions.first(where:{$0.id==request.anchor.versionID}) { Text("SHA256 \(version.fingerprint)").font(.system(size:14,design:.monospaced)).textSelection(.enabled) }
     ForEach(preview.captures.filter{$0.requestID==request.id},id:\.requestedMs) { capture in
      VStack(alignment:.leading,spacing:8) {
       if let image=NSImage(data:capture.png) { Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).frame(maxWidth:800).accessibilityLabel("저장된 표시가 있는 실제 원본 캡처") }
       Text("요청 \(capture.requestedMs) ms · 실제 캡처 \(String(format:"%.3f",capture.actualMs)) ms · \(capture.pixelWidth)×\(capture.pixelHeight)").font(.system(size:14)).foregroundStyle(mutedInk)
      }
     }
     ForEach(preview.snapshot.events.filter{$0.requestID==request.id}) { event in
      VStack(alignment:.leading,spacing:5) { Text(OfflineReportRenderer.label(event.kind)).font(.system(size:14,weight:.semibold));Text(event.body).font(.system(size:16)).textSelection(.enabled) }
     }
    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.white).clipShape(RoundedRectangle(cornerRadius:10))
   }
   Text("묶을 파일").font(.system(size:20,weight:.semibold))
   ForEach(preview.entries,id:\.path) { entry in
    HStack { Text(entry.path).font(.system(size:16));Spacer();Text("\(entry.data.count.formatted())바이트").font(.system(size:14)).monospacedDigit() }
   }
   Text("ZIP SHA256 \(preview.archiveSHA256)").font(.system(size:14,design:.monospaced)).textSelection(.enabled)
  }.frame(maxWidth:.infinity,alignment:.leading)
 }
 @MainActor private func startPreparation() {
  work?.cancel();if let preview {coordinator?.cancel(preview:preview)}
  let token=UUID();generation=token;preview=nil;receipt=nil;error=nil;preparing=true
  let manager=coordinator ?? OfflineExportCoordinator(repository:store.repository);coordinator=manager
  work=Task { @MainActor in
   defer { if generation==token {preparing=false} }
   do {
    for id in selectedRequestIDs {
     if let request=store.snapshot.requests.first(where:{$0.id==id}),let draft=store.drafts.bodyIfPresent(id),draft != request.body { throw OfflineError.invalid("선택한 메모의 수정을 먼저 저장해 주세요.") }
    }
    let current=try await store.repository.load()
    let snapshot=try ExportSnapshot(workspace:current,artifactID:artifactID,selectedRequestIDs:selectedRequestIDs)
    let prepared=try await manager.prepare(snapshot:snapshot)
    guard !Task.isCancelled,generation==token else {manager.cancel(preview:prepared);return}
    preview=prepared;preparing=false
    #if DEBUG
    if ProcessInfo.processInfo.environment["DAL_OFFLINE_QA_MODE"] == "export" {
      await OfflineFixtureRunner.exportViewQA(coordinator:manager,preview:prepared,dismiss:{ close() })
    }
    #endif
   } catch is CancellationError {} catch {if generation==token {self.error=error.localizedDescription}}
  }
 }
 @MainActor private func save() {
  guard let preview,let coordinator else{return}
  let panel=NSSavePanel();panel.allowedContentTypes=[.zip];panel.canCreateDirectories=true;panel.showsTagField=false
  let name=preview.snapshot.artifactName.replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:"\\",with:"-").replacingOccurrences(of:":",with:"-")
  panel.nameFieldStringValue=String(name.prefix(80))+"-메모.zip"
  guard panel.runModal() == .OK,let destination=panel.url else{return}
  let approval:ExportDestinationApproval
  do { approval=try coordinator.approveNewDestination(preview:preview,destination:destination) }
  catch { self.error=error.localizedDescription;return }
  saving=true;error=nil
  work=Task { @MainActor in
   defer{saving=false}
   do{receipt=try await coordinator.commit(preview:preview,destination:destination,approval:approval)}
   catch is CancellationError {} catch{self.error=error.localizedDescription}
  }
 }
 @MainActor private func close() { generation=UUID();work?.cancel();if let preview {coordinator?.cancel(preview:preview)};dismiss() }
}
