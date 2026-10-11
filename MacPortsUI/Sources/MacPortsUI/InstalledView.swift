import SwiftUI
import MacPortsKit

struct InstalledView: View {
	
	@ObservedObject var model: InstalledModel
	
	var body: some View {
		VStack(spacing: 0) {
			if !model.portInstalled {
				ContentUnavailableMessage(title: "MacPorts is not installed", detail: "Expected at /opt/local/bin/port.", symbol: "shippingbox")
			} else {
				Picker("Show", selection: $model.filter) {
					ForEach(InstalledModel.Filter.allCases) { Text($0.rawValue).tag($0) }
				}
				.pickerStyle(.segmented).labelsHidden()
				.padding(10)
				Divider()
				content
				Divider()
				footer
			}
		}
		.searchable(text: $model.search, prompt: "Filter installed ports")
		.toolbar {
			ToolbarItem {
				Button { Task { await model.refresh() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
					.disabled(model.isBusy || !model.portInstalled)
			}
		}
		.task { if model.ports == nil { await model.refresh() } }
		.confirmationDialog(title, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }), presenting: model.pending) { pending in
			switch pending {
			case .uninstall(let port):
				Button("Uninstall \(port.name)", role: .destructive) { Task { await model.uninstall(port) } }
			case .removeInactive:
				Button("Remove Inactive Versions", role: .destructive) { Task { await model.removeInactive() } }
			case .blocked:
				Button("OK", role: .cancel) {}
			}
		} message: { pending in
			Text(message(for: pending))
		}
	}
	
	// MARK: Pieces
	
	@ViewBuilder private var content: some View {
		if model.ports == nil {
			VStack(spacing: 12) {
				ProgressView()
				Text("Reading installed ports…").foregroundStyle(.secondary)
			}.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if model.visible.isEmpty {
			ContentUnavailableMessage(title: "No ports match", detail: nil, symbol: "magnifyingglass")
		} else {
			Table(model.visible, selection: $model.selection) {
				TableColumn("Port") { port in
					HStack(spacing: 6) {
						Text(port.name).fontWeight(.medium)
						if !port.isActive { Text("inactive").font(.caption2).padding(.horizontal, 5).background(.orange.opacity(0.2), in: Capsule()) }
					}
				}
				TableColumn("Version") { Text($0.version).monospacedDigit() }
				TableColumn("Variants") { Text($0.variants).foregroundStyle(.secondary).lineLimit(1) }
				TableColumn("Kind") { port in
					HStack(spacing: 4) {
						Label(port.isRequested ? "Requested" : "Dependency", systemImage: port.isRequested ? "person.fill" : "link")
							.foregroundStyle(port.isRequested ? Color.primary : Color.secondary)
						if port.isLeaf && !port.isRequested { Text("· unused").foregroundStyle(.orange) }
					}
				}
				.width(min: 130, ideal: 160)
				TableColumn("Old versions") { port in
					if !port.inactiveVersions.isEmpty {
						Text("\(port.inactiveVersions.count)").help(port.inactiveVersions.joined(separator: ", "))
					}
				}
				.width(80)
			}
		}
	}
	
	private var footer: some View {
		HStack {
			if model.isBusy { ProgressView().controlSize(.small) }
			Text(summary).foregroundStyle(.secondary)
			Spacer()
			Button("Remove Inactive Versions…") { model.pending = .removeInactive }
				.disabled(model.isBusy || model.inactiveCount == 0)
			Button("Uninstall…") {
				if let port = model.selectedPort { Task { await model.requestUninstall(port) } }
			}
			.disabled(model.isBusy || model.selectedPort == nil)
		}
		.padding(10)
	}
	
	private var summary: String {
		guard let ports = model.ports else { return "" }
		let requested = ports.filter(\.isRequested).count
		var text = "\(ports.count) installed · \(requested) requested · \(ports.count - requested) dependencies"
		if model.inactiveCount > 0 { text += " · \(model.inactiveCount) old versions" }
		return text
	}
	
	private var title: String {
		switch model.pending {
		case .uninstall(let port): return "Uninstall \(port.name)?"
		case .blocked(let port, _): return "\(port.name) is still needed"
		case .removeInactive: return "Remove inactive versions?"
		case nil: return ""
		}
	}
	
	private func message(for pending: InstalledModel.Pending) -> String {
		switch pending {
		case .uninstall(let port):
			return "\(port.name) \(port.version) will be removed. Ports that were installed only for it are kept; look for them under Leaves."
		case .blocked(_, let dependents):
			let list = dependents.prefix(8).joined(separator: ", ") + (dependents.count > 8 ? " and \(dependents.count - 8) more" : "")
			return "These installed ports depend on it: \(list). Uninstall them first."
		case .removeInactive:
			return "Removes \(model.inactiveCount) older version\(model.inactiveCount == 1 ? "" : "s") that are installed but not active. The active versions are not touched."
		}
	}
	
}
