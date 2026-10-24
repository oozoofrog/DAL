import SwiftUI
import UniformTypeIdentifiers
import WorkspaceCore

struct ReviewView: View {

  @EnvironmentObject var store: WorkspaceStore
  @StateObject var media = MediaController()
  @State private var versionID = ""
  @State private var threadID: String?
  @State private var creating = false
  @State private var annotation: Annotation?
  @State private var tool = "point"
  @State private var intent = ""
  @State private var start = 0.0
  @State private var end = 2.0
  @State private var working = false
  @State private var showResolved = false
  @State private var localURL: URL?
  @State private var fps = 24.0
  var replyKind: String { threadID.map { store.drafts.kind($0) } ?? "reply" }
  var version: Version? {
    store.snapshot.versions.first {
      $0.id == versionID
    }
      ?? store.snapshot.versions.first
  }

  var thread: ReviewThread? {
    store.snapshot.threads.first {
      $0.id == threadID
    }
  }

  var result: Version? {
    store.snapshot.versions.first {
      $0.id == thread?.resultVersionId
    }
  }

  var canCompare: Bool {
    guard let thread, thread.resultMessageId != nil, localURL == nil else {
      return false
    }
    return media.sourceVersionID == thread.versionId
      && media.resultVersionID == thread.resultVersionId
      && thread.range.fits(actualDuration: media.duration)
      && thread.range.fits(actualDuration: media.resultDuration)
  }

  var body: some View {
    GeometryReader {
      geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 23) {
          HStack {
            VStack(alignment: .leading, spacing: 10) {
              Text("VIDEO REVIEW · \(store.artifact?.name ?? "영상")").font(.system(size: 13))
                .foregroundStyle(mutedInk)
              Text(store.project?.name ?? "프로젝트").font(.system(size: 28, weight: .semibold))
            }
            Spacer()
            Button {
              Task {
                await store.refresh()
              }
            } label: {
              Label("새로고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(WorkspaceButtonStyle())
          }
          if geometry.size.width > 1050 {
            HStack(alignment: .top, spacing: 24) {
              videoColumn.frame(maxWidth: .infinity)
              conversation.frame(width: 380)
            }
          } else {
            videoColumn
            conversation
          }
        }
        .padding(30)
      }
    }
    .task(
      id:
        "\(version?.id ?? "none")|\(localURL?.absoluteString ?? "remote")|\(thread?.id ?? "")|\(thread?.resultMessageId ?? "")"
    ) {
      if let localURL {
        await media.loadLocal(localURL)
      } else {
        await media.load(version: version, result: result, store: store)
      }
      guard !Task.isCancelled else { return }
      if let thread { media.seek(Double(thread.startMs) / 1000) }
    }
    .onAppear {
      store.stopPlayback = {
        media.clear()
      }
    }
    .onDisappear {
      media.clear()
      store.stopPlayback = nil
    }
    .onChange(of: store.connected) {
      _, connected in
      if !connected {
        media.clear()
      }
    }
  }

