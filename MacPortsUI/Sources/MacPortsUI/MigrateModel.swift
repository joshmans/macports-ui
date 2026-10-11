import Foundation
import Combine
import MacPortsKit

@MainActor
final class MigrateModel: ObservableObject {
	
	enum Sheet: Identifiable {
		case working
		case review(SwitchPreview)
		
		var id: String {
			switch self {
			case .working: return "working"
			case .review: return "review"
			}
		}
	}
	
	@Published private(set) var formulae: [HomebrewFormula]?
	@Published private(set) var isLoading = false
	@Published var onlySwitchable = true
	@Published var selection = Set<String>()
	@Published var sheet: Sheet?
	
	let activity: ActivityModel
	let brewInstalled = HomebrewClient.isInstalled
	let portInstalled = PortsClient.isInstalled
	private var observer: AnyCancellable?
	private var previewTask: Task<Void, Never>?
	
	init(activity: ActivityModel) {
		self.activity = activity
		observer = activity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
	}
	
	var visible: [HomebrewFormula] {
		(formulae ?? []).filter { !onlySwitchable || $0.alternative != nil }
	}
	
	var switchableCount: Int { (formulae ?? []).filter { $0.alternative != nil }.count }
	
	/// Selected formulae that have a MacPorts equivalent and are not already being switched.
	var selectedSwitchable: [HomebrewFormula] {
		(formulae ?? []).filter { selection.contains($0.id) && $0.alternative != nil && !activity.isPending($0.name) }
	}
	
	func isPending(_ formula: HomebrewFormula) -> Bool { activity.isPending(formula.name) }
	
	func loadIfNeeded() async {
		guard formulae == nil else { return }
		await refresh()
	}
	
	func refresh() async {
		guard brewInstalled, !isLoading else { return }
		isLoading = true
		apply(formulae: await HomebrewClient.fetchOutdated())
		isLoading = false
	}
	
	func apply(formulae loaded: [HomebrewFormula]) {
		formulae = loaded
		selection.formIntersection(Set(loaded.map(\.id)))
	}
	
	/// Works out what switching the selection would do and shows it for review.
	func beginSwitch() {
		let selected = selectedSwitchable
		guard !selected.isEmpty else { return }
		sheet = .working
		previewTask?.cancel()
		previewTask = Task {
			let preview = await HomebrewClient.previewSwitch(of: selected)
			guard !Task.isCancelled, case .working? = sheet else { return }
			sheet = .review(preview)
		}
	}
	
	func cancelSwitch() {
		previewTask?.cancel()
		sheet = nil
	}
	
	func confirmSwitch(_ preview: SwitchPreview) {
		sheet = nil
		let formulaNames = preview.groups.flatMap { $0.map(\.formula) }
		let ports = preview.groups.flatMap { $0.map(\.port) }
		activity.enqueue(title: "Switch \(preview.formulaCount) package\(preview.formulaCount == 1 ? "" : "s") to MacPorts",
						 keys: Set(formulaNames + ports + ["@migrate"]), success: "Switch finished.", onFinish: { [weak self] in await self?.refresh() }) {
			await HomebrewClient.executeSwitch(preview, onOutput: $0)
		}
	}
	
}
