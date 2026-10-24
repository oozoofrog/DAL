import AVFoundation
import Testing

@testable import DotWorkspace

@MainActor @Test func missingProjectVideoClearsPreviousPlayer() async {
  let media = MediaController()
  let store = WorkspaceStore()
  media.duration = 12
  media.player.replaceCurrentItem(
    with: AVPlayerItem(url: URL(fileURLWithPath: "/tmp/stale-test.mp4")))
  await media.load(version: nil, store: store)
  #expect(media.player.currentItem == nil)
  #expect(media.duration == 0)
}
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"] != nil))
func sequentialPairLoadPreservesSourceAndDeliveredReadiness() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["DOT_TEST_VIDEO"])
  let controller = MediaController()
  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  await controller.loadPair(source: asset, sourceID: "anchor", result: asset, resultID: "delivered")
  #expect(controller.duration > 0)
  #expect(controller.resultDuration > 0)
  #expect(controller.sourceVersionID == "anchor")
  #expect(controller.resultVersionID == "delivered")
  #expect(controller.player.currentItem != nil)
  #expect(controller.resultPlayer.currentItem != nil)
}
