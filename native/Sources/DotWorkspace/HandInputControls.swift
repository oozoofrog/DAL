import SwiftUI
import WorkspaceCore

@MainActor enum HandSessionFactory {
    static var isSynthetic: Bool {
        #if DEBUG
        return OfflineFixtureRunner.isHandQA
        #else
        return false
        #endif
    }
    @MainActor static func make() -> HandInputSession {
        #if DEBUG
        if let synthetic = OfflineFixtureRunner.handSessionForQA() { return synthetic }
        #endif
        return HandInputSession(permission: AppleHandPermission(), driver: CameraHandDriver(), now: { ProcessInfo.processInfo.systemUptime }, mapping: HandMapping(region: HandRegion(x: 0.2, y: 0.15, width: 0.6, height: 0.7), mirrored: true))
    }
}

struct HandInputControls: View {
    @ObservedObject var session: HandInputSession
    let context: HandContext
    @Binding var region: HandRegion
    @Binding var mirrored: Bool
    let synthetic: Bool
    @State private var expanded = false
    @FocusState private var editingRange: Bool
    private var mappingValid: Bool {
        [region.x,region.y,region.width,region.height].allSatisfy(\.isFinite) && region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0 && region.x + region.width <= 1 && region.y + region.height <= 1
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(synthetic ? "카메라 꺼짐 · 합성 손 좌표 시험" : "손 입력 · \(session.state == .running ? "사용 중" : "꺼짐")")
                .font(.system(size: 16, weight: .semibold))
            DisclosureGroup("손으로 표시하기 (실험)", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("켜고 카메라를 직접 선택한 뒤 시작해요. 영상과 손 좌표는 저장하거나 전송하지 않아요.").font(.system(size: 14)).foregroundStyle(mutedInk)
                    if session.state == .off || session.state == .denied || session.state == .unavailable {
                        Button("이번 실행에서 손 입력 켜기") { Task { await session.enableFromUserAction(context: context) } }
                            .buttonStyle(WorkspaceButtonStyle()).disabled(!context.eligible || !mappingValid)
                    } else if session.state == .choosingDevice {
                        Picker("카메라 선택", selection: Binding(get: { session.selectedDeviceID ?? "" }, set: { session.chooseDevice(id: $0) })) {
                            Text("직접 선택해 주세요").tag("")
                            ForEach(session.choices) { Text($0.label).tag($0.id) }
                        }.font(.system(size: 16))
                        Button("선택한 카메라로 시작") { Task { await session.startSelectedDeviceFromUserAction(context: context) } }
                            .buttonStyle(WorkspaceButtonStyle()).disabled(session.selectedDeviceID == nil || !context.eligible || !mappingValid)
                    } else if session.state == .requestingPermission || session.state == .discovering || session.state == .starting {
                        Text("허용 상태와 선택한 카메라를 확인하고 있어요.").font(.system(size: 14))
                    }
                    if session.state != .off { Button("손 입력 끄기") { session.disable() }.buttonStyle(WorkspaceButtonStyle()) }
                    Toggle("좌우 반전", isOn: $mirrored).font(.system(size: 16))
                    HStack {
                        field("왼쪽", value: $region.x); field("위", value: $region.y)
                        field("너비", value: $region.width); field("높이", value: $region.height)
                    }
                    Text("입력 범위는 0–1이에요. 반전이나 범위를 바꾸면 입력을 끄고 다시 선택해요.").font(.system(size: 14)).foregroundStyle(mutedInk)
                    if !mappingValid { Text("범위가 화면 안에 들어오도록 값을 확인해 주세요.").font(.system(size: 14)) }
                    if !context.eligible { Text("영상을 멈추고 입력 중인 초안을 정리한 뒤 사용할 수 있어요.").font(.system(size: 14)).foregroundStyle(mutedInk) }
                    if let message = session.message { Text(message).font(.system(size: 14)) }
                    Text("손을 펴서 잠시 가리킨 뒤 집었다 놓으면 선택하거나 저장 전 점을 만들어요. 저장·내보내기는 버튼으로 해요. 실제 카메라 환경의 정확도는 아직 확인하지 않았어요.").font(.system(size: 14)).foregroundStyle(mutedInk)
                }.padding(.top, 12)
            }.font(.system(size: 16))
        }.onChange(of: editingRange) { _, focused in if focused { session.disable() } }
        .padding(14).background(ink.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func field(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 14)); TextField(label, value: value, format: .number).focused($editingRange).textFieldStyle(.roundedBorder).font(.system(size: 16)).frame(minHeight: 44) }
    }
}
