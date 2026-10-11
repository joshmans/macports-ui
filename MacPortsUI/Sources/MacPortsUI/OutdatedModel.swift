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
	@Published var log: String?
	@Published private(set) var logIsLive = false
	@Published var logFailed = false
	
	let portInstalled = PortsClient.isInstalled
	
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
		startLog()
		let result = await PortsClient.upgrade(list.map(\.name), onOutput: appender())
		show(result, success: "Upgrade finished.")
		phase = .idle
		await refresh()
	}
	
	func refreshIndex() async {
		guard !isBusy else { return }
		phase = .working("Refreshing the port index…")
		startLog()
		let result = await PortsClient.selfUpdate(onOutput: appender())
		show(result, success: "Port index refreshed.")
		phase = .idle
		await refresh()
	}
	
	/// Opens the log sheet so output can be shown while the command runs.
	private func startLog() {
		log = ""
		logFailed = false
		logIsLive = true
	}
	
	private func appender() -> @Sendable (String) -> Void {
		{ [weak self] text in
			Task { @MainActor in self?.log?.append(text) }
		}
	}
	
	private func show(_ result: ActionResult, success: String) {
		logIsLive = false
		logFailed = !result.succeeded
		let streamed = (log ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		if result.succeeded {
			log = streamed.isEmpty ? success : streamed
		} else {
			let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
			log = streamed.isEmpty ? (text.isEmpty ? "The command failed (exit \(result.status))." : text) : streamed
		}
	}
	
}
