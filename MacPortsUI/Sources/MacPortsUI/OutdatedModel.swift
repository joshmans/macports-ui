import Foundation
import MacPortsKit

@MainActor
final class OutdatedModel: ObservableObject {
	
	enum Phase: Equatable {
		case idle
		case checking
		case working(String)
	}
	
	@Published private(set) var report: OutdatedReport?
	@Published private(set) var phase = Phase.idle
	@Published var selection = Set<String>()
	
	let activity: ActivityModel
	let portInstalled = PortsClient.isInstalled
	
	init(activity: ActivityModel) {
		self.activity = activity
	}
	
	var ports: [OutdatedPort] { report?.ports ?? [] }
	var prebuilt: [OutdatedPort] { ports.filter(\.isPrebuilt) }
	var isBusy: Bool { phase != .idle }
	
	/// Selected ports that can be upgraded without compiling.
	var selectedPrebuilt: [OutdatedPort] { ports.filter { selection.contains($0.id) && $0.isPrebuilt } }
	
	func refresh() async {
		guard portInstalled, !isBusy else { return }
		phase = .checking
		let result = await PortsClient.fetchOutdated()
		report = result
		selection.formIntersection(Set(result.ports.map(\.id)))
		phase = .idle
	}
	
	func upgrade(_ list: [OutdatedPort]) async {
		guard !list.isEmpty, !isBusy else { return }
		phase = .working(list.count == 1 ? "Upgrading \(list[0].name)…" : "Upgrading \(list.count) ports…")
		await activity.run(success: "Upgrade finished.") { await PortsClient.upgrade(list.map(\.name), onOutput: $0) }
		phase = .idle
		await refresh()
	}
	
	func refreshIndex() async {
		guard !isBusy else { return }
		phase = .working("Refreshing the port index…")
		await activity.run(success: "Port index refreshed.") { await PortsClient.selfUpdate(onOutput: $0) }
		phase = .idle
		await refresh()
	}
	
}
