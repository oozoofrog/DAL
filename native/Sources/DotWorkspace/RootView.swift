import SwiftUI
import UniformTypeIdentifiers
import WorkspaceCore

let ink = Color(red: 0.20, green: 0.27, blue: 0.16)
let mutedInk = Color(red: 0.36, green: 0.43, blue: 0.30)
let ivory = Color(red: 0.97, green: 0.97, blue: 0.94)
struct WorkspaceButtonStyle: ButtonStyle {
  var prominent = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 16, weight: .medium)).padding(.horizontal, 15).frame(
      minHeight: 44
    ).background(prominent ? ink : Color.white).foregroundStyle(prominent ? Color.white : ink)
      .clipShape(RoundedRectangle(cornerRadius: 7)).overlay(
        RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(prominent ? 0 : 0.16))
      ).opacity(configuration.isPressed ? 0.75 : 1)
  }
}

struct StatusPill: View {
  let label: String
  var body: some View {
    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(ink).padding(
      .horizontal, 9
    ).padding(.vertical, 6).background(Color.green.opacity(0.08)).clipShape(
      RoundedRectangle(cornerRadius: 5))
  }
}

struct RootView: View {

  @EnvironmentObject var store: WorkspaceStore
  @State private var createProject = false
  @State private var name = ""
  @State private var summary = ""
  @State private var previewURL: URL?
  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          Text("✳").font(.system(size: 38)).foregroundStyle(
            Color(red: 0.64, green: 0.53, blue: 0.30))
          VStack(alignment: .leading, spacing: 5) {
            Text("DAL").font(.system(size: 21, weight: .semibold))
            Text("PRIVATE WORKSPACE").font(.system(size: 9, weight: .medium)).tracking(1.5)
              .foregroundStyle(mutedInk)
          }
        }
        .padding(.bottom, 15)
        Button {
          store.destination = "home"
        } label: {
          Label("프로젝트", systemImage: "square.grid.2x2")
        }
        .buttonStyle(WorkspaceButtonStyle())
        if store.connected {
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(store.projects) {
                project in
                Button {
                  Task {
                    await store.select(project)
                  }
                } label: {
                  Text(project.name).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WorkspaceButtonStyle())
              }
            }
          }
        }
        Spacer()
        Button {
          Task {
            await store.showTools()
          }
        } label: {
          Label("이 도구 개선", systemImage: "bubble.left.and.text.bubble.right")
        }
        .buttonStyle(WorkspaceButtonStyle()).disabled(!store.connected)
        Button {
          openLocalVideo()
        } label: {
          Label("기기 영상 열기", systemImage: "film")
        }
        .buttonStyle(WorkspaceButtonStyle())
        Divider()
        HStack(spacing: 6) {
          Circle().fill(store.connected ? Color.green : Color.gray).frame(width: 6, height: 6)
          Text(store.connected ? "저장소 연결됨" : "연결되지 않음").font(.system(size: 14)).foregroundStyle(
            mutedInk)
        }
        Button("dot 연결 상태") { store.showConnectionStatus() }
        .buttonStyle(WorkspaceButtonStyle())
      }
      .padding(22).frame(minWidth: 245).background(ivory)
    } detail: {
      VStack(spacing: 0) {
        if let error = store.error {
          HStack {
            Text(error).font(.system(size: 14))
            Spacer()
            Button {
              store.error = nil
            } label: {
              Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
          }
          .foregroundStyle(.red).padding(15).background(Color.red.opacity(0.06))
        }
        if let previewURL, store.destination == "local" {
          LocalVideoView(url: previewURL)
        } else if store.destination == "project", store.project != nil {
          ReviewView().id("\(store.project?.id ?? "")|\(store.artifact?.id ?? "")")
        } else if store.destination == "tool", store.connected {
          ToolImprovementView()
        } else {
          home
        }
      }
      .background(ivory)
    }
    .navigationSplitViewStyle(.balanced).frame(minWidth: 1100, minHeight: 750).font(
      .system(size: 16)
    ).foregroundStyle(ink).sheet(isPresented: $store.showingConnectionStatus) {
      ConnectionStatusView().environmentObject(store)
    }
    .sheet(isPresented: $createProject) {
      VStack(alignment: .leading, spacing: 18) {
        Text("새 프로젝트").font(.system(size: 24, weight: .semibold))
        TextField("프로젝트 이름", text: $name).textFieldStyle(.roundedBorder)
        TextField("짧은 설명", text: $summary).textFieldStyle(.roundedBorder)
        Text("빈 영상 작업물과 함께 시작합니다.").font(.system(size: 14)).foregroundStyle(mutedInk)
        HStack {
          Button("취소") {
            createProject = false
          }
          .buttonStyle(WorkspaceButtonStyle())
          Spacer()
          Button("프로젝트 만들기") {
            Task {
              do {
                try await store.createProject(name: name, summary: summary)
                createProject = false
                name = ""
                summary = ""
              } catch {
                store.error = error.localizedDescription
              }
            }
          }
          .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(30).frame(width: 480)
    }
    .onAppear {
      if let path = ProcessInfo.processInfo.environment["DOT_LOCAL_VIDEO"] {
        previewURL = URL(fileURLWithPath: path)
        store.destination = "local"
      }
    }
  }

  var home: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack {
          VStack(alignment: .leading, spacing: 12) {
            Text("프로젝트와 대화를 이어가는 공간").font(.system(size: 13, weight: .medium)).foregroundStyle(
              mutedInk)
            Text("오늘은 어떤 작업을 이어갈까요.").font(.system(size: 30, weight: .semibold))
          }
          Spacer()
          Button {
            Task {
              await store.refresh()
            }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(WorkspaceButtonStyle()).disabled(!store.connected)
        }
        if store.connected {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
            ForEach(store.projects) {
              p in
              Button {
                Task {
                  await store.select(p)
                }
              } label: {
                VStack(alignment: .leading, spacing: 18) {
                  HStack {
                    Image(systemName: "film").font(.system(size: 25))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                  }
                  Text(p.name).font(.system(size: 24, weight: .semibold))
                  Text(p.summary).font(.system(size: 16)).foregroundStyle(mutedInk)
                    .multilineTextAlignment(.leading)
                  Spacer()
                  HStack(spacing: 15) {
                    Text("작업물 \(p.artifactCount)")
                    Text("열린 대화 \(p.openCount)")
                    Text("확인할 결과 \(p.resultCount)")
                  }
                  .font(.system(size: 14))
                  Divider()
                  Text("마지막 기록 \(p.updatedAt)").font(.system(size: 12)).foregroundStyle(mutedInk)
                }
                .padding(25).frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
                .background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
              }
              .buttonStyle(.plain)
            }
            Button {
              createProject = true
            } label: {
              VStack(spacing: 18) {
                Image(systemName: "plus").font(.system(size: 26))
                Text("프로젝트 추가").font(.system(size: 19))
                Text("새 영상과 검토 대화를 모으세요.").font(.system(size: 14)).foregroundStyle(mutedInk)
              }
              .frame(maxWidth: .infinity, minHeight: 300).background(Color.white.opacity(0.4))
              .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
          }
        } else {
          VStack(alignment: .leading, spacing: 21) {
            Text("기기에 있는 영상을 열어 보세요").font(.system(size: 24, weight: .semibold))
            Text(
              "영상을 재생하고 원하는 장면으로 이동할 수 있어요.\n프로젝트와 저장된 대화는 dot 연결 방식이 준비되면 이어갈 수 있어요."
            ).lineSpacing(8)
              .foregroundStyle(mutedInk)
            HStack(spacing: 13) {
              Button("기기 영상 열기") {
                openLocalVideo()
              }
              .buttonStyle(WorkspaceButtonStyle(prominent: true))
              Button("dot 연결 상태") { store.showConnectionStatus() }
                .buttonStyle(WorkspaceButtonStyle())
            }
          }
          .padding(35).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(
            RoundedRectangle(cornerRadius: 14))
        }
        Divider()
        Text("기기 영상은 이 Mac에서만 열어요. 현재 DAL에서 대화를 저장하거나 dot에게 보낼 수는 없어요.").font(
          .system(size: 14)
        ).foregroundStyle(mutedInk).lineSpacing(6)
      }
      .padding(38)
    }
  }

  func openLocalVideo() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.mpeg4Movie]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      previewURL = url
      store.destination = "local"
    }
  }

}

