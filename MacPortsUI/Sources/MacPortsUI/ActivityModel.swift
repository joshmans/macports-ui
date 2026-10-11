import Foundation
import Combine
import MacPortsKit

/// One privileged command in the queue, with its own log.
@MainActor
final class ActivityJob: ObservableObject, Identifiable {
	
	enum Status {
		case queued, running, succeeded, failed, cancelled
		
		var isActive: Bool { self == .queued || self == .running }
	}
	
	let id = UUID()
	let title: String
	
	/// What the job touches: port names, or `@selfupdate` and similar for global actions. Used to stop the same thing being queued twice.
	let keys: Set<String>
	let createdAt = Date()
	
	@Published fileprivate(set) var status = Status.queued
	@Published fileprivate(set) var log = ""
	@Published fileprivate(set) var startedAt: Date?
	@Published fileprivate(set) var finishedAt: Date?
	
	fileprivate let success: String
	fileprivate let command: (@escaping @Sendable (String) -> Void) async -> ActionResult
	fileprivate let onFinish: (() async -> Void)?
	
	fileprivate init(title: String, keys: Set<String>, success: String, command: @escaping (@escaping @Sendable (String) -> Void) async -> ActionResult, onFinish: (() async -> Void)?) {
		self.title = title
		self.keys = keys
		self.success = success
		self.command = command
		self.onFinish = onFinish
	}
	
	var duration: TimeInterval? {
		guard let startedAt else { return nil }
		return (finishedAt ?? Date()).timeIntervalSince(startedAt)
	}
	
}

/// A first-in, first-out queue of privileged `port` commands. MacPorts holds a lock while it works, so jobs run one at a time.
@MainActor
final class ActivityModel: ObservableObject {
	
	/// Oldest first.
	@Published private(set) var jobs = [ActivityJob]()
	@Published var selectedJobID: ActivityJob.ID?
	@Published private(set) var unseenFailures = 0
	
	/// The title of the job that was queued last, shown briefly as a notice.
	@Published private(set) var notice: String?
	
	private var isProcessing = false
	private var noticeTask: Task<Void, Never>?
	private var jobObservers = [AnyCancellable]()
	
	var activeCount: Int { jobs.filter { $0.status.isActive }.count }
	
	/// Whether something with this key is queued or running.
	func isPending(_ key: String) -> Bool {
		jobs.contains { $0.status.isActive && $0.keys.contains(key) }
	}
	
	/// Adds a command to the queue and starts it when the ones before it are done.
	///
	/// - Returns: The job, or `nil` if something touching the same keys is already queued or running.
	@discardableResult
	func enqueue(title: String, keys: Set<String>, success: String, onFinish: (() async -> Void)? = nil,
				 command: @escaping (@escaping @Sendable (String) -> Void) async -> ActionResult) -> ActivityJob? {
		guard !keys.contains(where: isPending) else { return nil }
		
		let job = ActivityJob(title: title, keys: keys, success: success, command: command, onFinish: onFinish)
		// Rows watch the jobs, and so do the lists that count them.
		jobObservers.append(job.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
		jobs.append(job)
		selectedJobID = job.id
		showNotice("Queued: \(title)")
		processQueue()
		return job
	}
	
	/// Cancels a job that has not started. A running job cannot be stopped safely.
	func cancel(_ job: ActivityJob) {
		guard job.status == .queued else { return }
		job.status = .cancelled
		job.finishedAt = Date()
	}
	
	func clearFinished() {
		let finished = Set(jobs.filter { !$0.status.isActive }.map(\.id))
		jobs.removeAll { finished.contains($0.id) }
		if let selectedJobID, finished.contains(selectedJobID) { self.selectedJobID = jobs.last?.id }
		unseenFailures = 0
	}
	
	func markFailuresSeen() { unseenFailures = 0 }
	
	
	// MARK: - Running
	
	private func processQueue() {
		guard !isProcessing else { return }
		isProcessing = true
		Task {
			while let job = jobs.first(where: { $0.status == .queued }) {
				await run(job)
			}
			isProcessing = false
		}
	}
	
	private func run(_ job: ActivityJob) async {
		job.status = .running
		job.startedAt = Date()
		
		let result = await job.command { [weak job] text in
			Task { @MainActor in job?.log.append(text) }
		}
		
		// The reply carries the complete output, which settles any streamed text still on its way.
		let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
		let streamed = job.log.trimmingCharacters(in: .whitespacesAndNewlines)
		if !output.isEmpty {
			job.log = output
		} else if streamed.isEmpty {
			job.log = result.succeeded ? job.success : "The command failed (exit \(result.status))."
		} else {
			job.log = streamed
		}
		
		job.finishedAt = Date()
		job.status = result.succeeded ? .succeeded : .failed
		if !result.succeeded { unseenFailures += 1 }
		await job.onFinish?()
	}
	
	private func showNotice(_ text: String) {
		notice = text
		noticeTask?.cancel()
		noticeTask = Task {
			try? await Task.sleep(nanoseconds: 4_000_000_000)
			guard !Task.isCancelled else { return }
			notice = nil
		}
	}
	
	func dismissNotice() { notice = nil }
	
}
