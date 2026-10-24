import SwiftUI

struct ConnectionStatusView: View {
  @EnvironmentObject var store: WorkspaceStore
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Label("dot 연결 상태", systemImage: "circle.dotted").font(.system(size: 25, weight: .semibold))
      StatusPill(label: "연결되지 않음")
      Text("DAL에서 웹사이트를 열거나 로그인하지 않아요.").font(.system(size: 19, weight: .medium))
      Text("현재 앱에는 dot과 대화를 주고받는 연결 통로가 없어요. 기기 영상 재생과 구간 탐색은 사용할 수 있어요.")
        .font(.system(size: 16)).lineSpacing(7).foregroundStyle(mutedInk)
      Text("기존 서버 기록은 유지돼요. dot의 별도 도구 연결이 있어도 DAL 앱이 연결된 것은 아니에요.")
        .font(.system(size: 14)).lineSpacing(6).foregroundStyle(mutedInk)
      HStack { Spacer(); Button("닫기") { store.dismissConnectionStatus() }.buttonStyle(WorkspaceButtonStyle(prominent: true)).keyboardShortcut(.cancelAction) }
    }.padding(32).frame(width: 580).background(ivory).foregroundStyle(ink)
  }
}
