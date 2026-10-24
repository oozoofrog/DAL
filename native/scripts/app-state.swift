import AppKit
import Foundation
let mode=CommandLine.arguments[1],path=URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL.path
let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"com.eyerama.dotworkspace").filter{$0.bundleURL?.standardizedFileURL.path==path}
if mode=="check" {print(apps.isEmpty ? "stopped":"running");exit(apps.isEmpty ? 0:3)}
// This option is only for this task's known no-draft QA output instance; installers never use it.
if mode=="quit-owned-qa" && path.hasSuffix("/outputs/DotWorkspace.app") {for app in apps{guard app.terminate() else{exit(4)}};exit(0)}
exit(2)
