import Foundation
import MacPortsKit

@MainActor
final class BrowseModel: ObservableObject {
	
	@Published private(set) var catalog: [CatalogPort]?
	@Published private(set) var categories = [(name: String, count: Int)]()
	@Published private(set) var results = [CatalogPort]()
	@Published private(set) var installedVersions = [String: String]()
	@Published private(set) var detail: PortDetail?
	@Published private(set) var detailIsLoading = false
	@Published private(set) var isInstalling = false
	@Published var installFlow: InstallFlowModel?
	
	@Published var search = "" { didSet { updateResults() } }
	@Published var category: String? { didSet { updateResults() } }
	@Published var selection: String? { didSet { if selection != oldValue { loadDetail() } } }
	
	let activity: ActivityModel
	let portInstalled = PortsClient.isInstalled
	private var detailTask: Task<Void, Never>?
	
	/// The most results shown at once; a search narrows them.
	static let limit = 500
	
	init(activity: ActivityModel) {
		self.activity = activity
	}
	
	var hasQuery: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty || category != nil }
	
	func loadIfNeeded() async {
		guard portInstalled, catalog == nil else { return }
		await reload()
	}
	
	/// Reads the catalog again, for example after the port index was refreshed.
	func reload() async {
		catalog = nil
		let loaded = await PortsClient.fetchCatalog()
		catalog = loaded
		categories = Catalog.categories(in: loaded)
		updateResults()
		await refreshInstalled()
	}
	
	func refreshInstalled() async {
		let installed = await PortsClient.fetchInstalled()
		installedVersions = Dictionary(installed.map { ($0.name, $0.version) }, uniquingKeysWith: { first, _ in first })
	}
	
	private func updateResults() {
		guard let catalog, hasQuery else { results = []; return }
		results = Catalog.search(search, in: catalog, category: category, limit: Self.limit)
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
	
	func install(_ flow: InstallFlowModel, buildFromSource: Bool) async {
		guard !isInstalling else { return }
		isInstalling = true
		let name = flow.detail.name
		let arguments = flow.selection.arguments
		flow.cancel()
		installFlow = nil
		// Let the install sheet go away before the log sheet comes up.
		try? await Task.sleep(nanoseconds: 400_000_000)
		await activity.run(success: "Installed \(name).") { await PortsClient.install(name, variants: arguments, buildFromSource: buildFromSource, onOutput: $0) }
		await refreshInstalled()
		isInstalling = false
	}
	
}
