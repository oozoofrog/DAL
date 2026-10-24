import AVFoundation
import SwiftUI

struct PlayerSurface: NSViewRepresentable {

  let player: AVPlayer
  func makeNSView(context: Context) -> SurfaceView {
    let view = SurfaceView()
    view.playerLayer.player = player
    return view
  }

  func updateNSView(_ nsView: SurfaceView, context: Context) {
    nsView.playerLayer.player = player
  }

  final class SurfaceView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.backgroundColor = NSColor.black.cgColor
      playerLayer.videoGravity = .resizeAspect
      layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) {
      fatalError("init(coder:) unavailable")
    }
    override func layout() {
      super.layout()
      playerLayer.frame = bounds
    }
  }

}
