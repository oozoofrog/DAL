import Foundation

public enum OfflineReportRenderer {
 public static func escape(_ text:String) -> String {
  text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&#39;")
 }
 public static func render(snapshot:ExportSnapshot,captures:[AnnotatedCapture]) throws -> [GeneratedEntry] {
  var entries:[GeneratedEntry]=[],images:[PublicExportManifest.Image]=[],sections:[String]=[]
  let expected=snapshot.requests.reduce(0){$0+snapshot.captureTimes(for:$1.id).count}
  guard captures.count==expected else { throw OfflineError.invalid("선택한 메모의 캡처가 모두 준비되지 않았어요.") }
  for (index,request) in snapshot.requests.enumerated() {
   guard let version=snapshot.versions.first(where:{$0.id==request.anchor.versionID}) else { throw OfflineError.invalid("원본 버전을 확인해 주세요.") }
   var figures:[String]=[]
   for (frameIndex,time) in snapshot.captureTimes(for:request.id).enumerated() {
    let matches=captures.filter{$0.requestID==request.id && $0.requestedMs==time}
    guard matches.count==1,let capture=matches.first,capture.versionID==version.id,capture.sourceFingerprint==version.fingerprint,capture.actualMs.isFinite,capture.actualMs>=0,capture.actualMs<=Double(version.durationMs),capture.pixelWidth>0,capture.pixelHeight>0,capture.png.starts(with:[137,80,78,71,13,10,26,10]) else { throw OfflineError.invalid("캡처와 요청·원본 버전이 일치하지 않아요.") }
    let path=String(format:"images/%03d-%02d.png",index+1,frameIndex+1)
    entries.append(.init(path:path,data:capture.png))
    images.append(.init(path:path,requestID:request.id,versionID:version.id,sourceFingerprint:version.fingerprint,requestedMs:time,actualCapturedMs:capture.actualMs,pixelWidth:capture.pixelWidth,pixelHeight:capture.pixelHeight))
    figures.append("<figure><img src=\"\(path)\" alt=\"메모 \(index+1)의 표시된 원본 캡처\"><figcaption>요청 시각 \(time) ms · 실제 캡처 \(String(format:"%.3f",capture.actualMs)) ms · \(capture.pixelWidth)×\(capture.pixelHeight)</figcaption></figure>")
   }
   let history=snapshot.events.filter{$0.requestID==request.id}.map { event in
    "<li><strong>\(escape(label(event.kind)))</strong><p>\(escape(event.body))</p><small>\(escape(event.id)) · \(escape(event.createdAt))</small></li>"
   }.joined()
   let a=request.anchor,mark=a.annotation
   let coordinates="\(mark.type) · (\(mark.x), \(mark.y))" + (mark.x2.map{" → (\($0), \(mark.y2 ?? 0))"} ?? "")
   sections.append("""
   <article><h2>\(index+1). 메모</h2><p class="body">\(escape(request.body))</p>
   <dl><dt>요청 ID / 수정</dt><dd>\(escape(request.id)) / \(request.revision)</dd><dt>원본 버전</dt><dd>\(escape(version.id))</dd><dt>내용 지문 SHA256</dt><dd>\(escape(version.fingerprint))</dd><dt>선택 구간</dt><dd>\(a.startMs)–\(a.endMs) ms</dd><dt>정규화 표시</dt><dd>\(escape(coordinates))</dd><dt>메모 상태</dt><dd>\(request.resolved ? "닫힘" : "열림")</dd></dl>
   \(figures.joined())<details open><summary>변경 이력</summary><ol>\(history)</ol></details></article>
   """)
  }
  let html="""
  <!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' file:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>\(escape(snapshot.artifactName)) · DAL 메모</title><style>body{font:17px/1.65 system-ui,-apple-system,sans-serif;color:#30422b;background:#f8f7ef;max-width:1000px;margin:36px auto;padding:0 24px}h1{font-size:30px}h2{font-size:24px}article{background:white;border:1px solid #ccd1c7;border-radius:12px;margin:30px 0;padding:24px;break-inside:avoid}.body,li p{white-space:pre-wrap;overflow-wrap:anywhere}dl{display:grid;grid-template-columns:150px 1fr;gap:8px}dt{font-weight:600}dd{margin:0;overflow-wrap:anywhere;font-size:15px}img{max-width:100%;height:auto}figure{margin:20px 0}figcaption,small{font-size:14px;color:#475a40}li{margin:18px 0}summary{font-weight:600}footer{font-size:14px}@media print{body{background:white;margin:0}article{border-color:#999}}</style></head><body><header><p>DAL · \(escape(snapshot.projectName))</p><h1>\(escape(snapshot.artifactName))</h1><p>스냅샷 시각 (UTC) \(escape(snapshot.createdAtText))</p><p>선택한 \(snapshot.requests.count)개 메모의 로컬 스냅샷입니다. 원본 영상은 포함하지 않았습니다.</p><p>표시와 텍스트는 참고 자료입니다. 작성자 인증이나 자동 전송을 뜻하지 않습니다. 결과 기록과 사용자 승인은 별개입니다.</p></header>\(sections.joined())<footer>내보내기 ID \(escape(snapshot.exportID)) · 전체 내용 목록과 체크섬은 manifest.json에 있습니다.</footer></body></html>
  """
  entries.insert(.init(path:"review.html",data:Data(html.utf8)),at:0)
  let manifest=PublicExportManifest(schemaVersion:1,exportID:snapshot.exportID,createdAt:snapshot.createdAtText,projectID:snapshot.projectID,projectName:snapshot.projectName,artifactID:snapshot.artifactID,artifactName:snapshot.artifactName,provenance:"local-record-snapshot; identity-unverified; manual-handoff",requests:snapshot.requests.map{.init(id:$0.id,revision:$0.revision,body:$0.body,anchor:$0.anchor,resolved:$0.resolved,currentResultEventID:$0.currentResultEventID,approvedResultEventID:$0.approvedResultEventID)},history:snapshot.events.map{.init(id:$0.id,requestID:$0.requestID,kind:$0.kind,body:$0.body,resultVersionID:$0.resultVersionID,resultEventID:$0.resultEventID,createdAt:$0.createdAt)},sources:snapshot.versions.map{.init(versionID:$0.id,fingerprint:$0.fingerprint,byteCount:$0.byteCount,durationMs:$0.durationMs)},images:images,entries:entries.map{.init(path:$0.path,byteCount:$0.data.count,sha256:exportSHA256($0.data))})
  let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted,.withoutEscapingSlashes]
  entries.append(.init(path:"manifest.json",data:try encoder.encode(manifest)))
  return entries
 }
 public static func label(_ kind:OfflineEventKind) -> String {
  switch kind { case .request:return "요청";case .textRevision:return "내용 수정";case .proposal:return "제안";case .result:return "결과 기록";case .decisionApprove:return "사용자 승인 기록";case .decisionReject:return "다시 요청 기록";case .resolved:return "닫기";case .reopened:return "다시 열기" }
 }
}
