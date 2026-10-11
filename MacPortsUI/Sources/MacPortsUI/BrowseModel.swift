import Foundation
import Combine
import MacPortsKit

@MainActor
final class BrowseModel: ObservableObject {
	
	@Published private(set) var catalog: [CatalogPort]?
	@Published private(set) var categories = [(name: String, count: Int)]()
	@Published private(set) var results = [CatalogPort]()
	@Published private(set) var installedVersions = [String: String]()
	@Published private(set) var detail: PortDetail?
	@Published private(set) var detailIsLoading = false
	@Published var installFlow: InstallFlowModel?
	
	@Published var search = "" { didSet { updateResults() } }
	@Published var category: String? { didSet { updateResults() } }
	@Published var selection: String? { didSet { if selection != oldValue { loadDetail() } } }
	
	let activity: ActivityModel
	let portInstalled = PortsClient.isInstalled
	private var detailTask: Task<Void, Never>?
	private var observer: AnyCancellable?
	
	/// The most results shown at once; a search narrows them.
	static let limit = 500
	
	init(activity: ActivityModel) {
		self.activity = activity
		observer = activity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
	}
	
	var hasQuery: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty || category != nil }
	
	func loadIfNeeded() async {
		guard portInstalled, catalog == nil else { return }
		await reload()
	}
	
	/// Reads the catalog again, for example after the port index was refreshed.
	func reload() async {
		catalog = nil
		apply(catalog: await PortsClient.fetchCatalog())
		await refreshInstalled()
	}
	
	func apply(catalog loaded: [CatalogPort]) {
		catalog = loaded
		categories = Catalog.categories(in: loaded)
		updateResults()
	}
	
	func refreshInstalled() async {
		let installed = await PortsClient.fetchInstalled()
		installedVersions = Dictionary(installed.map { ($0.name, $0.version) }, uniquingKeysWith: { first, _ in first })
	}
	
	private func updateResults() {
		if let catalog, hasQuery {
			results = Catalog.search(search, in: catalog, category: category, limit: Self.limit)
		} else {
			results = []
		}
		// A port that is no longer listed must not stay selected, or its details and Install button would still be on screen.
		if let selection, !results.contains(where: { $0.name == selection }) { self.selection = nil }
	}
	
	private func loadDetail() {
		detailTask?.cancel()
		detail = nil
		guard let name = selection else { detailIsLoading = false; return }
		detailIsLoading = true
		detailTask = Task {
			let loaded = await PortsClient.detail(of: name)
			guard !Task.isCancelled else { return }
			detail = loaded
			detailIsLoading = false
		}
	}
	
	/// Opens the install sheet for the selected port.
	func beginInstall() {
		guard let detail, installedVersions[detail.name] == nil else { return }
		installFlow = InstallFlowModel(detail: detail)
	}
	
	func cancelInstall() {
		installFlow?.cancel()
		installFlow = nil
	}
	
	/// Whether the port has a queued or running action.
	func isPending(_ name: String) -> Bool { activity.isPending(name) }
	
	func install(_ flow: InstallFlowModel, buildFromSource: Bool) {
		let name = flow.detail.name
		let arguments = flow.selection.arguments
		flow.cancel()
		installFlow = nil
		let title = buildFromSource ? "Build \(name) from source" : "Install \(name)"
		activity.enqueue(title: title, keys: [name], success: "Installed \(name).", onFinish: { [weak self] in await self?.refreshInstalled() }) {
			await PortsClient.install(name, variants: arguments, buildFromSource: buildFromSource, onOutput: $0)
		}
	}
	
}
