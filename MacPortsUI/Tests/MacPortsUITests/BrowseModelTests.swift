import XCTest
import MacPortsKit
@testable import MacPortsUI

@MainActor
final class BrowseModelTests: XCTestCase {
	
	private let catalog = [
		CatalogPort(name: "wget", version: "1", categories: ["net"], summary: "retriever"),
		CatalogPort(name: "curl", version: "1", categories: ["net"], summary: "transfer"),
		CatalogPort(name: "tree", version: "1", categories: ["sysutils"], summary: "directory listing")
	]
	
	private func makeModel() -> BrowseModel {
		let model = BrowseModel(activity: ActivityModel())
		model.apply(catalog: catalog)
		return model
	}
	
	func testSelectionIsClearedWhenTheSearchNoLongerListsIt() {
		let model = makeModel()
		model.search = "wget"
		model.selection = "wget"
		model.search = "tree"
		XCTAssertNil(model.selection, "Details of a port that is not listed must not stay on screen")
		XCTAssertNil(model.detail)
		XCTAssertEqual(model.results.map(\.name), ["tree"])
	}
	
	func testSelectionStaysWhileItIsStillListed() {
		let model = makeModel()
		model.search = "w"
		model.selection = "wget"
		model.search = "wg"
		XCTAssertEqual(model.selection, "wget")
	}
	
	func testSelectionIsClearedWhenTheCategoryExcludesIt() {
		let model = makeModel()
		model.category = "net"
		model.selection = "curl"
		model.category = "sysutils"
		XCTAssertNil(model.selection)
	}
	
	func testSelectionIsClearedWhenTheQueryIsEmptied() {
		let model = makeModel()
		model.search = "wget"
		model.selection = "wget"
		model.search = ""
		XCTAssertTrue(model.results.isEmpty)
		XCTAssertNil(model.selection)
	}
	
}
