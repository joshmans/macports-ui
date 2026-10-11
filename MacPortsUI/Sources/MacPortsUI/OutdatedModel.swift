import Foundation
import Combine
import MacPortsKit

@MainActor
final class OutdatedModel: ObservableObject {
	
	@Published private(set) var report: OutdatedReport?
	@Published private(set) var isChecking = false
	@Published var selection = Set<String>()
	
	let activity: ActivityModel
	let portInstalled = PortsClient.isInstalled
	private var observer: AnyCancellable?
	
	init(activity: ActivityModel) {
		self.activity = activity
		// The queue decides which buttons are enabled.
		observer = activity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
	}
	
	var ports: [OutdatedPort] { report?.ports ?? [] }
	
	/// Ports that can be upgraded now: prebuilt and not already queued.
	var upgradable: [OutdatedPort] { ports.filter { $0.isPrebuilt && !activity.isPending($0.name) } }
	var selectedUpgradable: [OutdatedPort] { upgradable.filter { selection.contains($0.id) } }
	var prebuiltCount: Int { ports.filter(\.isPrebuilt).count }
	
	var isRefreshingIndex: Bool { activity.isPending("@selfupdate") }
	
	func refresh() async {
		guard portInstalled, !isChecking else { return }
		isChecking = true
		let result = await PortsClient.fetchOutdated()
		report = result
		selection.formIntersection(Set(result.ports.map(\.id)))
		isChecking = false
	}
	
	func upgrade(_ list: [OutdatedPort]) {
		let names = list.map(\.name)
		guard !names.isEmpty else { return }
		activity.enqueue(title: names.count == 1 ? "Upgrade \(names[0])" : "Upgrade \(names.count) ports (\(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? ", …" : ""))",
						 keys: Set(names), success: "Upgrade finished.", onFinish: { [weak self] in await self?.refresh() }) {
			await PortsClient.upgrade(names, onOutput: $0)
		}
	}
	
	func refreshIndex() {
		activity.enqueue(title: "Refresh port index", keys: ["@selfupdate"], success: "Port index refreshed.", onFinish: { [weak self] in await self?.refresh() }) {
			await PortsClient.selfUpdate(onOutput: $0)
		}
	}
	
}
