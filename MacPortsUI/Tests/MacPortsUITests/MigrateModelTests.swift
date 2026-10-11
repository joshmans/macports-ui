import XCTest
import MacPortsKit
@testable import MacPortsUI

@MainActor
final class MigrateModelTests: XCTestCase {
	
	private func formula(_ name: String, port: String?) -> HomebrewFormula {
		HomebrewFormula(name: name, installedVersion: "1.0", availableVersion: "1.1", hasBottle: false, reason: "No bottle",
						alternative: port.map { MacPortsAlternative(name: $0, version: "1.0_0") })
	}
	
	private func makeModel() -> MigrateModel {
		let model = MigrateModel(activity: ActivityModel())
		model.apply(formulae: [formula("wget", port: "wget"), formula("dotnet", port: nil), formula("aom", port: "aom")])
		return model
	}
	
	func testOnlyFormulaeWithAnEquivalentAreShownByDefault() {
		let model = makeModel()
		XCTAssertEqual(model.visible.map(\.name), ["wget", "aom"])
		model.onlySwitchable = false
		XCTAssertEqual(model.visible.map(\.name), ["wget", "dotnet", "aom"])
		XCTAssertEqual(model.switchableCount, 2)
	}
	
	func testOnlySwitchableSelectionsCanBeSwitched() {
		let model = makeModel()
		model.selection = ["wget", "dotnet"]
		XCTAssertEqual(model.selectedSwitchable.map(\.name), ["wget"], "A formula without a MacPorts equivalent is never switched")
	}
	
	func testSelectionDropsFormulaeThatAreGoneAfterARefresh() {
		let model = makeModel()
		model.selection = ["wget", "aom"]
		model.apply(formulae: [formula("aom", port: "aom")])
		XCTAssertEqual(model.selection, ["aom"])
	}
	
	func testFormulaeAlreadyBeingSwitchedAreNotOfferedAgain() {
		let activity = ActivityModel()
		let model = MigrateModel(activity: activity)
		model.apply(formulae: [formula("wget", port: "wget")])
		model.selection = ["wget"]
		activity.enqueue(title: "busy", keys: ["wget"], success: "ok") { _ in
			try? await Task.sleep(nanoseconds: 200_000_000)
			return ActionResult(status: 0, output: "")
		}
		XCTAssertTrue(model.selectedSwitchable.isEmpty)
	}
	
	func testReviewIsDiscardedWhenCancelled() {
		let model = makeModel()
		model.selection = ["wget"]
		model.sheet = .working
		model.cancelSwitch()
		XCTAssertNil(model.sheet)
	}
	
}
