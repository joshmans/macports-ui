import XCTest
import MacPortsKit
@testable import MacPortsUI

/// Records what the fake commands did, so the tests can check order and overlap.
private actor Recorder {
	var started = [String]()
	var running = 0
	var maxRunning = 0
	
	func begin(_ name: String) {
		started.append(name)
		running += 1
		maxRunning = max(maxRunning, running)
	}
	
	func end() { running -= 1 }
}

@MainActor
final class ActivityModelTests: XCTestCase {
	
	/// Waits until the queue has nothing active.
	private func drain(_ activity: ActivityModel, timeout: TimeInterval = 5) async {
		let deadline = Date().addingTimeInterval(timeout)
		while activity.activeCount > 0, Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
	}
	
	private func command(_ name: String, _ recorder: Recorder, status: Int32 = 0, output: String = "") -> (@escaping @Sendable (String) -> Void) async -> ActionResult {
		return { onOutput in
			await recorder.begin(name)
			onOutput("working on \(name)\n")
			try? await Task.sleep(nanoseconds: 40_000_000)
			await recorder.end()
			return ActionResult(status: status, output: output.isEmpty ? "working on \(name)" : output)
		}
	}
	
	func testRunsJobsOneAtATimeInOrder() async {
		let activity = ActivityModel()
		let recorder = Recorder()
		for name in ["a", "b", "c"] {
			activity.enqueue(title: name, keys: [name], success: "ok", command: command(name, recorder))
		}
		await drain(activity)
		let started = await recorder.started
		let maxRunning = await recorder.maxRunning
		XCTAssertEqual(started, ["a", "b", "c"])
		XCTAssertEqual(maxRunning, 1, "MacPorts holds a lock, so jobs must never overlap")
		XCTAssertTrue(activity.jobs.allSatisfy { $0.status == .succeeded })
		XCTAssertEqual(activity.jobs.first?.log, "working on a")
	}
	
	func testRefusesTheSameKeyWhileItIsPending() async {
		let activity = ActivityModel()
		let recorder = Recorder()
		XCTAssertNotNil(activity.enqueue(title: "install wget", keys: ["wget"], success: "ok", command: command("wget", recorder)))
		XCTAssertTrue(activity.isPending("wget"))
		XCTAssertNil(activity.enqueue(title: "uninstall wget", keys: ["wget"], success: "ok", command: command("again", recorder)))
		await drain(activity)
		XCTAssertFalse(activity.isPending("wget"))
		XCTAssertNotNil(activity.enqueue(title: "uninstall wget", keys: ["wget"], success: "ok", command: command("wget2", recorder)), "Allowed again once the first is done")
		await drain(activity)
		let started = await recorder.started
		XCTAssertEqual(started, ["wget", "wget2"])
	}
	
	func testCancelsOnlyQueuedJobs() async {
		let activity = ActivityModel()
		let recorder = Recorder()
		let first = activity.enqueue(title: "first", keys: ["a"], success: "ok", command: command("a", recorder))!
		let second = activity.enqueue(title: "second", keys: ["b"], success: "ok", command: command("b", recorder))!
		try? await Task.sleep(nanoseconds: 10_000_000)
		activity.cancel(first)
		XCTAssertNotEqual(first.status, .cancelled, "A running command is never cancelled")
		activity.cancel(second)
		XCTAssertEqual(second.status, .cancelled)
		await drain(activity)
		let started = await recorder.started
		XCTAssertEqual(started, ["a"])
		XCTAssertFalse(activity.isPending("b"))
	}
	
	func testFailuresAreCountedUntilSeen() async {
		let activity = ActivityModel()
		let recorder = Recorder()
		activity.enqueue(title: "bad", keys: ["x"], success: "ok", command: command("x", recorder, status: 1, output: "Error: nope"))
		await drain(activity)
		XCTAssertEqual(activity.jobs.first?.status, .failed)
		XCTAssertEqual(activity.jobs.first?.log, "Error: nope")
		XCTAssertEqual(activity.unseenFailures, 1)
		activity.markFailuresSeen()
		XCTAssertEqual(activity.unseenFailures, 0)
	}
	
	func testRunsTheFinishHandlerAfterEachJobAndClearKeepsActiveJobs() async {
		let activity = ActivityModel()
		let recorder = Recorder()
		var finished = [String]()
		activity.enqueue(title: "one", keys: ["one"], success: "ok", onFinish: { finished.append("one") }, command: command("one", recorder))
		await drain(activity)
		activity.enqueue(title: "two", keys: ["two"], success: "ok", onFinish: { finished.append("two") }, command: command("two", recorder))
		activity.clearFinished()
		XCTAssertEqual(activity.jobs.map(\.title), ["two"], "Finished jobs go, the active one stays")
		await drain(activity)
		XCTAssertEqual(finished, ["one", "two"])
	}
	
	func testEmptyOutputFallsBackToTheSuccessMessage() async {
		let activity = ActivityModel()
		activity.enqueue(title: "quiet", keys: ["q"], success: "All done.") { _ in ActionResult(status: 0, output: "") }
		await drain(activity)
		XCTAssertEqual(activity.jobs.first?.log, "All done.")
	}
	
}