struct LocalVideoView: View {
  let url: URL
  @StateObject var media = MediaController()
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("기기에서 연 영상").font(.system(size: 28, weight: .semibold))
      Text(url.lastPathComponent).foregroundStyle(mutedInk)
      PlayerSurface(player: media.player).aspectRatio(16 / 9, contentMode: .fit).clipShape(
        RoundedRectangle(cornerRadius: 10))
      HStack {
        Button {
          media.toggle()
        } label: {
          Label(
            media.playing ? "일시 정지" : "재생", systemImage: media.playing ? "pause.fill" : "play.fill")
        }
        .buttonStyle(WorkspaceButtonStyle())
        Slider(
          value: Binding(
            get: {
              media.time
            },
            set: {
              media.seek($0)
            }
          ), in: 0...max(media.duration, 0.01))
        Text(timeLabel(Int(media.time * 1000))).monospacedDigit()
      }
      Text("이 영상은 기기에서만 열어요. 현재 DAL에서는 영상에 대화를 저장하거나 dot에게 보낼 수 없어요.").font(.system(size: 14))
        .foregroundStyle(mutedInk).lineSpacing(7)
      if let error = media.error {
        Text(error).foregroundStyle(.red)
      }
      Spacer()
    }
    .padding(35).task(id: url) {
      await media.loadLocal(url)
    }
    .onDisappear {
      media.clear()
    }
  }

}
