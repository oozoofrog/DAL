import Foundation
import Testing
@testable import WorkspaceCore
@Test func offlineZIPUnicodeRoundtripsWithIndependentReader() throws {
 let entries=[GeneratedEntry(path:"문서/메모.html",data:Data("한글 & plain text".utf8)),GeneratedEntry(path:"manifest.json",data:Data("{}".utf8))]
 let zip=try OfflineZIPWriter.archive(entries:entries)
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
 let url=root.appendingPathComponent("한글 묶음.zip");try zip.write(to:url)
 let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/env");process.arguments=["python3","-c","import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; assert z.namelist()==['\\ubb38\\uc11c/\\uba54\\ubaa8.html','manifest.json']; assert z.read('\\ubb38\\uc11c/\\uba54\\ubaa8.html').decode()=='\\ud55c\\uae00 & plain text'; assert all(i.flag_bits&0x800 for i in z.infolist())",url.path];try process.run();process.waitUntilExit();#expect(process.terminationStatus==0)
 let saved=try Data(contentsOf:url);#expect(zip.count==saved.count)
}
@Test func offlineZIPRejectsTraversalAbsoluteDuplicateAndOverflow() throws {
 for path in ["../bad","/absolute","a\\b","a//b","a/./b","a/../b","a/\0b"] { #expect(throws:OfflineError.self){try OfflineZIPWriter.archive(entries:[.init(path:path,data:Data())])} }
 #expect(throws:OfflineError.self){try OfflineZIPWriter.archive(entries:[.init(path:"é.txt",data:Data()),.init(path:"e\u{301}.txt",data:Data())])}
 #expect(throws:OfflineError.self){try OfflineZIPWriter.validateZIP32(entryCount:65535,totalBytes:1)}
 #expect(throws:OfflineError.self){try OfflineZIPWriter.validateZIP32(entryCount:1,totalBytes:UInt64(UInt32.max))}
}
