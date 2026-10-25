import Foundation
import WorkspaceCore

struct HandVideoGeometry: Equatable {
    let width: Double; let height: Double; let videoWidth: Double; let videoHeight: Double
    var valid: Bool { [width,height,videoWidth,videoHeight].allSatisfy { $0.isFinite && $0 > 0 } }
}
struct HandVisibleAnnotation {
    let id: String; let versionID: String; let startMs: Int; let endMs: Int; let annotation: Annotation
}
struct HandInputSurface {
    let context: HandContext; let targets: [HandTarget]
}
/// This allowlist returns unsaved values only. It has no repository or export reference.
enum HandInputPolicy {
    static func surface(versionID: String?, selectionID: String, playheadMs: Int, sourceReady: Bool, paused: Bool, focused: Bool, typing: Bool, hasUnsavedDraft: Bool, geometry: HandVideoGeometry, visible: HandVisibleAnnotation?) -> HandInputSurface {
        let eligible = versionID != nil && playheadMs >= 0 && sourceReady && paused && focused && !typing && !hasUnsavedDraft && geometry.valid
        let identity = "\(selectionID)|\(geometry.width)|\(geometry.height)|\(geometry.videoWidth)|\(geometry.videoHeight)"
        let context = HandContext(id: identity, versionID: versionID ?? "", playheadMs: playheadMs, eligible: eligible)
        guard eligible else { return HandInputSurface(context: context, targets: []) }
        let box = VideoContentBox(containerWidth: geometry.width, containerHeight: geometry.height, videoWidth: geometry.videoWidth, videoHeight: geometry.videoHeight)
        let video = HandRegion(x: box.left / geometry.width, y: box.top / geometry.height, width: box.width / geometry.width, height: box.height / geometry.height)
        var targets = [HandTarget(id: "video", kind: .videoSurface, bounds: video)]
        if let visible, visible.versionID == versionID, playheadMs >= visible.startMs, playheadMs <= visible.endMs, visible.annotation.isValid {
            let a = visible.annotation
            let minimumX = 44 / box.width; let minimumY = 44 / box.height
            let x1 = min(a.x,a.x2 ?? a.x); let y1 = min(a.y,a.y2 ?? a.y)
            let x2 = max(a.x,a.x2 ?? a.x); let y2 = max(a.y,a.y2 ?? a.y)
            let left = max(0, min(x1, (x1+x2-minimumX)/2)); let top = max(0, min(y1, (y1+y2-minimumY)/2))
            let right = min(1, max(x2, left+minimumX)); let bottom = min(1, max(y2, top+minimumY))
            targets.insert(HandTarget(id: visible.id, kind: .visibleRequest, bounds: HandRegion(x: video.x + left * video.width, y: video.y + top * video.height, width: (right-left) * video.width, height: (bottom-top) * video.height)), at: 0)
        }
        return HandInputSurface(context: context, targets: targets)
    }
    static func allowedAction(_ feedback: HandFeedback, on surface: HandInputSurface) -> HandAction? {
        guard surface.context.eligible, feedback.lockedContext == surface.context, let lock = feedback.lockedTarget, surface.targets.contains(lock), let action = feedback.action else { return nil }
        switch action {
        case .selectVisibleRequest(let id):
            return lock.kind == .visibleRequest && lock.id == id ? action : nil
        case .startPointDraft(let p):
            guard lock.kind == .videoSurface, p.x.isFinite, p.y.isFinite, (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
            return action
        }
    }
}
