import Foundation
import Testing
import WorkspaceCore
@testable import DotWorkspace

@MainActor @Test func connectionStatusDoesNotAuthenticateOrCreateRecords() async {
  let store = WorkspaceStore()
  #expect(!store.connected)
  store.showConnectionStatus()
  #expect(store.showingConnectionStatus)
  #expect(!store.connected)
  #expect(!store.client.connected)
  #expect(store.projects.isEmpty)
  #expect(store.snapshot.threads.isEmpty)
  store.dismissConnectionStatus()
  #expect(!store.showingConnectionStatus)
  await store.refresh()
  #expect(store.projects.isEmpty)
  #expect(!store.connected)
}
@MainActor @Test func ownerHTTPRemainsBlockedWithoutNativeChannel() async throws {
  let client = SiteSession(origin: URL(string: "https://example.invalid")!)
  do {
    let _: ProjectList = try await client.request(path: "/api/projects")
    Issue.record("Disconnected HTTP must never reach a server")
  } catch ConnectionError.notConnected { }
  #expect(!client.connected)
  #expect(client.mediaCookies(for: URL(string: "https://example.invalid/api/media/test")!).isEmpty)
}
