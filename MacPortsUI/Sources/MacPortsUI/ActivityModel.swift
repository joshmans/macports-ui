import Foundation
import MacPortsKit

/// The log of the privileged command that is running or just finished, shared by every screen.
@MainActor
final class ActivityModel: ObservableObject {
	
	@Published var log: String?
	@Published private(set) var isLive = false
	@Published private(set) var failed = false
	
	/// Runs a command with a live log sheet. The closure receives the callback that feeds the log.
	@discardableResult
	func run(success: String, _ command: (@escaping @Sendable (String) -> Void) async -> ActionResult) async -> ActionResult {
		log = ""
		failed = false
		isLive = true
		let result = await command { [weak self] text in
			Task { @MainActor in self?.log?.append(text) }
		}
		isLive = false
		failed = !result.succeeded
		let streamed = (log ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		let fallback = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
		if streamed.isEmpty {
			log = result.succeeded ? success : (fallback.isEmpty ? "The command failed (exit \(result.status))." : fallback)
		} else {
			log = streamed
		}
		return result
	}
	
}
