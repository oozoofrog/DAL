import SwiftUI
import WorkspaceCore

struct ToolImprovementView: View {

  @EnvironmentObject var store: WorkspaceStore
  @State private var selected: String?
  @State private var adding = false
  @State private var newBody = ""
  @State private var working = false
  let labels = [
    "requested": "요청 기록", "proposed": "제안 도착", "approved": "진행 결정 · 미적용", "deferred": "보류",
    "applied": "적용 기록",
  ]
  var request: ToolRequest? {
    store.tools.requests.first {
      $0.id == selected
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 10) {
            Text("WORKSPACE · TOOL IMPROVEMENT").font(.system(size: 13)).foregroundStyle(mutedInk)
            Text("이 도구 개선").font(.system(size: 28, weight: .semibold))
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
        Text("작업물의 수정과 구분해서, 작업실의 불편함과 개선 제안을 이야기해요.").foregroundStyle(mutedInk)
        HStack(alignment: .top, spacing: 24) {
          VStack(alignment: .leading, spacing: 13) {
            Button {
              adding = true
              selected = nil
            } label: {
              Label("개선 요청 남기기", systemImage: "plus")
            }
            .buttonStyle(WorkspaceButtonStyle(prominent: true))
            ForEach(store.tools.requests) {
              r in
              Button {
                selected = r.id
                adding = false
              } label: {
                VStack(alignment: .leading, spacing: 13) {
                  StatusPill(label: r.resolved ? "정리됨" : labels[r.status] ?? r.status)
                  Text(r.body).font(.system(size: 16)).multilineTextAlignment(.leading)
                  Text("마지막 기록 \(r.updatedAt)").font(.system(size: 12)).foregroundStyle(mutedInk)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
                  selected == r.id ? Color.green.opacity(0.07) : .white
                ).clipShape(RoundedRectangle(cornerRadius: 8))
              }
              .buttonStyle(.plain)
            }
            if store.tools.requests.isEmpty {
              Text("아직 개선 대화가 없어요. 사용 중 불편했던 점부터 남겨 주세요.").font(.system(size: 14)).lineSpacing(7)
                .foregroundStyle(mutedInk)
            }
          }
          .frame(width: 275)
          VStack(alignment: .leading, spacing: 20) {
            if adding {
              Text("어떤 점이 불편했나요?").font(.system(size: 23, weight: .semibold))
              TextEditor(text: $newBody).font(.system(size: 16)).frame(minHeight: 170).padding(8)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.15)))
              Text("어느 화면에서 어떤 작업이 어려웠는지 알려 주세요. dot의 실제 답변과 제안을 이 대화에 모읍니다.").font(
                .system(size: 14)
              ).foregroundStyle(mutedInk).lineSpacing(7)
              Button("요청 저장") {
                Task {
                  working = true
                  defer {
                    working = false
                  }
                  do {
                    let submitted = newBody
                    selected = try await store.createToolRequest(submitted)
                    adding = false
                    if newBody == submitted {
                      newBody = ""
                    }
                  } catch {
                    store.error = error.localizedDescription
                  }
                }
              }
              .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
                working || newBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if let request {
              StatusPill(label: labels[request.status] ?? request.status)
              Text(request.body).font(.system(size: 22, weight: .semibold)).lineSpacing(6)
              Divider()
              ForEach(
                store.tools.messages.filter {
                  $0.requestId == request.id
                }
              ) {
                m in
                VStack(alignment: .leading, spacing: 11) {
                  HStack {
                    Text(m.authorRole == "dot" ? "✳ dot" : "나").font(
                      .system(size: 14, weight: .medium))
                    Spacer()
                    Text(m.createdAt).font(.system(size: 12)).foregroundStyle(mutedInk)
                  }
                  Text(m.body).font(.system(size: 16)).lineSpacing(7)
                  if let p = m.proposal {
                    Divider()
                    proposalField("제안 이유", p.rationale)
                    proposalField("작은 변경안", p.summary)
                    proposalField("변경 범위", p.scope)
                  }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
                  Color.green.opacity(m.authorRole == "dot" ? 0.025 : 0.06)
                ).clipShape(RoundedRectangle(cornerRadius: 8))
              }
              if request.status == "proposed" {
                VStack(alignment: .leading, spacing: 13) {
                  Text("이 제안으로 진행할까요?").font(.system(size: 19, weight: .semibold))
                  Text("결정만 기록합니다. 실제 코드 변경과 배포는 별도 작업에서 검증한 뒤 진행해요.").font(.system(size: 14))
                    .foregroundStyle(mutedInk).lineSpacing(6)
                  HStack {
                    Button("이 제안으로 진행") {
                      Task {
                        await act("approve")
                      }
                    }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    Button("보류") {
                      Task {
                        await act("defer")
                      }
                    }
                    .buttonStyle(WorkspaceButtonStyle())
                  }
                }
                .padding(18).background(Color.yellow.opacity(0.08)).clipShape(
                  RoundedRectangle(cornerRadius: 8))
              }
              if request.status == "approved" {
                Text("진행하기로 결정한 제안입니다. 아직 적용 완료를 뜻하지 않습니다.").font(.system(size: 14))
                  .foregroundStyle(mutedInk).padding(15).background(Color.green.opacity(0.05))
              }
              Text("대화 이어가기").font(.system(size: 16, weight: .medium))
              TextEditor(
                text: Binding(
                  get: {
                    store.drafts.body(request.id)
                  },
                  set: {
                    store.drafts.set(request.id, body: $0)
                  }
                )
              ).font(.system(size: 16)).frame(minHeight: 100).padding(8).overlay(
                RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.15)))
              HStack {
                Button("답글 저장") {
                  Task {
                    await act("reply")
                  }
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(
                  working
                    || store.drafts.body(request.id).trimmingCharacters(in: .whitespacesAndNewlines)
                      .isEmpty
                )
                Spacer()
                Button(request.resolved ? "다시 열기" : "대화 정리") {
                  Task {
                    await act(request.resolved ? "reopen" : "resolve")
                  }
                }
                .buttonStyle(WorkspaceButtonStyle())
              }
            } else {
              VStack(alignment: .leading, spacing: 20) {
                Text("✳").font(.system(size: 40)).foregroundStyle(
                  Color(red: 0.65, green: 0.53, blue: 0.30))
                Text("필요할 때, 작게 바꿔요").font(.system(size: 24, weight: .semibold))
                Text("구체적인 불편함을 남기면 제안과 결정의 맥락을 이곳에 보관합니다.").foregroundStyle(mutedInk).lineSpacing(
                  7)
                Text("대화 내용은 실행 명령이 아닙니다. 이 화면은 코드를 실행하거나 스스로 배포하지 않습니다.").font(.system(size: 14))
                  .foregroundStyle(mutedInk).lineSpacing(7)
              }
              .padding(.vertical, 35)
            }
            Divider()
            Text("도구로 남긴 실제 답변을 새로고침으로 확인해요.").font(.system(size: 14)).foregroundStyle(mutedInk)
          }
          .padding(25).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(
            RoundedRectangle(cornerRadius: 12))
        }
      }
      .padding(30)
    }
  }

  func proposalField(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.system(size: 14, weight: .semibold))
      Text(text).font(.system(size: 16)).lineSpacing(6)
    }
  }

  func act(_ kind: String) async {
    guard let request else {
      return
    }
    let body = store.drafts.body(request.id)
    working = true
    defer {
      working = false
    }
    do {
      try await store.toolAction(request, kind: kind, body: kind == "reply" ? body : nil)
      if kind == "reply" {
        store.drafts.clearSubmitted(request.id, body: body)
      }
    } catch {
      store.error = error.localizedDescription
      try? await store.loadTools()
    }
  }

}
