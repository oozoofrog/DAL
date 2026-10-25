import AppKit
import SwiftUI
import WorkspaceCore

@main enum DALMain {
 @MainActor static func main() {
  let arguments=Array(CommandLine.arguments.dropFirst())
  if arguments.contains("--local-qa") {
   guard arguments.first=="--local-qa" else {fputs("--local-qa must be first\n",stderr);exit(2)}
   do {
    let output=try LocalQACommand.run(arguments:Array(arguments.dropFirst()),input:{try LocalQACommand.readInput(.standardInput)})
    print(output);exit(0)
   }catch{fputs(error.localizedDescription+"\n",stderr);exit(2)}
  }
  DotWorkspaceApp.main()
 }
}

struct DotWorkspaceApp: App {

  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var store = WorkspaceStore()
  var body: some Scene {
    WindowGroup("DAL") {
      Group {
        if ProcessInfo.processInfo.environment["DAL_QA_DIRECTORY"] != nil {
          RootView().environmentObject(store).onAppear {
            if ProcessInfo.processInfo.environment["DAL_SHOW_CONNECTION_STATUS"] == "1" { store.showConnectionStatus() }
          }
        } else { OfflineWorkspaceHost() }
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
        Button("dot 연결 상태") {
          store.showConnectionStatus()
        }
      }
    }
  }

}
final class AppDelegate: NSObject, NSApplicationDelegate {
  static weak var active: AppDelegate?
  var stopHandInput: (() -> Void)?
  var prepareToQuit: (() async throws -> Void)?
  private var awaitingQuit = false
  static func traceOfflineLifecycle(_ stage: String) {
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    guard ["create", "reopen", "export", "hand"].contains(env["DAL_OFFLINE_QA_MODE"] ?? ""), let root = env["DAL_OFFLINE_QA_ROOT"],
      (try? String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("DAL_TEST_FIXTURE_ONLY"), encoding: .utf8)) == "synthetic-offline-workbench-test\n" else { return }
    FileHandle.standardError.write(Data(("DAL_LIFECYCLE " + stage + "\n").utf8))
    #endif
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Self.traceOfflineLifecycle("delegate-entry")
    stopHandInput?()
    guard let prepareToQuit else { return .terminateNow }
    guard !awaitingQuit else { return .terminateLater }
    awaitingQuit = true
    Task { @MainActor in
      do {
        Self.traceOfflineLifecycle("flush-begin")
        try await prepareToQuit()
        Self.traceOfflineLifecycle("flush-end")
        Self.traceOfflineLifecycle("reply-true")
        sender.reply(toApplicationShouldTerminate: true)
      }
      catch {
        Self.traceOfflineLifecycle("flush-failed")
        awaitingQuit = false; sender.reply(toApplicationShouldTerminate: false)
        let alert = NSAlert(); alert.messageText = "저장하지 못해 종료하지 않았어요."; alert.informativeText = error.localizedDescription; alert.runModal()
      }
    }
    return .terminateLater
  }
  func applicationWillTerminate(_ notification: Notification) {
    Self.traceOfflineLifecycle("will-terminate")
  }
  static func captureOwnWindow(path: String) {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.active = self
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
