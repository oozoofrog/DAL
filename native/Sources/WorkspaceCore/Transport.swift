import Foundation

public final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  let boundary: SiteBoundary
  public init(boundary: SiteBoundary) { self.boundary = boundary }
  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(request.url.map(boundary.permits) == true ? request : nil) }
}
@MainActor public final class SiteSession {
  public let boundary: SiteBoundary
  private var authCookies: [HTTPCookie] = []
  private var session: URLSession
  public private(set) var connected = false
  public var onExpired: (() -> Void)?
  public init(origin: URL) {
    boundary = SiteBoundary(origin: origin)
    let c = URLSessionConfiguration.ephemeral
    c.httpCookieStorage = nil
    c.httpShouldSetCookies = false
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.timeoutIntervalForRequest = 30
    session = URLSession(
      configuration: c, delegate: SameOriginRedirects(boundary: boundary), delegateQueue: nil)
  }
  public func disconnect() {
    connected = false
    authCookies = []
    session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    onExpired?()
  }
  public func mediaCookies(for url: URL) -> [HTTPCookie] { boundary.cookies(authCookies, for: url) }
  public func mediaURL(hash: String) -> URL? {
    guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
      return nil
    }
    return URL(string: "/api/media/\(hash)", relativeTo: boundary.origin)?.absoluteURL
  }
  public func request<T: Decodable>(
    path: String, method: String = "GET", body: [String: Any]? = nil
  ) async throws -> T {
    guard connected else { throw ConnectionError.notConnected }
    guard let url = URL(string: path, relativeTo: boundary.origin)?.absoluteURL,
      boundary.permits(url), url.path.hasPrefix("/api/")
    else { throw ConnectionError.invalidOrigin }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let cookies = boundary.cookies(authCookies, for: url)
    for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
      request.setValue(v, forHTTPHeaderField: k)
    }
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return try await perform(request)
  }
  public func upload(
    file: URL, label: String, durationMs: Int, fps: Double, projectId: String, artifactId: String
  ) async throws -> MutationResult {
    guard connected else { throw ConnectionError.notConnected }
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 30 * 1024 * 1024 else {
      throw ConnectionError.server("영상은 30MB 이하로 선택해 주세요.")
    }
    let url = boundary.origin.appendingPathComponent("api/media")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpShouldHandleCookies = false
    request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
    request.setValue(
      label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "video",
      forHTTPHeaderField: "x-video-label")
    request.setValue(String(durationMs), forHTTPHeaderField: "x-video-duration-ms")
    request.setValue(String(fps), forHTTPHeaderField: "x-video-fps")
    request.setValue(projectId, forHTTPHeaderField: "x-project-id")
    request.setValue(artifactId, forHTTPHeaderField: "x-artifact-id")
    for (k, v) in HTTPCookie.requestHeaderFields(with: boundary.cookies(authCookies, for: url)) {
      request.setValue(v, forHTTPHeaderField: k)
    }
    let (data, response) = try await session.upload(for: request, fromFile: file)
    return try validate(data, response)
  }
  private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)
    return try validate(data, response)
  }
  private func validate<T: Decodable>(_ data: Data, _ response: URLResponse) throws -> T {
    guard let r = response as? HTTPURLResponse, let url = r.url, boundary.permits(url) else {
      throw ConnectionError.invalidResponse
    }
    if [301, 302, 303, 307, 308, 401, 403].contains(r.statusCode) {
      disconnect()
      throw ConnectionError.authenticationExpired
    }
    guard (200...299).contains(r.statusCode) else {
      throw ConnectionError.server(
        (try? JSONDecoder().decode(ServerFailure.self, from: data).error)
          ?? "서버에 저장하지 못했습니다. 다시 시도해 주세요.")
    }
    guard r.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true else {
      throw ConnectionError.invalidResponse
    }
    do { return try JSONDecoder().decode(T.self, from: data) } catch {
      throw ConnectionError.invalidResponse
    }
  }
}
