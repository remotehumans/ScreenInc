// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ScreenInk", platforms: [.macOS(.v14)], products: [.executable(name: "ScreenInk", targets: ["ScreenInk"])], targets: [.executableTarget(name: "ScreenInk"), .testTarget(name: "ScreenInkTests", dependencies: ["ScreenInk"])])
