import AVFoundation
import SwiftUI
import WorkspaceCore

@MainActor final class MediaController: ObservableObject {

  let player = AVPlayer(), resultPlayer = AVPlayer()
  @Published var duration = 0.0
  @Published var resultDuration = 0.0
  @Published var time = 0.0
  @Published var size = CGSize.zero
  @Published private(set) var loadedOfflineVersion: OfflineVersion?
  @Published private(set) var loadedSelectionID: UUID?
  @Published var playing = false
  @Published var comparing = false
  @Published var error: String?
  @Published var loading = false
  @Published var localURL: URL?
  @Published var sourceVersionID: String?
  @Published var resultVersionID: String?
  func loadPair(source: AVURLAsset, sourceID: String, result: AVURLAsset?, resultID: String?) async
  {
    await loadAsset(source, versionID: sourceID)
    guard !Task.isCancelled else { return }
    await loadResultAsset(result, versionID: resultID)
  }
  private var observer: Any?
  private var sourceToken = UUID(), resultToken = UUID()
  var playbackRange: ReviewRange?
  init() {
    observer = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
    ) {
      [weak self] value in
      Task {
        @MainActor in
        guard let self else {
          return
        }
        guard value.seconds.isFinite else { return }
        self.time = value.seconds
        self.playing = self.player.rate != 0
        if let range = self.playbackRange, value.seconds * 1000 >= Double(range.endMs) {
          self.pause()
          self.seek(Double(range.startMs) / 1000)
        }
      }
    }
  }

  func pause() {
    player.pause()
    resultPlayer.pause()
    playing = false
  }

  func clear() {
    pause()
    player.replaceCurrentItem(with: nil)
    resultPlayer.replaceCurrentItem(with: nil)
    duration = 0
    size = .zero
    loading = false
    localURL = nil
    loadedOfflineVersion = nil
    loadedSelectionID = nil
    resultDuration = 0
    sourceVersionID = nil
    resultVersionID = nil
    time = 0
    comparing = false
    playbackRange = nil
    error = nil
    sourceToken = UUID()
    resultToken = UUID()
  }

  func load(version: Version?, result: Version? = nil, store: WorkspaceStore) async {
    guard let version, let hash = version.mediaHash, let url = store.client.mediaURL(hash: hash),
      store.connected
    else {
      clear()
      return
    }
    localURL = nil
    let source = AVURLAsset(
      url: url, options: [AVURLAssetHTTPCookiesKey: store.client.mediaCookies(for: url)])
    var resultAsset: AVURLAsset?
    if let resultHash = result?.mediaHash, let resultURL = store.client.mediaURL(hash: resultHash) {
      resultAsset = AVURLAsset(
        url: resultURL,
        options: [AVURLAssetHTTPCookiesKey: store.client.mediaCookies(for: resultURL)])
    }
    await loadPair(source: source, sourceID: version.id, result: resultAsset, resultID: result?.id)
  }
  func loadLocal(_ url: URL) async {
    await loadAsset(AVURLAsset(url: url), localURL: url)
  }

  func isReadyForOffline(_ version: OfflineVersion?, selectionID: UUID) -> Bool {
    guard let version else { return false }
    return !loading && player.currentItem != nil && duration > 0 && size.width > 0 && size.height > 0
      && loadedOfflineVersion == version && loadedSelectionID == selectionID
      && Int((duration * 1000).rounded()) == version.durationMs
  }
  func loadOffline(_ version: OfflineVersion, selectionID: UUID) async {
    let url = URL(fileURLWithPath: version.sourceLocator)
    await loadAsset(AVURLAsset(url: url), versionID: version.id, localURL: url, offlineVersion: version, selectionID: selectionID)
  }
  private func loadAsset(_ asset: AVURLAsset, versionID: String? = nil, localURL: URL? = nil, offlineVersion: OfflineVersion? = nil, selectionID: UUID? = nil) async {
    clear()
    let token = UUID()
    sourceToken = token
    pause()
    duration = 0
    loading = true
    error = nil
    defer {
      if sourceToken == token {
        loading = false
      }
    }
    do {
      let duration = try await asset.load(.duration).seconds
      guard duration.isFinite, duration > 0 else {
        throw ConnectionError.server("영상 길이를 확인하지 못했습니다.")
      }
      let tracks = try await asset.loadTracks(withMediaType: .video)
      guard let track = tracks.first else { throw ConnectionError.server("영상 트랙을 확인하지 못했습니다.") }
      let raw = try await track.load(.naturalSize)
      let transform = try await track.load(.preferredTransform)
      let rect = CGRect(origin: .zero, size: raw).applying(transform)
      let natural = CGSize(width: abs(rect.width), height: abs(rect.height))
      guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0 else { throw ConnectionError.server("영상 크기를 확인하지 못했습니다.") }
      if let offlineVersion, Int((duration * 1000).rounded()) != offlineVersion.durationMs { throw ConnectionError.server("기록한 영상 길이와 달라요.") }
      guard sourceToken == token, !Task.isCancelled else {
        return
      }
      self.duration = duration
      sourceVersionID = versionID
      self.localURL = localURL
      loadedOfflineVersion = offlineVersion
      loadedSelectionID = selectionID
      size = natural
      player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
      time = 0
    } catch {
      if sourceToken == token {
        self.error = "영상을 열지 못했습니다. \(error.localizedDescription)"
      }
    }
  }

  private func loadResultAsset(_ asset: AVURLAsset?, versionID: String?) async {
    let token = UUID()
    resultToken = token
    resultDuration = 0
    resultVersionID = nil
    resultPlayer.replaceCurrentItem(with: nil)
    guard let asset else { return }
    do {
      let duration = try await asset.load(.duration).seconds
      guard resultToken == token, duration.isFinite, !Task.isCancelled else { return }
      resultDuration = duration
      resultVersionID = versionID
      resultPlayer.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    } catch {
      if resultToken == token { self.error = "결과 영상을 확인하지 못했습니다. \(error.localizedDescription)" }
    }
  }

  func seek(_ seconds: Double) {
    let value = max(0, min(seconds, duration))
    let target = CMTime(seconds: value, preferredTimescale: 600)
    player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    if comparing {
      resultPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    time = value
  }

  func toggle(range: ReviewRange? = nil) {
    if player.rate != 0 {
      pause()
      return
    }
    play(range: range)
  }

  func play(range: ReviewRange? = nil) {
    guard duration > 0 else {
      return
    }
    playbackRange = range
    if let range {
      seek(Double(range.startMs) / 1000)
    }
    if comparing {
      guard let range, range.fits(actualDuration: duration),
        range.fits(actualDuration: resultDuration)
      else {
        error = "두 영상에서 같은 구간을 확인하지 못했습니다."
        return
      }
      let target = CMTime(seconds: Double(range.startMs) / 1000, preferredTimescale: 600)
      player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) {
        [weak self] _ in
        Task {
          @MainActor in
          guard let self else {
            return
          }
          self.resultPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] _ in
            Task {
              @MainActor in
              guard let self else {
                return
              }
              let host = CMTimeAdd(
                CMClockGetTime(CMClockGetHostTimeClock()),
                CMTime(seconds: 0.15, preferredTimescale: 600))
              self.player.setRate(1, time: target, atHostTime: host)
              self.resultPlayer.setRate(1, time: target, atHostTime: host)
            }
          }
        }
      }
    } else {
      player.play()
    }
    playing = true
  }

}
