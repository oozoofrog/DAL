import Foundation
import SwiftUI
import WorkspaceCore

@MainActor final class QAProofModel:ObservableObject {
 @Published private(set) var record:LocalQARecord?
 @Published private(set) var error:String?
 private let directory:URL?
 var available:Bool{directory != nil}
 init(directory:URL?){self.directory=directory;refresh()}
 func refresh(){guard let directory else{return};do{record=try LocalQAStore(directory:directory).latest();error=nil}catch{record=nil;self.error=error.localizedDescription}}
 func createRequest(){guard let directory else{return};do{let store=try LocalQAStore(directory:directory);let request=try store.createRequest();record=try store.read(request.id);error=nil}catch{self.error=error.localizedDescription}}
}
