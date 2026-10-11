import SwiftUI
import MacPortsKit

/// Settings pane for the optional privileged helper.
struct HelperSettingsView: View {
	
	@State private var state = PortsClient.helperState
	@State private var error: String?
	
	var body: some View {
		Form {
			Section {
				HStack(spacing: 10) {
					Image(systemName: state == .enabled ? "checkmark.shield.fill" : "shield.lefthalf.filled")
						.font(.title).foregroundStyle(state == .enabled ? .green : .secondary)
					Text("Privileged Helper").font(.title3.bold())
				}
				Text("The helper is a small background service that runs only install, upgrade, uninstall and selfupdate for this app, so you are not asked for your administrator password each time. Because MacPorts runs port build scripts as root, only install ports you trust.")
					.font(.callout).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Section {
				LabeledContent("Status", value: description)
				switch state {
				case .unavailable:
					EmptyView()
				case .notRegistered:
					Button("Enable Helper") { enable() }
				case .requiresApproval:
					Button("Open Login Items Settings…") { PortsClient.openLoginItemsSettings() }
					Button("Check Again") { state = PortsClient.helperState }
				case .enabled:
					Button("Disable Helper") { PortsClient.disableHelper(); state = PortsClient.helperState }
				}
				if let error { Text(error).foregroundStyle(.red).font(.callout) }
			}
		}
		.formStyle(.grouped)
		.frame(width: 460)
		.fixedSize(horizontal: false, vertical: true)
		.onAppear { state = PortsClient.helperState }
	}
	
	private var description: String {
		switch state {
		case .unavailable(let reason): return "Unavailable. \(reason)"
		case .notRegistered: return "Off"
		case .requiresApproval: return "Waiting for your approval in System Settings"
		case .enabled: return "On"
		}
	}
	
	private func enable() {
		do { try PortsClient.enableHelper(); error = nil } catch { self.error = error.localizedDescription }
		state = PortsClient.helperState
	}
	
}
