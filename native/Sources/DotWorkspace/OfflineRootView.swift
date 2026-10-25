import SwiftUI
import UniformTypeIdentifiers
import WorkspaceCore

struct OfflineWorkspaceHost: View {
  @State private var store: OfflineWorkspaceStore?
  @State private var failure: String?
  var body: some View {
    Group {
      if let store { OfflineRootView().environmentObject(store) }
      else if let failure { Text(failure).padding(35).foregroundStyle(ink) }
      else { ProgressView("로컬 기록을 여는 중…") }
    }.frame(minWidth: 1100, minHeight: 750).background(ivory).task {
      guard store == nil else { return }
      do {
        let path = ProcessInfo.processInfo.environment["DAL_OFFLINE_QA_ROOT"].map { URL(fileURLWithPath: $0) }
          ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DAL/OfflineWorkbench")
        let model = try OfflineWorkspaceStore(directory: path)
        store = model; await model.load()
        AppDelegate.active?.prepareToQuit = { try await model.flushPendingEdits() }
        #if DEBUG
        await OfflineFixtureRunner.run(store: model)
        #endif
      } catch { failure = error.localizedDescription }
    }
  }
}
struct OfflineRootView: View {
  @EnvironmentObject var store: OfflineWorkspaceStore
  @State private var addingProject = false
  @State private var projectName = ""
  @State private var recovering = false
  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 18) {
        Text("✳ DAL").font(.system(size: 27, weight: .semibold)).padding(.bottom, 12)
        Text("이 Mac의 작업실").font(.system(size: 15)).foregroundStyle(mutedInk)
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(store.snapshot.projects) { project in
              Button(project.name) { store.selectProject(project.id) }.buttonStyle(WorkspaceButtonStyle(prominent: store.selectedProjectID == project.id))
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Button("새 프로젝트") { addingProject = true }.buttonStyle(WorkspaceButtonStyle())
        if let project = store.project {
          Divider()
          Text("작업물").font(.system(size: 16, weight: .semibold))
          ForEach(store.snapshot.artifacts.filter { $0.projectID == project.id }) { artifact in
            Button(artifact.name) { store.selectArtifact(artifact.id) }.buttonStyle(WorkspaceButtonStyle())
          }
          Button("새 작업물 영상 열기") { openVideo(newArtifact: true) }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(store.busy)
        }
        Spacer()
        Text("로컬 저장 · 직접 내보내기\n자동 대화 연결 없음").font(.system(size: 14)).foregroundStyle(mutedInk).lineSpacing(5)
      }.padding(22).frame(minWidth: 245).background(ivory)
    } detail: {
      VStack(spacing: 0) {
        if let error = store.error {
          HStack {
            Text(error).font(.system(size: 16)).textSelection(.enabled)
            Spacer()
            Button("이전 저장 사본 복구") { recovering = true }.buttonStyle(WorkspaceButtonStyle())
          }.padding(16).background(Color.red.opacity(0.07)).foregroundStyle(.red)
        }
        if store.version != nil { OfflineReviewView().id(store.artifact?.id ?? "empty") }
        else {
          VStack(alignment: .leading, spacing: 23) {
            Text(store.project?.name ?? "이 Mac에서 작업을 이어가세요").font(.system(size: 30, weight: .semibold))
            Text("프로젝트를 만들고 영상을 열어 위치가 남는 메모를 기록하세요.").font(.system(size: 18)).foregroundStyle(mutedInk)
            Button(store.project == nil ? "새 프로젝트" : "영상 열기") {
              if store.project == nil { addingProject = true } else { openVideo(newArtifact: true) }
            }.buttonStyle(WorkspaceButtonStyle(prominent: true))
          }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).padding(40)
        }
      }.background(ivory)
    }.navigationSplitViewStyle(.balanced).foregroundStyle(ink).font(.system(size: 16))
    .sheet(isPresented: $addingProject) {
      VStack(alignment: .leading, spacing: 20) {
        Text("새 프로젝트").font(.system(size: 25, weight: .semibold))
        TextField("프로젝트 이름", text: $projectName).textFieldStyle(.roundedBorder).font(.system(size: 17))
        HStack { Button("취소") { addingProject = false }; Spacer(); Button("프로젝트 만들기") { Task { await store.createProject(name: projectName); if store.error == nil { addingProject = false; projectName = "" } } }.disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.buttonStyle(WorkspaceButtonStyle())
      }.padding(30).frame(width: 460).background(ivory)
    }
    .confirmationDialog("현재 기록을 남겨 두고 마지막 정상 사본으로 복구할까요?", isPresented: $recovering) {
      Button("이전 사본으로 복구") { Task { await store.recover() } }
    }
  }
  private func openVideo(newArtifact: Bool) {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { Task { await store.importVideo(url, asNewArtifact: newArtifact) } }
  }
}
