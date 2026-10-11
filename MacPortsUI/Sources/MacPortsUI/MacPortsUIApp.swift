import SwiftUI

@main
struct MacPortsUIApp: App {
	var body: some Scene {
		WindowGroup("MacPorts UI") {
			RootView()
				.frame(minWidth: 900, minHeight: 480)
		}
		.defaultSize(width: 1100, height: 700)
	}
}
