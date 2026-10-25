import SwiftUI

struct LocalQAView:View {
 @ObservedObject var proof:QAProofModel
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   Divider()
   Text("로컬 경로 시험 · QA").font(.system(size:21,weight:.semibold))
   Text("시험 파일을 이 대화의 dot이 Mac 도구로 읽고 답하는 방식이에요. 자동으로 전송하거나 dot을 깨우지 않아요.").font(.system(size:15)).foregroundStyle(mutedInk).fixedSize(horizontal:false,vertical:true)
   if let record=proof.record {
    Text("요청 \(record.request.id)\nnonce \(record.request.nonce)").font(.system(size:14,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
    Text("요청 출처: DAL 연결 시험 · 사람의 작업 지시가 아님").font(.system(size:14)).foregroundStyle(mutedInk).fixedSize(horizontal:false,vertical:true)
    if let reply=record.reply {
     Text(reply.body).font(.system(size:17)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.white).clipShape(RoundedRectangle(cornerRadius:8))
     Text("로컬 QA 답변 · 작성자 표기는 인증이 아니에요. 이 대화의 실제 실행 기록과 대조해 확인합니다.").font(.system(size:14)).foregroundStyle(mutedInk).fixedSize(horizontal:false,vertical:true)
    }else{Text("아직 답변 파일이 없어요. dot의 답변 후 새로고침해 주세요.").font(.system(size:16))}
   }
   if let error=proof.error{Text(error).foregroundStyle(.red).font(.system(size:14))}
   HStack{
    if proof.record==nil {Button("QA 요청 만들기"){proof.createRequest()}.buttonStyle(WorkspaceButtonStyle())}
    Button("답변 새로고침"){proof.refresh()}.buttonStyle(WorkspaceButtonStyle())
   }
  }.task {
   if proof.record==nil,ProcessInfo.processInfo.environment["DAL_QA_CREATE_REQUEST"]=="1"{proof.createRequest()}
  }
 }
}
