import Foundation
import Vision
import AVFoundation
import WorkspaceCore

/// Worker-only and ephemeral. Never retains buffers or emits observations outside this call.
final class VisionHandDetector {
    private let forbidden: @Sendable () -> Bool
    init(forbidden: @escaping @Sendable () -> Bool) { self.forbidden = forbidden }
    func detect(_ sample: CMSampleBuffer, time: Double) -> HandFrame? {
        guard !forbidden(), let image = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let width = Double(CVPixelBufferGetWidth(image)); let height = Double(CVPixelBufferGetHeight(image))
        let request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 2
        do {
            try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([request])
            let results = request.results ?? []
            guard results.count == 1, let hand = results.first else { return HandFrame(time: time, imageWidth: width, imageHeight: height, handCount: results.count, joints: [:]) }
            let points = try hand.recognizedPoints(.all)
            let names: [(HandJoint,VNHumanHandPoseObservation.JointName)] = [(.thumbTip,.thumbTip),(.indexTip,.indexTip),(.indexMCP,.indexMCP),(.littleMCP,.littleMCP),(.wrist,.wrist)]
            var joints: [HandJoint: HandPoint] = [:]
            for (joint,name) in names { if let p = points[name] { joints[joint] = HandPoint(x: p.location.x, y: p.location.y, confidence: Double(p.confidence)) } }
            return HandFrame(time: time, imageWidth: width, imageHeight: height, handCount: 1, joints: joints)
        } catch { return HandFrame(time: time, imageWidth: width, imageHeight: height, handCount: 0, joints: [:]) }
    }
}
