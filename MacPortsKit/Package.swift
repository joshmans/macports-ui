// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "MacPortsKit",
	platforms: [.macOS(.v13)],
	products: [
		.library(name: "MacPortsKit", targets: ["MacPortsKit"]),
		.executable(name: "MacPortsHelper", targets: ["MacPortsHelper"])
	],
	targets: [
		// The allow-list and protocol, shared by the app and the root helper. Foundation and Security only.
		.target(name: "PortHelperShared"),
		.target(name: "MacPortsKit", dependencies: ["PortHelperShared"]),
		.executableTarget(name: "MacPortsHelper", dependencies: ["PortHelperShared"]),
		.testTarget(name: "MacPortsKitTests", dependencies: ["MacPortsKit"])
	]
)
