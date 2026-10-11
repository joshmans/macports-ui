import Foundation
import MacPortsKit

@MainActor
final class InstalledModel: ObservableObject {
	
	enum Filter: String, CaseIterable, Identifiable {
		case all = "All"
		case requested = "Requested"
		case dependencies = "Dependencies"
		case leaves = "Leaves"
		var id: String { rawValue }
	}
	
	/// What the user is about to confirm.
	enum Pending: Identifiable {
		case uninstall(InstalledPort)
		case blocked(InstalledPort, dependents: [String])
		case removeInactive
		
		var id: String {
			switch self {
			case .uninstall(let port): return "uninstall-\(port.name)"
			case .blocked(let port, _): return "blocked-\(port.name)"
			case .removeInactive: return "inactive"
			}
		}
	}
	
	@Published private(set) var ports: [InstalledPort]?
	@Published private(set) var isBusy = false
	@Published var filter = Filter.all
	@Published var search = ""
	@Published var selection: String?
	@Published var pending: Pending?
	
	let activity: ActivityModel
	let portInstalled = PortsClient.isInstalled
	
	init(activity: ActivityModel) {
		self.activity = activity
	}
	
	var visible: [InstalledPort] {
		(ports ?? []).filter { port in
			switch filter {
			case .all: return true
			case .requested: return port.isRequested
			case .dependencies: return !port.isRequested
			case .leaves: return port.isLeaf
			}
		}.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
	}
	
	var selectedPort: InstalledPort? { ports?.first { $0.id == selection } }
	
	/// Total number of inactive versions across all ports.
	var inactiveCount: Int { (ports ?? []).reduce(0) { $0 + $1.inactiveVersions.count } }
	
	func refresh() async {
		guard portInstalled, !isBusy else { return }
		isBusy = true
		ports = await PortsClient.fetchInstalled()
		if let selection, ports?.contains(where: { $0.id == selection }) != true { self.selection = nil }
		isBusy = false
	}
	
	/// Asks MacPorts who depends on the port, then either blocks or asks for confirmation.
	func requestUninstall(_ port: InstalledPort) async {
		guard !isBusy else { return }
		isBusy = true
		let dependents = await PortsClient.dependents(of: port.name)
		isBusy = false
		pending = dependents.isEmpty ? .uninstall(port) : .blocked(port, dependents: dependents)
	}
	
	func uninstall(_ port: InstalledPort) async {
		guard !isBusy else { return }
		isBusy = true
		await activity.run(success: "Uninstalled \(port.name).") { await PortsClient.uninstall(port.name, onOutput: $0) }
		isBusy = false
		await refresh()
	}
	
	func removeInactive() async {
		guard !isBusy else { return }
		isBusy = true
		await activity.run(success: "Removed inactive versions.") { await PortsClient.uninstallInactive(onOutput: $0) }
		isBusy = false
		await refresh()
	}
	
}
