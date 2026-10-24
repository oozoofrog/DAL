import AppKit
import SwiftUI

@main struct DotWorkspaceApp: App {

  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var store = WorkspaceStore()
  var body: some Scene {
    WindowGroup("DAL") {
      RootView().environmentObject(store).onAppear {
        if ProcessInfo.processInfo.environment["DOT_SHOW_AUTH"] == "1" {
          store.beginLogin()
        }
      }
    }
    .defaultSize(width: 1500, height: 980).commands {
      CommandGroup(replacing: .newItem) {
        Button("새로고침") {
          Task {
            await store.refresh()
          }
        }
        .keyboardShortcut("r", modifiers: .command)
      }
      CommandGroup(after: .appInfo) {
        Button("작업실 로그인") {
          store.beginLogin()
        }
        Button("연결 끊기") {
          store.disconnect()
        }
      }
    }
  }

}
final class AppDelegate: NSObject, NSApplicationDelegate {

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    #if DEBUG
      if let path = ProcessInfo.processInfo.environment["DOT_SNAPSHOT_PATH"] {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
          guard
            let window = NSApp.keyWindow
              ?? NSApp.windows.first(where: {
                $0.isVisible
              }
              ), let view = window.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
          else {
            return
          }
          view.cacheDisplay(in: view.bounds, to: bitmap)
          if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
          }
        }
      }

    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

}
