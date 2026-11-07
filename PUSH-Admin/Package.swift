// swift-tools-version: 5.9
// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import PackageDescription
let package = Package(name:"PUSHAdmin",platforms:[.macOS(.v14)],products:[.executable(name:"PUSHAdmin",targets:["PUSHAdmin"])],targets:[.executableTarget(name:"PUSHAdmin",path:"Sources")])
