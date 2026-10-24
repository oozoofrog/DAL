// swift-tools-version: 6.0
import PackageDescription
let package=Package(name:"DotWorkspace",platforms:[.macOS(.v14)],products:[.executable(name:"DotWorkspace",targets:["DotWorkspace"])],targets:[.target(name:"WorkspaceCore"),.executableTarget(name:"DotWorkspace",dependencies:["WorkspaceCore"]),.testTarget(name:"WorkspaceCoreTests",dependencies:["WorkspaceCore"]),.testTarget(name:"DotWorkspaceTests",dependencies:["DotWorkspace","WorkspaceCore"])],swiftLanguageModes:[.v5])
