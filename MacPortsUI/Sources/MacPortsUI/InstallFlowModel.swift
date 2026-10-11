import Foundation
import MacPortsKit

/// One install in preparation: the chosen variants and what they would need.
@MainActor
final class InstallFlowModel: ObservableObject, Identifiable {
	
	nonisolated let detail: PortDetail
	nonisolated var id: String { detail.name }
	
	@Published private(set) var selection: VariantSelection
	@Published private(set) var plan: InstallPlan?
	@Published private(set) var isPlanning = false
	
	private var planTask: Task<Void, Never>?
	
	init(detail: PortDetail) {
		self.detail = detail
		self.selection = VariantSelection(variants: detail.variants)
	}
	
	func setVariant(_ name: String, enabled: Bool) {
		selection.set(name, enabled: enabled)
		refreshPlan()
	}
	
	func resetVariants() {
		selection = VariantSelection(variants: detail.variants)
		refreshPlan()
	}
	
	/// Recomputes the plan. A quick succession of changes only keeps the last.
	func refreshPlan() {
		planTask?.cancel()
		plan = nil
		isPlanning = true
		let detail = detail
		let selection = selection
		planTask = Task {
			try? await Task.sleep(nanoseconds: 250_000_000)
			guard !Task.isCancelled else { return }
			let result = await PortsClient.planInstall(of: detail.name, version: detail.version, revision: detail.revision, selection: selection)
			guard !Task.isCancelled else { return }
			plan = result
			isPlanning = false
		}
	}
	
	func cancel() { planTask?.cancel() }
	
}
