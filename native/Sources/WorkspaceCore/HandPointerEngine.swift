import Foundation

public enum HandJoint: CaseIterable, Sendable { case thumbTip, indexTip, indexMCP, littleMCP, wrist }
public struct HandPoint: Equatable, Sendable {
    public var x: Double; public var y: Double; public var confidence: Double
    public init(x: Double, y: Double, confidence: Double = 1) { self.x = x; self.y = y; self.confidence = confidence }
    var valid: Bool { x.isFinite && y.isFinite && confidence.isFinite && (0...1).contains(x) && (0...1).contains(y) && (0.65...1).contains(confidence) }
}
public struct HandRegion: Equatable, Sendable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    var valid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.000000001 && y + height <= 1.000000001 }
    public func contains(_ p: HandPoint) -> Bool { valid && p.valid && p.x >= x && p.y >= y && p.x <= x + width && p.y <= y + height }
}
public struct HandMapping: Equatable, Sendable {
    public var region: HandRegion; public var mirrored: Bool
    public init(region: HandRegion, mirrored: Bool) { self.region = region; self.mirrored = mirrored }
    public func map(_ p: HandPoint) -> HandPoint? {
        guard p.valid, region.valid else { return nil }
        let topY = 1 - p.y
        guard p.x >= region.x - 1e-12, p.x <= region.x + region.width + 1e-12, topY >= region.y - 1e-12, topY <= region.y + region.height + 1e-12 else { return nil }
        let x = min(1, max(0, (p.x - region.x) / region.width))
        return HandPoint(x: mirrored ? 1 - x : x, y: min(1, max(0, (topY - region.y) / region.height)), confidence: p.confidence)
    }
}
public struct HandFrame: Sendable {
    public var time: Double; public var imageWidth: Double; public var imageHeight: Double; public var handCount: Int; public var joints: [HandJoint: HandPoint]
    public init(time: Double, imageWidth: Double, imageHeight: Double, handCount: Int, joints: [HandJoint: HandPoint]) { self.time = time; self.imageWidth = imageWidth; self.imageHeight = imageHeight; self.handCount = handCount; self.joints = joints }
}
public struct HandContext: Equatable, Sendable {
    public var id: String; public var versionID: String; public var playheadMs: Int; public var eligible: Bool
    public init(id: String, versionID: String, playheadMs: Int, eligible: Bool) { self.id = id; self.versionID = versionID; self.playheadMs = playheadMs; self.eligible = eligible }
}
public struct HandTarget: Equatable, Sendable {
    public enum Kind: Sendable { case visibleRequest, videoSurface }
    public var id: String; public var kind: Kind; public var bounds: HandRegion
    public init(id: String, kind: Kind, bounds: HandRegion) { self.id = id; self.kind = kind; self.bounds = bounds }
}
public enum HandAction: Equatable, Sendable { case selectVisibleRequest(String), startPointDraft(HandPoint) }
public struct HandFeedback: Equatable, Sendable {
    public enum Phase: Sendable { case idle, hovering, ready, pinching, releasing }
    public var pointer: HandPoint?; public var phase: Phase; public var lockedTarget: HandTarget?; public var lockedContext: HandContext?; public var action: HandAction?
    public init(pointer: HandPoint?, phase: Phase, lockedTarget: HandTarget?, lockedContext: HandContext?, action: HandAction?) {
        self.pointer = pointer; self.phase = phase; self.lockedTarget = lockedTarget; self.lockedContext = lockedContext; self.action = action
    }
    public static let idle = HandFeedback(pointer: nil, phase: .idle, lockedTarget: nil, lockedContext: nil, action: nil)
}
public struct HandPointerEngine: Sendable {
    public let mapping: HandMapping
    private var lastTime: Double?
    private var receivedAt: Double?
    private var feedback = HandFeedback.idle
    private var currentContext: HandContext?
    private var hoverTarget: HandTarget?
    private var hoverSince: Double?
    private var openSince: Double?
    private var lockedTarget: HandTarget?
    private var lockedContext: HandContext?
    private var lockedPoint: HandPoint?
    private var releaseSince: Double?
    public init(mapping: HandMapping) { self.mapping = mapping }
    public static func pinchRatio(frame: HandFrame) -> Double? {
        guard frame.handCount == 1, frame.imageWidth.isFinite, frame.imageHeight.isFinite, frame.imageWidth > 0, frame.imageHeight > 0,
              HandJoint.allCases.allSatisfy({ frame.joints[$0]?.valid == true }),
              let a = frame.joints[.indexTip], let b = frame.joints[.thumbTip], let c = frame.joints[.indexMCP], let d = frame.joints[.littleMCP] else { return nil }
        func distance(_ a: HandPoint, _ b: HandPoint) -> Double { hypot((a.x - b.x) * frame.imageWidth, (a.y - b.y) * frame.imageHeight) }
        let palm = distance(c,d); guard palm > 0.000001 else { return nil }
        let ratio = distance(a,b) / palm
        return ratio.isFinite ? ratio : nil
    }
    public mutating func process(frame: HandFrame, now: Double, context: HandContext, targets: [HandTarget]) -> HandFeedback {
        guard now.isFinite, frame.time.isFinite, frame.time <= now + 0.001, now - frame.time <= 0.15, lastTime.map({ frame.time > $0 }) ?? true else { reset(); return feedback }
        let previousTime = lastTime
        lastTime = frame.time
        guard context.eligible, let ratio = Self.pinchRatio(frame: frame), let raw = frame.joints[.indexTip].flatMap(mapping.map) else { reset(); return feedback }
        if currentContext != context || receivedAt.map({ now - $0 > 0.15 || now < $0 }) == true { reset() }
        currentContext = context
        let pointer: HandPoint
        if let old = feedback.pointer, let previousTime {
            let alpha = 1 - exp(-(frame.time - previousTime) / 0.08)
            pointer = HandPoint(x: old.x + alpha * (raw.x - old.x), y: old.y + alpha * (raw.y - old.y), confidence: raw.confidence)
        } else { pointer = raw }
        receivedAt = now
        if let lock = lockedTarget, let lockedContext, let lockedPoint {
            guard lockedContext == context, targets.contains(lock) else {
                reset(); currentContext = context; receivedAt = now
                feedback.pointer = pointer; feedback.phase = .hovering
                return feedback
            }
            var action: HandAction?
            if ratio >= 0.45 {
                if releaseSince == nil { releaseSince = now }
                if now - releaseSince! >= 0.1 - 1e-9 {
                    // The camera ROI maps to the app surface; remove the actual video letterbox here.
                    let videoPoint = HandPoint(x: (lockedPoint.x - lock.bounds.x) / lock.bounds.width, y: (lockedPoint.y - lock.bounds.y) / lock.bounds.height, confidence: lockedPoint.confidence)
                    action = lock.kind == .visibleRequest ? .selectVisibleRequest(lock.id) : .startPointDraft(videoPoint)
                    self.lockedTarget = nil; self.lockedContext = nil; self.lockedPoint = nil
                    releaseSince = nil; hoverTarget = nil; hoverSince = nil; openSince = now
                }
            } else { releaseSince = nil }
            feedback = HandFeedback(pointer: pointer, phase: action != nil ? .hovering : (releaseSince != nil ? .releasing : .pinching), lockedTarget: lock, lockedContext: lockedContext, action: action)
            return feedback
        }
        // Only app-visible targets participate; annotations take priority over the video surface.
        let requests = targets.filter { $0.kind == .visibleRequest && $0.bounds.contains(pointer) }
        let surfaces = targets.filter { $0.kind == .videoSurface && $0.bounds.contains(pointer) }
        let target: HandTarget? = requests.count == 1 ? requests[0] : (requests.isEmpty && surfaces.count == 1 ? surfaces[0] : nil)
        let wasReady = feedback.phase == .ready && target != nil && target == hoverTarget
        if target != hoverTarget { hoverTarget = target; hoverSince = target == nil ? nil : now }
        if ratio >= 0.45 { if openSince == nil { openSince = now } } else { openSince = nil }
        if wasReady, ratio <= 0.25, let target {
            lockedTarget = target; lockedContext = context; lockedPoint = pointer; releaseSince = nil
            feedback = HandFeedback(pointer: pointer, phase: .pinching, lockedTarget: target, lockedContext: context, action: nil)
        } else {
            let ready = target != nil && openSince.map({ now - $0 >= 0.2 - 1e-9 }) == true && hoverSince.map({ now - $0 >= 0.3 - 1e-9 }) == true
            feedback = HandFeedback(pointer: pointer, phase: (ready || wasReady) ? .ready : .hovering, lockedTarget: nil, lockedContext: nil, action: nil)
        }
        return feedback
    }
    public mutating func tick(now: Double) -> HandFeedback {
        if !now.isFinite || receivedAt.map({ now - $0 > 0.15 || now < $0 }) ?? false { reset() }
        feedback.action = nil; return feedback
    }
    public mutating func cancel() { reset(); lastTime = nil }
    private mutating func reset() {
        feedback = .idle; receivedAt = nil; currentContext = nil
        hoverTarget = nil; hoverSince = nil; openSince = nil
        lockedTarget = nil; lockedContext = nil; lockedPoint = nil; releaseSince = nil
    }
}
