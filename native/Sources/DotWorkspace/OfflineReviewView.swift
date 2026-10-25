import SwiftUI
import Combine
import WorkspaceCore
import UniformTypeIdentifiers

struct OfflineReviewView: View {
  @EnvironmentObject var store: OfflineWorkspaceStore
  @StateObject private var media = MediaController()
  @StateObject private var hand = HandSessionFactory.make()
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var editingText: Bool
  @State private var handRegion = HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
  @State private var handMirrored = true
  @State private var videoGeometry = HandVideoGeometry(width: 0, height: 0, videoWidth: 0, videoHeight: 0)
  @State private var handQARan = false
  private let handClock = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
  @State private var mark: Annotation?
  @State private var markType = "point"
  private var intent: String { store.version.map { store.composerBody($0.id) } ?? "" }
  private var canAnnotate: Bool { store.canAnnotate(using: media) }
  @State private var startMs = 0.0
  @State private var endMs = 2000.0
  @State private var showClosed = false
  @State private var selectedExportIDs = Set<String>()
  @State private var showingExport = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 8) {
            Text(store.project?.name ?? "프로젝트").font(.system(size: 14)).foregroundStyle(mutedInk)
            Text(store.artifact?.name ?? "영상").font(.system(size: 26, weight: .semibold))
          }
          Spacer()
          Button("새 버전 추가") { pickVideo(relink: false) }.buttonStyle(WorkspaceButtonStyle()).disabled(store.busy)
        }
        HStack(alignment: .top, spacing: 22) {
          VStack(alignment: .leading, spacing: 16) {
            Picker("영상 버전", selection: Binding(get: { store.selectedVersionID ?? "" }, set: { media.clear(); store.selectedVersionID = $0; store.selectedRequestID = nil })) {
              ForEach(store.snapshot.versions.filter { $0.artifactID == store.artifact?.id }) { v in Text("\(v.id.prefix(8)) · \(v.fingerprint.prefix(12))").tag(v.id) }
            }.font(.system(size: 16))
            ZStack {
              PlayerSurface(player: media.player)
              markLayer
            }.aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 9))
            HStack {
              Button(media.playing ? "일시 정지" : "재생") { media.toggle() }.buttonStyle(WorkspaceButtonStyle()).disabled(!canAnnotate)
              Slider(value: Binding(get: { media.time }, set: { media.seek($0) }), in: 0...max(media.duration, 0.01)).accessibilityLabel("영상 시간").disabled(!canAnnotate)
              Text(timeLabel(Int(media.time * 1000))).monospacedDigit()
            }
            HandInputControls(session: hand, context: handSurface.context, region: $handRegion, mirrored: $handMirrored, synthetic: HandSessionFactory.isSynthetic)
            if store.availability != .matching {
              Text(store.availability == .missing ? "원본 파일이 없어요. 메모는 보관돼요." : "영상 내용이 다르거나 읽을 수 없어요. 새 표시는 만들지 않아요.").font(.system(size: 16)).foregroundStyle(mutedInk)
              Button("같은 원본 다시 선택") { pickVideo(relink: true) }.buttonStyle(WorkspaceButtonStyle())
            }
            HStack {
              Picker("표시 종류", selection: $markType) { Text("점").tag("point"); Text("영역").tag("rectangle"); Text("화살표").tag("arrow") }.pickerStyle(.segmented)
              Button("중앙에 표시") { mark = markType == "point" ? Annotation(type: "point", x: 0.5, y: 0.5) : Annotation(type: markType, x: 0.3, y: 0.3, x2: 0.7, y2: 0.7) }.buttonStyle(WorkspaceButtonStyle()).disabled(!canAnnotate)
            }
            if let selected = mark {
              HStack {
                coordinateField("x", value: selected.x, key: "x")
                coordinateField("y", value: selected.y, key: "y")
                if selected.type != "point" {
                  coordinateField("끝 x", value: selected.x2 ?? 0.7, key: "x2")
                  coordinateField("끝 y", value: selected.y2 ?? 0.7, key: "y2")
                }
              }
            }
            HStack {
              Button("현재 시각을 시작으로") { startMs = (media.time * 1000).rounded(); endMs = min(Double(store.version?.durationMs ?? 0), startMs + 2000) }.buttonStyle(WorkspaceButtonStyle()).disabled(!canAnnotate)
              TextField("시작 ms", value: $startMs, format: .number).focused($editingText).textFieldStyle(.roundedBorder).frame(width: 100).accessibilityLabel("시작 밀리초")
              Text("–")
              TextField("끝 ms", value: $endMs, format: .number).focused($editingText).textFieldStyle(.roundedBorder).frame(width: 100).accessibilityLabel("끝 밀리초")
            }
            TextEditor(text: composerBinding(store.version?.id)).focused($editingText).font(.system(size: 17)).frame(minHeight: 100).overlay(RoundedRectangle(cornerRadius: 6).stroke(ink.opacity(0.2))).accessibilityLabel("새 요청 메모")
            Button("표시한 구간에 메모 저장") {
              guard let version = store.version, let mark else { return }
              let body = intent
              let anchor = OfflineAnchor(versionID: version.id, startMs: Int(startMs), endMs: Int(endMs), annotation: mark)
              Task { await store.createRequest(anchor: anchor, body: body) }
            }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!canAnnotate || mark?.isValid != true || intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !startMs.isFinite || !endMs.isFinite || startMs < 0 || endMs <= startMs || endMs > Double(store.version?.durationMs ?? 0))
            Text("로컬 메모예요. dot에게 전송하거나 사용자 인증을 확인하지 않아요.").font(.system(size: 14)).foregroundStyle(mutedInk)
          }.frame(maxWidth: .infinity)
          requestColumn.frame(width: 330)
        }
      }.padding(28)
    }.onAppear { installHandStopHook() }
    .onReceive(handClock) { _ in hand.tick() }
    .onChange(of: handSurface.context, initial: true) { _, next in hand.updateContext(next); hand.updateTargets(handSurface.targets) }
    .onChange(of: handSurface.targets) { _, next in hand.updateTargets(next) }
    .onChange(of: handRegion) { _, _ in hand.updateMapping(HandMapping(region: handRegion, mirrored: handMirrored)) }
    .onChange(of: handMirrored) { _, _ in hand.updateMapping(HandMapping(region: handRegion, mirrored: handMirrored)) }
    .onChange(of: hand.feedback) { _, next in applyHandFeedback(next) }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hand.disable() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in hand.disable() }
    .onChange(of: canAnnotate) { _, ready in
      #if DEBUG
      if ready && !handQARan && OfflineFixtureRunner.isHandQA {
        handQARan = true
        Task { await OfflineFixtureRunner.handViewQA(session: hand, surface: { handSurface }, draft: { mark }, apply: { applyHandFeedback($0) }) }
      }
      #endif
    }
    .task(id: store.mediaSelectionID) {
      hand.disable()
      mark = store.request?.anchor.annotation
      await store.prepareMedia(media)
    }.onChange(of: store.selectedRequestID) { _, _ in
      if let request = store.request { mark = request.anchor.annotation; startMs = Double(request.anchor.startMs); endMs = Double(request.anchor.endMs); media.seek(Double(request.anchor.startMs) / 1000) }
    }.onDisappear { hand.disable(); AppDelegate.active?.stopHandInput = nil; media.clear() }
    .onChange(of: store.qaExportRequestID, initial: true) { _, id in
      #if DEBUG
      if let id, ProcessInfo.processInfo.environment["DAL_OFFLINE_QA_MODE"] == "export" { selectedExportIDs = [id]; showingExport = true }
      #endif
    }
    .sheet(isPresented: $showingExport) { OfflineExportView(artifactID: store.artifact?.id ?? "", selectedRequestIDs: selectedExportIDs.sorted()).environmentObject(store) }
  }
  private var requestColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("위치가 남는 메모").font(.system(size: 21, weight: .semibold))
      Button("선택한 \(selectedExportIDs.count)개 미리 보기") { media.pause(); showingExport = true }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(selectedExportIDs.isEmpty || store.busy)
      Toggle("닫은 메모 포함", isOn: $showClosed).font(.system(size: 14))
      ForEach(store.snapshot.requests.filter { $0.artifactID == store.artifact?.id && (showClosed || !$0.resolved) }) { request in
        HStack(alignment: .top, spacing: 10) {
        Toggle("내보내기에 포함", isOn: Binding(get: { selectedExportIDs.contains(request.id) }, set: { included in if included { selectedExportIDs.insert(request.id) } else { selectedExportIDs.remove(request.id) } })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("요청 \(request.id.prefix(8)) 내보내기에 포함").frame(minWidth: 44, minHeight: 44)
        Button {
          media.clear(); store.selectRequest(request.id); mark = request.anchor.annotation
          startMs = Double(request.anchor.startMs); endMs = Double(request.anchor.endMs)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(request.body).font(.system(size: 16)).lineLimit(3)
            Text("\(timeLabel(request.anchor.startMs)) – \(timeLabel(request.anchor.endMs)) · \(request.id.prefix(8))").font(.system(size: 14)).foregroundStyle(store.selectedRequestID == request.id ? Color.white.opacity(0.9) : mutedInk)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(WorkspaceButtonStyle(prominent: store.selectedRequestID == request.id))
        }
      }
      if let request = store.request {
        Divider()
        Text("요청 \(request.id)").font(.system(size: 14, design: .monospaced)).textSelection(.enabled)
        TextEditor(text: Binding(get: { return store.drafts.bodyIfPresent(request.id) ?? request.body }, set: { store.drafts.set(request.id, body: $0) })).focused($editingText).font(.system(size: 17)).frame(minHeight: 100).accessibilityLabel("선택한 메모 수정")
        HStack {
          Button("수정 저장") { let body = store.drafts.bodyIfPresent(request.id) ?? request.body; Task { await store.saveText(id: request.id, body: body, expectedRevision: request.revision) } }.buttonStyle(WorkspaceButtonStyle())
          Button(request.resolved ? "다시 열기" : "닫기") { Task { await store.setResolved(request) } }.buttonStyle(WorkspaceButtonStyle())
        }
        Text("변경 이력").font(.system(size: 17, weight: .semibold))
        ForEach(store.snapshot.events.filter { $0.requestID == request.id }) { event in
          VStack(alignment: .leading, spacing: 5) {
            Text(event.kind.rawValue).font(.system(size: 14)).foregroundStyle(mutedInk)
            Text(event.body).font(.system(size: 16)).textSelection(.enabled)
          }.padding(.vertical, 6)
        }
      }
    }
  }
  private var markLayer: some View {
    GeometryReader { geometry in
      let box = VideoContentBox(containerWidth: geometry.size.width, containerHeight: geometry.size.height, videoWidth: media.size.width, videoHeight: media.size.height)
      Canvas { context, _ in
        if canAnnotate, let selected = mark ?? store.request?.anchor.annotation {
          let p = CGPoint(x: box.left + selected.x * box.width, y: box.top + selected.y * box.height)
          var path = Path()
          if selected.type == "point" { path.addEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)) }
          else if let x2 = selected.x2, let y2 = selected.y2 {
            let q = CGPoint(x: box.left + x2 * box.width, y: box.top + y2 * box.height)
            if selected.type == "rectangle" { path.addRect(CGRect(x: min(p.x,q.x), y: min(p.y,q.y), width: abs(q.x-p.x), height: abs(q.y-p.y))) }
            else { path.move(to: p); path.addLine(to: q); let angle = atan2(q.y-p.y,q.x-p.x); path.move(to: CGPoint(x:q.x-14*cos(angle-0.45),y:q.y-14*sin(angle-0.45)));path.addLine(to:q);path.addLine(to:CGPoint(x:q.x-14*cos(angle+0.45),y:q.y-14*sin(angle+0.45))) }
          }
          context.stroke(path, with: .color(.yellow), lineWidth: 3)
        }
        if let pointer = hand.feedback.pointer, hand.state == .running {
          let point = CGPoint(x: pointer.x * geometry.size.width, y: pointer.y * geometry.size.height)
          context.stroke(Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)), with: .color(ink), lineWidth: hand.feedback.phase == .ready ? 4 : 2)
        }
      }.onAppear { updateHandGeometry(geometry.size) }
      .onChange(of: geometry.size) { _, size in updateHandGeometry(size) }
      .onChange(of: media.size) { _, _ in updateHandGeometry(geometry.size) }
      .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
        guard canAnnotate, let first = box.normalized(x: value.startLocation.x, y: value.startLocation.y), let last = box.normalized(x: value.location.x, y: value.location.y) else { return }
        media.pause()
        if markType == "point" { mark = Annotation(type: "point", x: last.x, y: last.y) }
        else if markType == "rectangle" { mark = Annotation(type: markType, x: min(first.x,last.x), y: min(first.y,last.y), x2: max(first.x,last.x), y2: max(first.y,last.y)) }
        else { mark = Annotation(type: markType, x: first.x, y: first.y, x2: last.x, y2: last.y) }
      }).accessibilityLabel("영상 위 표시 영역. 키보드로는 중앙에 표시 버튼을 사용할 수 있어요.")
    }
  }
  private func installHandStopHook() {
    let session = hand
    AppDelegate.active?.stopHandInput = { [weak session] in session?.disable() }
  }
  private var handSurface: HandInputSurface {
    let request = store.request
    let originalMark = request?.anchor.annotation
    let markChanged = mark != originalMark
    let rangeChanged = request.map { startMs != Double($0.anchor.startMs) || endMs != Double($0.anchor.endMs) } ?? (startMs != 0 || endMs != min(2000, Double(store.version?.durationMs ?? 2000)))
    let editedBody = request.map { (store.drafts.bodyIfPresent($0.id) ?? $0.body) != $0.body } ?? false
    let visible = request.map { HandVisibleAnnotation(id: $0.id, versionID: $0.anchor.versionID, startMs: $0.anchor.startMs, endMs: $0.anchor.endMs, annotation: $0.anchor.annotation) }
    return HandInputPolicy.surface(versionID: store.version?.id, selectionID: store.mediaSelectionID.uuidString + "|" + markType, playheadMs: Int((media.time * 1000).rounded()), sourceReady: canAnnotate, paused: !media.playing, focused: scenePhase == .active && NSApp.isActive && !showingExport, typing: editingText, hasUnsavedDraft: !intent.isEmpty || markChanged || rangeChanged || editedBody, geometry: videoGeometry, visible: visible)
  }
  private func updateHandGeometry(_ size: CGSize) {
    videoGeometry = HandVideoGeometry(width: size.width, height: size.height, videoWidth: media.size.width, videoHeight: media.size.height)
  }
  private func applyHandFeedback(_ feedback: HandFeedback) {
    guard let action = HandInputPolicy.allowedAction(feedback, on: handSurface) else { return }
    switch action {
    case .selectVisibleRequest(let id):
      guard store.selectedRequestID != id else { return }
      hand.disable(); media.clear(); store.selectRequest(id)
    case .startPointDraft(let p):
      mark = Annotation(type: "point", x: p.x, y: p.y); markType = "point"
      startMs = Double(feedback.lockedContext!.playheadMs); endMs = min(Double(store.version?.durationMs ?? 0), startMs + 2000)
      hand.disable()
    }
  }
  private func composerBinding(_ versionID: String?) -> Binding<String> {
    Binding(get: { versionID.map { store.composerBody($0) } ?? "" }, set: { body in
      if let versionID { store.setComposerBody(versionID, body: body) }
    })
  }
  private func coordinateField(_ label: String, value: Double, key: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.system(size: 14))
      TextField(label, value: Binding(get: { value }, set: { next in
        guard var current = mark else { return }
        if key == "x" { current.x = next }; if key == "y" { current.y = next }
        if key == "x2" { current.x2 = next }; if key == "y2" { current.y2 = next }
        mark = current
      }), format: .number).focused($editingText).textFieldStyle(.roundedBorder).accessibilityLabel("표시 정규화 좌표 " + label)
    }.frame(maxWidth: .infinity)
  }
  private func pickVideo(relink: Bool) {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.allowsMultipleSelection = false
    media.pause()
    if panel.runModal() == .OK, let url = panel.url { if relink { media.clear() }; Task { if relink { await store.relink(url) } else { await store.importVideo(url, asNewArtifact: false) } } }
  }
}
