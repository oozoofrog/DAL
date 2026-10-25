import Foundation
import CryptoKit
import AVFoundation
import Darwin

public struct MediaFingerprint: Codable, Equatable, Sendable {
  public let sha256: String
  public let byteCount: Int64
  public let durationMs: Int
  public init(sha256: String, byteCount: Int64, durationMs: Int) {
    self.sha256 = sha256; self.byteCount = byteCount; self.durationMs = durationMs
  }
}
public struct FileFingerprint: Equatable, Sendable {
  public let sha256: String
  public let byteCount: Int64
}
public enum MediaAvailability: String, Equatable, Sendable {
  case matching, missing, mismatched, unreadable
}
public enum OfflineMediaIdentity {
  private static func identity(_ url: URL) throws -> stat {
    guard url.isFileURL, url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw OfflineError.invalid("로컬 영상 파일을 선택해 주세요.") }
    var value = stat()
    guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { throw OfflineError.io("영상을 안전하게 열지 못했습니다.") }
    return value
  }
  private static func same(_ a: stat, _ b: stat) -> Bool {
    a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
      && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
      && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
  }
  public static func hashFile(_ url: URL) throws -> FileFingerprint {
    try Task.checkCancellation()
    let initial = try identity(url)
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw OfflineError.io("영상을 읽지 못했습니다.") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var opened = stat()
    guard fstat(fd, &opened) == 0, same(initial, opened) else { throw OfflineError.conflict }
    var hasher = SHA256(); var count: Int64 = 0
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
      try Task.checkCancellation(); hasher.update(data: bytes); count += Int64(bytes.count)
    }
    var final = stat()
    guard fstat(fd, &final) == 0, count == initial.st_size, same(initial, final), same(initial, try identity(url)) else { throw OfflineError.conflict }
    return FileFingerprint(sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: count)
  }
  public static func inspect(_ url: URL) async throws -> MediaFingerprint {
    try Task.checkCancellation()
    let initial = try identity(url)
    let digest = try hashFile(url)
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    let tracks = try await asset.loadTracks(withMediaType: .video)
    try Task.checkCancellation()
    guard duration.isFinite, duration > 0, duration * 1000 < Double(Int.max), !tracks.isEmpty else { throw OfflineError.invalid("영상 길이나 비디오 트랙을 확인하지 못했습니다.") }
    guard same(initial, try identity(url)) else { throw OfflineError.conflict }
    return MediaFingerprint(sha256: digest.sha256, byteCount: digest.byteCount, durationMs: Int((duration * 1000).rounded()))
  }
  public static func verify(_ url: URL, expected: MediaFingerprint) async -> MediaAvailability {
    guard url.isFileURL else { return .unreadable }
    guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
    do {
      let digest = try hashFile(url)
      guard digest.sha256 == expected.sha256, digest.byteCount == expected.byteCount else { return .mismatched }
      let media = try await inspect(url)
      return media == expected ? .matching : .mismatched
    } catch { return .unreadable }
  }
}
