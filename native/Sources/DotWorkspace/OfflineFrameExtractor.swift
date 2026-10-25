import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import WorkspaceCore

enum OfflineFrameExtractor {
 static func capture(version:OfflineVersion,request:OfflineRequest,requestedMs:Int) async throws -> AnnotatedCapture {
  let anchor=request.anchor
  guard anchor.versionID==version.id,anchor.startMs>=0,anchor.endMs<=version.durationMs,requestedMs>=anchor.startMs,requestedMs<anchor.endMs,anchor.annotation.isValid else { throw OfflineError.invalid("캡처할 원본 구간과 표시를 확인해 주세요.") }
  try Task.checkCancellation()
  let url=URL(fileURLWithPath:version.sourceLocator),expected=MediaFingerprint(sha256:version.fingerprint,byteCount:version.byteCount,durationMs:version.durationMs)
  guard await OfflineMediaIdentity.verify(url,expected:expected) == .matching else { throw OfflineError.invalid("원본이 없거나 내용이 달라 캡처하지 않았어요. 같은 원본을 다시 선택해 주세요.") }
  let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url));generator.appliesPreferredTrackTransform=true
  generator.maximumSize=CGSize(width:1920,height:1080)
  generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
  let result=try await generator.image(at:CMTime(value:Int64(requestedMs),timescale:1000))
  try Task.checkCancellation()
  let actual=result.actualTime.seconds*1000,image=result.image
  guard actual.isFinite,actual>=0,actual<=Double(version.durationMs),image.width>0,image.height>0,
   let space=CGColorSpace(name:CGColorSpace.sRGB),let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OfflineError.invalid("실제 캡처를 만들지 못했어요.") }
  let width=Double(image.width),height=Double(image.height),mark=anchor.annotation
  context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
  context.setStrokeColor(CGColor(red:1,green:0.82,blue:0,alpha:1));context.setLineWidth(max(3,min(width,height)*0.006))
  let p=CGPoint(x:mark.x*width,y:(1-mark.y)*height)
  if mark.type=="point" { let radius=max(7,min(width,height)*0.012);context.strokeEllipse(in:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)) }
  else if let x2=mark.x2,let y2=mark.y2 {
   let q=CGPoint(x:x2*width,y:(1-y2)*height)
   if mark.type=="rectangle" { context.stroke(CGRect(x:min(p.x,q.x),y:min(p.y,q.y),width:abs(q.x-p.x),height:abs(q.y-p.y))) }
   else {
    context.move(to:p);context.addLine(to:q)
    let angle=atan2(q.y-p.y,q.x-p.x),head=max(14,min(width,height)*0.03)
    context.move(to:CGPoint(x:q.x-head*cos(angle-0.45),y:q.y-head*sin(angle-0.45)));context.addLine(to:q);context.addLine(to:CGPoint(x:q.x-head*cos(angle+0.45),y:q.y-head*sin(angle+0.45)));context.strokePath()
   }
  }
  let png=NSMutableData()
  guard let marked=context.makeImage(),let destination=CGImageDestinationCreateWithData(png,UTType.png.identifier as CFString,1,nil) else { throw OfflineError.invalid("캡처 이미지를 저장하지 못했어요.") }
  CGImageDestinationAddImage(destination,marked,nil)
  guard CGImageDestinationFinalize(destination) else { throw OfflineError.invalid("캡처 이미지 검증에 실패했어요.") }
  try Task.checkCancellation()
  guard await OfflineMediaIdentity.verify(url,expected:expected) == .matching else { throw OfflineError.invalid("캡처 중 원본이 바뀌었어요. 새로 미리 보기를 만들어 주세요.") }
  return .init(requestID:request.id,versionID:version.id,sourceFingerprint:version.fingerprint,requestedMs:requestedMs,actualMs:actual,pixelWidth:image.width,pixelHeight:image.height,png:png as Data)
 }
}