  var videoColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Picker(
          "영상 버전",
          selection: Binding(
            get: {
              version?.id ?? ""
            },
            set: {
              versionID = $0
              threadID = nil
              creating = false
              localURL = nil
              media.comparing = false
            }
          )
        ) {
          ForEach(store.snapshot.versions) {
            v in Text(v.label).tag(v.id)
          }
        }
        .frame(maxWidth: 360)
        Spacer()
        Button(media.comparing ? "원본 보기" : "전후 비교") {
          media.pause()
          media.comparing.toggle()
          if let thread {
            media.seek(Double(thread.startMs) / 1000)
          }
        }
        .buttonStyle(WorkspaceButtonStyle()).disabled(!canCompare)
      }
      if media.comparing {
        HStack(alignment: .top, spacing: 14) {
          VStack(alignment: .leading, spacing: 9) {
            Text("BEFORE · 원래 표시 유지").font(.system(size: 14))
            stage
          }
          VStack(alignment: .leading, spacing: 9) {
            Text("AFTER · \(result?.label ?? "결과")").font(.system(size: 14))
            PlayerSurface(player: media.resultPlayer).aspectRatio(16 / 9, contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: 9))
          }
        }
      } else {
        stage
      }
      if let error = media.error {
        Text(error).font(.system(size: 14)).foregroundStyle(.red)
      }
      HStack(spacing: 10) {
        Button {
          media.toggle(range: media.comparing ? thread?.range : nil)
        } label: {
          Image(systemName: media.playing ? "pause.fill" : "play.fill")
        }
        .buttonStyle(WorkspaceButtonStyle()).disabled(media.duration == 0)
        Button {
          media.seek(media.time - 1 / (version?.fps ?? fps))
        } label: {
          Image(systemName: "backward.end")
        }
        .buttonStyle(WorkspaceButtonStyle()).accessibilityLabel("프레임 간격 뒤로, 근사 탐색")
        Button {
          media.seek(media.time + 1 / (version?.fps ?? fps))
        } label: {
          Image(systemName: "forward.end")
        }
        .buttonStyle(WorkspaceButtonStyle()).accessibilityLabel("프레임 간격 앞으로, 근사 탐색")
        Text("\(timeLabel(Int(media.time*1000))) / \(timeLabel(Int(media.duration*1000)))").font(
          .system(size: 14)
        ).monospacedDigit()
        Spacer()
        Button {
          media.player.isMuted.toggle()
          media.resultPlayer.isMuted = true
        } label: {
          Image(systemName: "speaker.wave.2")
        }
        .buttonStyle(WorkspaceButtonStyle()).accessibilityLabel("소리 전환")
      }
      Slider(
        value: Binding(
          get: {
            media.time
          },
          set: {
            media.seek($0)
          }
        ), in: 0...max(media.duration, 0.01)
      ).accessibilityLabel("영상 탐색, 근사값")
      HStack {
        Label(media.comparing ? "비교 구간" : "선택 구간", systemImage: "link").font(.system(size: 14))
        Spacer()
        TextField("시작 초", value: $start, format: .number.precision(.fractionLength(0...3))).frame(
          width: 85
        ).textFieldStyle(.roundedBorder).disabled(!creating)
        Text("→")
        TextField("끝 초", value: $end, format: .number.precision(.fractionLength(0...3))).frame(
          width: 85
        ).textFieldStyle(.roundedBorder).disabled(!creating)
        if creating {
          Button("현재 → 시작") {
            start = media.time
          }
          Button("현재 → 끝") {
            end = media.time
          }
        } else {
          Button("구간 재생") {
            media.play(range: thread?.range)
          }
          .disabled(thread == nil)
        }
      }
      .padding(13).background(Color.green.opacity(0.05)).clipShape(
        RoundedRectangle(cornerRadius: 7))
      Text(
        "\(localURL==nil ? "비공개 저장된 영상":"이 기기에서만 연 영상") · \(Int(version?.fps ?? fps)) fps 기준 · 탐색은 근사값"
      ).font(.system(size: 14)).foregroundStyle(mutedInk)
      HStack {
        Button("영상 선택") {
          chooseFile()
        }
        .buttonStyle(WorkspaceButtonStyle())
        if let localURL {
          Text(localURL.lastPathComponent).font(.system(size: 14)).lineLimit(1)
          TextField("fps", value: $fps, format: .number).frame(width: 55).textFieldStyle(
            .roundedBorder)
          Button("비공개로 저장") {
            Task {
              await upload()
            }
          }
          .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
            working || media.duration == 0)
        }
        Spacer()
      }
      Divider()
      HStack {
        Text("장면별 대화 \(store.snapshot.threads.count)").font(.system(size: 20, weight: .semibold))
        Spacer()
        Button {
          newRequest()
        } label: {
          Label("새 요청", systemImage: "plus")
        }
        .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
          media.duration == 0 || localURL != nil || media.sourceVersionID != version?.id)
      }
      Toggle("정리한 대화 포함", isOn: $showResolved).font(.system(size: 14))
      ForEach(
        store.snapshot.threads.filter {
          showResolved || !$0.resolved
        }
      ) {
        t in
        Button {
          selectThread(t)
        } label: {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left").padding(.top, 3)
            VStack(alignment: .leading, spacing: 9) {
              Text(t.intent).font(.system(size: 16)).multilineTextAlignment(.leading)
              Text("\(timeLabel(t.startMs)) — \(timeLabel(t.endMs))").font(.system(size: 14))
                .foregroundStyle(mutedInk)
            }
            Spacer()
            StatusPill(label: t.resolved ? "정리됨" : statusLabels[t.status] ?? t.status)
          }
          .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
            threadID == t.id ? Color.green.opacity(0.07) : .white
          ).clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
      }
      if store.snapshot.threads.isEmpty {
        Text("영상 위에 표시하고 첫 요청을 남겨 보세요.").font(.system(size: 16)).foregroundStyle(mutedInk).frame(
          maxWidth: .infinity, minHeight: 80)
      }
    }
  }

  var stage: some View {
    ZStack {
      PlayerSurface(player: media.player)
      GeometryReader {
        g in
        let box = VideoContentBox(
          containerWidth: g.size.width, containerHeight: g.size.height,
          videoWidth: media.size.width, videoHeight: media.size.height)
        Canvas {
          context, size in
          if let a = creating ? annotation : thread?.annotation {
            draw(a, context: &context, box: box)
          }
        }
        .allowsHitTesting(false)
        if !creating, localURL == nil {
          ForEach(
            store.snapshot.threads.filter {
              $0.versionId == version?.id && (!$0.resolved || $0.id == threadID)
            }
          ) {
            t in
            Button {
              selectThread(t)
            } label: {
              Image(systemName: "bubble.left.fill").foregroundStyle(
                Color(red: 0.95, green: 0.74, blue: 0.37)
              ).font(.system(size: 26)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("장면 요청: \(t.intent)").position(
              x: box.left + t.annotation.x * box.width, y: box.top + t.annotation.y * box.height)
          }
        }
        if creating {
          Color.clear.contentShape(Rectangle()).gesture(
            DragGesture(minimumDistance: 0).onChanged {
              value in
              guard let first = box.normalized(x: value.startLocation.x, y: value.startLocation.y),
                let last = box.normalized(x: value.location.x, y: value.location.y)
              else {
                return
              }
              if tool == "point" {
                annotation = Annotation(type: tool, x: last.x, y: last.y)
              } else if tool == "rectangle" {
                annotation = Annotation(
                  type: tool, x: min(first.x, last.x), y: min(first.y, last.y),
                  x2: max(first.x, last.x), y2: max(first.y, last.y))
              } else {
                annotation = Annotation(type: tool, x: first.x, y: first.y, x2: last.x, y2: last.y)
              }
            }
          )
        }
      }
      if media.duration == 0 {
        VStack(spacing: 16) {
          Image(systemName: "film").font(.system(size: 34))
          Text(media.loading ? "영상을 불러오는 중…" : "검토할 영상을 선택해 주세요").font(.system(size: 18))
          Text("실제 영상만 표시합니다.").font(.system(size: 14))
          Button("영상 선택") {
            chooseFile()
          }
          .buttonStyle(WorkspaceButtonStyle())
        }
        .foregroundStyle(.white).padding(25)
      }
    }
    .aspectRatio(16 / 9, contentMode: .fit).background(.black).clipShape(
      RoundedRectangle(cornerRadius: 9))
  }

  var conversation: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Image(systemName: "bubble.left.and.text.bubble.right")
        Text(creating ? "새 장면 요청" : "장면의 대화").font(.system(size: 20, weight: .semibold))
        Spacer()
      }
      Divider()
      if creating {
        Picker("표시", selection: $tool) {
          Text("지점").tag("point")
          Text("영역").tag("rectangle")
          Text("화살표").tag("arrow")
        }
        .pickerStyle(.segmented).onChange(of: tool) {
          _, _ in annotation = nil
        }
        Text("영상 위에서 지점을 누르거나 누른 채로 끌어 표시해 주세요.").font(.system(size: 14)).foregroundStyle(mutedInk)
        Button("가운데 표시 만들기") {
          annotation =
            tool == "point"
            ? Annotation(type: tool, x: 0.5, y: 0.5)
            : Annotation(type: tool, x: 0.3, y: 0.3, x2: 0.7, y2: 0.7)
        }
        .buttonStyle(WorkspaceButtonStyle())
        if annotation != nil {
          HStack {
            Text("x %")
            TextField(
              "x",
              value: Binding(
                get: {
                  (annotation?.x ?? 0.5) * 100
                },
                set: {
                  annotation?.x = $0 / 100
                }
              ), format: .number
            ).textFieldStyle(.roundedBorder)
            Text("y %")
            TextField(
              "y",
              value: Binding(
                get: {
                  (annotation?.y ?? 0.5) * 100
                },
                set: {
                  annotation?.y = $0 / 100
                }
              ), format: .number
            ).textFieldStyle(.roundedBorder)
          }
          .font(.system(size: 14))
        }
        Text("바라는 변화 남기기").font(.system(size: 16, weight: .medium))
        TextEditor(text: $intent).font(.system(size: 16)).frame(minHeight: 150).padding(7).overlay(
          RoundedRectangle(cornerRadius: 6).stroke(ink.opacity(0.15)))
        Text("의도를 적어 주세요. dot의 실제 이해와 제안이 같은 대화에 이어집니다.").font(.system(size: 14)).foregroundStyle(
          mutedInk)
        Button("요청 저장") {
          Task {
            await create()
          }
        }
        .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
          working || intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || annotation?.isValid != true || end <= start || end > media.duration)
        Button("취소") {
          creating = false
        }
        .buttonStyle(WorkspaceButtonStyle())
      } else if let thread {
        HStack {
          Text("\(timeLabel(thread.startMs)) — \(timeLabel(thread.endMs))").font(.system(size: 14))
          Spacer()
          StatusPill(label: thread.resolved ? "정리됨" : statusLabels[thread.status] ?? thread.status)
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            ForEach(
              store.snapshot.messages.filter {
                $0.threadId == thread.id
              }
            ) {
              m in
              VStack(alignment: .leading, spacing: 9) {
                HStack {
                  Text(m.authorRole == "dot" ? "✳ dot" : "나").font(
                    .system(size: 14, weight: .medium))
                  Spacer()
                  Text(m.kind == "result" ? "제작 결과" : m.kind == "intent" ? "검토 요청" : "대화").font(
                    .system(size: 14)
                  ).foregroundStyle(mutedInk)
                }
                Text(m.body).font(.system(size: 16)).lineSpacing(6).frame(
                  maxWidth: .infinity, alignment: .leading
                ).padding(14).background(
                  m.authorRole == "dot" ? Color.white : Color.green.opacity(0.05)
                ).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(
                  RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.12)))
                if m.kind == "result" {
                  if m.id == thread.resultMessageId {
                    Button("전달된 결과 전후 비교") {
                      media.comparing = true
                      media.seek(Double(thread.startMs) / 1000)
                    }
                    .buttonStyle(WorkspaceButtonStyle()).disabled(!canCompare)
                  } else {
                    Text("이전 전달본 · \(m.versionId ?? "")").font(.system(size: 14)).foregroundStyle(
                      mutedInk)
                  }
                }
              }
            }
          }
        }
        .frame(minHeight: 220, maxHeight: 450)
        if thread.status == "completed" {
          VStack(alignment: .leading, spacing: 12) {
            Text("수정 결과가 도착했습니다").font(.system(size: 17, weight: .semibold))
            Text(canCompare ? "같은 구간을 비교하고 결과를 확인해 주세요." : "두 영상의 실제 구간을 확인한 뒤 비교와 승인을 진행할 수 있습니다.")
              .font(.system(size: 14)).foregroundStyle(mutedInk)
            Button("이 결과 승인") {
              Task {
                await action("approve", for: thread)
              }
            }
            .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(working || !canCompare)
          }
          .padding(15).background(Color.yellow.opacity(0.08)).clipShape(
            RoundedRectangle(cornerRadius: 8))
        }
        Picker(
          "대화 종류",
          selection: Binding(
            get: { store.drafts.kind(thread.id) },
            set: { store.drafts.setKind(thread.id, kind: $0) })
        ) {
          Text("답글").tag("reply")
          Text("다시 요청").tag("rerequest")
        }
        .pickerStyle(.segmented)
        TextEditor(
          text: Binding(
            get: {
              store.drafts.body(thread.id)
            },
            set: {
              store.drafts.set(thread.id, body: $0)
            }
          )
        ).font(.system(size: 16)).frame(minHeight: 100).padding(7).overlay(
          RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.15)))
        Button(replyKind == "rerequest" ? "수정 다시 요청" : "답글 저장") {
          Task {
            await action(store.drafts.kind(thread.id), for: thread)
          }
        }
        .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
          working
            || store.drafts.body(thread.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button(thread.resolved ? "다시 열기" : "대화 정리") {
          Task {
            await action(thread.resolved ? "reopen" : "resolve", for: thread)
          }
        }
        .buttonStyle(WorkspaceButtonStyle())
      } else {
        VStack(alignment: .leading, spacing: 18) {
          Text("한 장면, 하나의 대화").font(.system(size: 21, weight: .medium))
          Text("영상에서 마음에 걸리는 곳을 짚어 주세요. 생각과 수정 결과를 같은 자리에서 이어갈 수 있어요.").lineSpacing(7)
            .foregroundStyle(mutedInk)
          Button("첫 요청 남기기") {
            newRequest()
          }
          .buttonStyle(WorkspaceButtonStyle()).disabled(
            media.duration == 0 || localURL != nil || media.sourceVersionID != version?.id)
        }
        .padding(.vertical, 35)
      }
      Divider()
      Text("대화는 서버에 저장됩니다. dot을 자동 실행하지 않으며, 연결된 도구로 남긴 실제 답변을 새로고침으로 확인해요.").font(
        .system(size: 14)
      ).foregroundStyle(mutedInk).lineSpacing(6)
    }
    .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(
      RoundedRectangle(cornerRadius: 12))
  }

  func selectThread(_ t: ReviewThread) {
    media.pause()
    media.comparing = false
    threadID = t.id
    versionID = t.versionId
    creating = false
    localURL = nil
    start = Double(t.startMs) / 1000
    end = Double(t.endMs) / 1000
    media.seek(start)
  }

  func newRequest() {
    creating = true
    threadID = nil
    annotation = nil
    media.comparing = false
    start = media.time
    end = min(media.duration, start + 2)
  }

  func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.mpeg4Movie]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      localURL = url
      creating = false
      threadID = nil
      media.comparing = false
    }
  }

  func upload() async {
    guard let localURL else {
      return
    }
    working = true
    defer {
      working = false
    }
    do {
      versionID = try await store.upload(file: localURL, duration: media.duration, fps: fps) ?? ""
      self.localURL = nil
    } catch {
      store.error = error.localizedDescription
    }
  }

  func create() async {
    guard let annotation, let version else {
      return
    }
    working = true
    let submitted = intent
    defer {
      working = false
    }
    do {
      threadID = try await store.createThread(
        version: version, start: Int((start * 1000).rounded()), end: Int((end * 1000).rounded()),
        annotation: annotation, intent: submitted)
      creating = false
      if intent == submitted {
        intent = ""
      }
    } catch {
      store.error = error.localizedDescription
    }
  }

  func action(_ kind: String, for thread: ReviewThread) async {
    working = true
    let body = store.drafts.body(thread.id)
    defer {
      working = false
    }
    do {
      try await store.threadAction(
        thread, kind: kind, body: ["reply", "rerequest"].contains(kind) ? body : nil)
      if ["reply", "rerequest"].contains(kind) {
        store.drafts.clearSubmitted(thread.id, body: body, kind: kind)
      }
    } catch {
      store.error = error.localizedDescription
      try? await store.loadReview()
    }
  }

  func draw(_ a: Annotation, context: inout GraphicsContext, box: VideoContentBox) {
    let p = CGPoint(x: box.left + a.x * box.width, y: box.top + a.y * box.height)
    let q = CGPoint(
      x: box.left + (a.x2 ?? a.x) * box.width, y: box.top + (a.y2 ?? a.y) * box.height)
    let color = Color(red: 0.96, green: 0.76, blue: 0.43)
    var path = Path()
    if a.type == "point" {
      path.addEllipse(in: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24))
    } else if a.type == "rectangle" {
      path.addRect(CGRect(x: p.x, y: p.y, width: q.x - p.x, height: q.y - p.y))
    } else {
      path.move(to: p)
      path.addLine(to: q)
      let angle = atan2(q.y - p.y, q.x - p.x)
      path.move(to: CGPoint(x: q.x - 14 * cos(angle - 0.45), y: q.y - 14 * sin(angle - 0.45)))
      path.addLine(to: q)
      path.addLine(to: CGPoint(x: q.x - 14 * cos(angle + 0.45), y: q.y - 14 * sin(angle + 0.45)))
    }
    context.stroke(path, with: .color(color), lineWidth: 3)
  }

}
