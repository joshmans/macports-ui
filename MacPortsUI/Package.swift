// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "MacPortsUI",
	platforms: [.macOS(.v13)],
	dependencies: [.package(path: "../MacPortsKit")],
	targets: [
		.executableTarget(name: "MacPortsUI", dependencies: ["MacPortsKit"]),
		.testTarget(name: "MacPortsUITests", dependencies: ["MacPortsUI"])
	]
)
