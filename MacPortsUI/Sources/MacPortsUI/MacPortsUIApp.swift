import SwiftUI

@main
struct MacPortsUIApp: App {
	var body: some Scene {
		WindowGroup("MacPorts UI") {
			OutdatedView()
				.frame(minWidth: 620, minHeight: 400)
		}
	}
}
