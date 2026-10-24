import Foundation
import Testing

@testable import WorkspaceCore

@Test func cookieScopeAndOrigin() throws {
  let base = URL(string: "https://workspace.example.invalid")!
  let policy = SiteBoundary(origin: base)
  #expect(
    policy.permits(
      URL(string: "https://workspace.example.invalid/api/projects")!))
  #expect(!policy.permits(URL(string: "https://chatgpt.com/api/projects")!))
  let own = HTTPCookie(properties: [
    .domain: base.host!, .path: "/", .name: "session", .value: "memory-only", .secure: "TRUE",
  ])!
  let foreign = HTTPCookie(properties: [
    .domain: "chatgpt.com", .path: "/", .name: "foreign", .value: "never-forward",
  ])!
  #expect(
    policy.cookies([own, foreign], for: base.appendingPathComponent("api/projects")).map(\.name)
      == ["session"])
}
@Test func immutableNormalizedAnchorsAndActualRange() throws {
  let point = Annotation(type: "point", x: 0.5, y: 0.3)
  #expect(point.isValid)
  #expect(!Annotation(type: "rectangle", x: 0.8, y: 0.1, x2: 0.2, y2: 0.5).isValid)
  #expect(ReviewRange(startMs: 1000, endMs: 3000).fits(actualDuration: 3))
  #expect(!ReviewRange(startMs: 1000, endMs: 3000).fits(actualDuration: 2.99))
  let box = VideoContentBox(
    containerWidth: 100, containerHeight: 100, videoWidth: 200, videoHeight: 100)
  #expect(box.normalized(x: 50, y: 10) == nil)
  #expect(box.normalized(x: 50, y: 50)?.x == 0.5)
}
@Test func threadDraftOwnershipAndInflightEdits() {
  var drafts = DraftStore()
  drafts.set("A", body: "sent")
  drafts.set("B", body: "writing")
  drafts.clearSubmitted("A", body: "sent")
  #expect(drafts.body("B") == "writing")
  drafts.set("A", body: "new edit")
  drafts.clearSubmitted("A", body: "old")
  #expect(drafts.body("A") == "new edit")
}
@Test func operationKeysReplayUntilConfirmed() {
  var keys = OperationKeys()
  let first = keys.key(for: "A")
  #expect(keys.key(for: "A") == first)
  #expect(keys.key(for: "B") != first)
  keys.confirm("A")
  #expect(keys.key(for: "A") != first)
}
@Test func draftModeBelongsToThreadAndInflightKindIsPreserved() {
  var drafts = DraftStore()
  drafts.set("A", body: "again")
  drafts.setKind("A", kind: "rerequest")
  drafts.set("B", body: "reply")
  #expect(drafts.kind("B") == "reply")
  drafts.setKind("A", kind: "reply")
  drafts.clearSubmitted("A", body: "again", kind: "rerequest")
  #expect(drafts.body("A") == "again")
}
@Test func mutationResponseMustIdentifyPersistedRecord() throws {
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(MutationResult.self, from: Data("{}".utf8))
  }
  let valid = try JSONDecoder().decode(
    MutationResult.self, from: Data("{\"threadId\":\"thread\",\"revision\":1}".utf8))
  #expect(valid.threadId == "thread")
}
