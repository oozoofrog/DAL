import Foundation

public struct SiteBoundary: Sendable {
  public let origin: URL
  public init(origin: URL) { self.origin = origin }
  public func permits(_ url: URL) -> Bool {
    url.scheme == "https" && url.scheme == origin.scheme
      && url.host?.lowercased() == origin.host?.lowercased() && url.port == origin.port
      && url.user == nil && url.password == nil
  }
  public func cookies(_ input: [HTTPCookie], for url: URL) -> [HTTPCookie] {
    guard permits(url), let host = url.host?.lowercased() else { return [] }
    return input.filter { cookie in
      let domain = cookie.domain.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "."))
      let path = cookie.path
      let pathMatches =
        url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/")
      return (host == domain || host.hasSuffix("." + domain)) && pathMatches
        && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }
  }
}
public struct Annotation: Codable, Hashable, Sendable {
  public var type: String
  public var x: Double
  public var y: Double
  public var x2: Double?
  public var y2: Double?
  public init(type: String, x: Double, y: Double, x2: Double? = nil, y2: Double? = nil) {
    self.type = type
    self.x = x
    self.y = y
    self.x2 = x2
    self.y2 = y2
  }
  public var isValid: Bool {
    guard ["point", "rectangle", "arrow"].contains(type),
      [x, y].allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else { return false }
    if type == "point" { return true }
    guard let x2, let y2, [x2, y2].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      return false
    }
    return type == "rectangle" ? x2 > x && y2 > y : hypot(x2 - x, y2 - y) > 0.005
  }
  public var json: [String: Any] {
    var d: [String: Any] = ["type": type, "x": x, "y": y]
    if let x2 { d["x2"] = x2 }
    if let y2 { d["y2"] = y2 }
    return d
  }
}
public struct ReviewRange: Sendable {
  public var startMs: Int
  public var endMs: Int
  public init(startMs: Int, endMs: Int) {
    self.startMs = startMs
    self.endMs = endMs
  }
  public func fits(actualDuration: Double) -> Bool {
    actualDuration.isFinite && startMs >= 0 && endMs > startMs
      && Double(endMs) <= ((actualDuration * 1000).rounded())
  }
}
public struct VideoContentBox: Sendable {
  public let left: Double
  public let top: Double
  public let width: Double
  public let height: Double
  public init(
    containerWidth: Double, containerHeight: Double, videoWidth: Double, videoHeight: Double
  ) {
    let scale = min(containerWidth / max(videoWidth, 1), containerHeight / max(videoHeight, 1))
    width = videoWidth * scale
    height = videoHeight * scale
    left = (containerWidth - width) / 2
    top = (containerHeight - height) / 2
  }
  public func normalized(x: Double, y: Double) -> (x: Double, y: Double)? {
    guard width > 0, height > 0 else { return nil }
    let px = (x - left) / width
    let py = (y - top) / height
    return (0...1).contains(px) && (0...1).contains(py) ? (px, py) : nil
  }
}
public struct DraftStore: Sendable {
  private struct Draft: Sendable {
    var body = ""
    var kind = "reply"
  }
  private var values: [String: Draft] = [:]
  public init() {}
  public mutating func set(_ id: String, body: String) {
    var draft = values[id] ?? Draft()
    draft.body = body
    values[id] = draft
  }
  public func body(_ id: String) -> String { values[id]?.body ?? "" }
  public func kind(_ id: String) -> String { values[id]?.kind ?? "reply" }
  public mutating func setKind(_ id: String, kind: String) {
    guard ["reply", "rerequest"].contains(kind) else { return }
    var draft = values[id] ?? Draft()
    draft.kind = kind
    values[id] = draft
  }
  public mutating func clearSubmitted(_ id: String, body: String, kind: String = "reply") {
    if values[id]?.body == body && values[id]?.kind == kind { values[id] = Draft() }
  }
}
public struct OperationKeys: Sendable {
  private var values: [String: String] = [:]
  public init() {}
  public mutating func key(for fingerprint: String) -> String {
    if let key = values[fingerprint] { return key }
    let key = UUID().uuidString
    values[fingerprint] = key
    return key
  }
  public mutating func confirm(_ fingerprint: String) { values.removeValue(forKey: fingerprint) }
}
public func timeLabel(_ milliseconds: Int) -> String {
  let s = Double(max(0, milliseconds)) / 1000
  return String(format: "%02d:%05.2f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
}
public let statusLabels: [String: String] = [
  "requested": "요청됨", "understood": "이해 확인", "proposed": "수정 제안", "in_progress": "제작 중",
  "completed": "결과 도착", "approved": "승인됨", "revision_requested": "다시 요청",
]
