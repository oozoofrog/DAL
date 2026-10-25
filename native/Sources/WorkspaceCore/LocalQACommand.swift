import Foundation

public enum LocalQACommand {
 public static func readInput(_ handle:FileHandle) throws ->Data {
  var result=Data()
  while let chunk=try handle.read(upToCount:min(1024,4097-result.count)),!chunk.isEmpty {
   result.append(chunk)
   guard result.count<=4096 else {throw LocalQAError.invalid("답변은 UTF-8 4096바이트 이하여야 합니다.")}
  }
  return result
 }
 public static func run(arguments:[String],input:() throws ->Data) throws ->String {
  guard let mode=arguments.first,["read","reply"].contains(mode) else {throw LocalQAError.invalid("read 또는 reply 명령만 사용할 수 있습니다.")}
  var values:[String:String]=[:];var index=1;var bodyStdin=false
  while index<arguments.count {
   let flag=arguments[index]
   if flag=="--body-stdin" {guard !bodyStdin else{throw LocalQAError.invalid("중복 옵션입니다.")};bodyStdin=true;index+=1;continue}
   guard index+1<arguments.count,values[flag]==nil,flag.hasPrefix("--") else {throw LocalQAError.invalid("명령 옵션을 확인해 주세요.")}
   values[flag]=arguments[index+1];index+=2
  }
  let required:Set<String>=mode=="read" ? ["--directory","--request"]:["--directory","--request","--nonce","--expected-revision","--operation-key"]
  guard Set(values.keys)==required,bodyStdin==(mode=="reply"),let root=values["--directory"],root.hasPrefix("/"),let id=values["--request"] else {throw LocalQAError.invalid("명령 옵션을 확인해 주세요.")}
  let store=try LocalQAStore(directory:URL(fileURLWithPath:root));let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
  let output:Data
  if mode=="read" {output=try encoder.encode(store.read(id))}
  else {
   let raw=try input();guard raw.count<=4096,let body=String(data:raw,encoding:.utf8),values["--expected-revision"]=="0" else {throw LocalQAError.invalid("UTF-8 답변과 revision0을 확인해 주세요.")}
   output=try encoder.encode(store.reply(id:id,nonce:values["--nonce"]!,expectedRevision:0,operationKey:values["--operation-key"]!,body:body))
  }
  return String(decoding:output,as:UTF8.self)
 }
}
