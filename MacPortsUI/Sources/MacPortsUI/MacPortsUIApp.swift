import SwiftUI

@main
struct MacPortsUIApp: App {
	var body: some Scene {
		WindowGroup("MacPorts UI") {
			RootView()
				.frame(minWidth: 820, minHeight: 400)
		}
	}
}
