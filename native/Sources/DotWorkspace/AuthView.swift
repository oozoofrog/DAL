import SwiftUI
import WebKit
import WorkspaceCore

struct AuthenticationSheet: View {

  @EnvironmentObject var store: WorkspaceStore
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text("비공개 작업실 로그인").font(.system(size: 20, weight: .semibold))
          Text("공식 로그인 페이지입니다. 로그인 세션은 앱을 닫으면 지워집니다.").font(.system(size: 14)).foregroundStyle(
            .secondary)
        }
        Spacer()
        Button("닫기") {
          store.showingAuth = false
        }
        .buttonStyle(WorkspaceButtonStyle())
      }
      .padding(20)
      Divider()
      AuthenticationWebView(store: store)
      if let error = store.error {
        Text(error).font(.system(size: 14)).foregroundStyle(.red).padding(15)
      }
    }
    .frame(width: 650, height: 760).background(ivory).foregroundStyle(ink).preferredColorScheme(
      .light)
  }

}

struct AuthenticationWebView: NSViewRepresentable {

  let store: WorkspaceStore
  func makeCoordinator() -> Coordinator {
    Coordinator(store: store)
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.uiDelegate = context.coordinator
    view.load(URLRequest(url: store.client.boundary.origin))
    return view
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
  }

  @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

    weak var store: WorkspaceStore?
    var checking = false
    init(store: WorkspaceStore) {
      self.store = store
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard let url = webView.url else { return }
      #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DOT_AUTH_STATE_PATH"] {
          let state: [String: String] = [
            "state": "loaded", "host": url.host ?? "", "path": url.path,
          ]
          if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
          }
        }
      #endif
      #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DOT_AUTH_SNAPSHOT_PATH"] {
          webView.takeSnapshot(with: nil) { image, _ in
            if let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
            {
              try? png.write(to: URL(fileURLWithPath: path))
            }
          }
        }
      #endif
      guard let store, store.client.boundary.permits(url), !checking else { return }
      checking = true
      webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
        [weak self, weak store] cookies in
        Task {
          @MainActor in
          defer {
            self?.checking = false
          }
          guard let store else {
            return
          }
          let valid = store.client.boundary.cookies(
            cookies, for: store.client.boundary.origin.appendingPathComponent("api/projects"))
          if !valid.isEmpty {
            await store.connect(cookies: valid)
          }
        }
      }
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      store?.error = "로그인 페이지를 열지 못했습니다. \(error.localizedDescription)"
    }

    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
      }
      return nil
    }

  }

}
