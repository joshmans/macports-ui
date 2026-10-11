// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "MacPortsKit",
	platforms: [.macOS(.v13)],
	products: [.library(name: "MacPortsKit", targets: ["MacPortsKit"])],
	targets: [
		.target(name: "MacPortsKit"),
		.testTarget(name: "MacPortsKitTests", dependencies: ["MacPortsKit"])
	]
)
