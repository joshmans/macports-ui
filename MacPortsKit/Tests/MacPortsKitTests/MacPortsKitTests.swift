//
//  MacPortsKitTests.swift
//  MacPortsKitTests
//

import XCTest
@testable import MacPortsKit

final class MacPortsKitTests: XCTestCase {
	
	
	
	
	
	
	
	// MARK: MacPorts
	
	func testParsesOutdatedOutput() {
		let output = """
		Warning: port definitions are more than two weeks old, consider updating them by running 'port selfupdate'.
		The following installed ports are outdated:
		aom                            3.14.1_0 < 3.15.1_0
		cairo                          1.18.4_2+quartz+x11 < 1.18.6_0
		"""
		XCTAssertEqual(MacPortsParser.parseOutdated(output), [
			.init(name: "aom", installed: "3.14.1_0", available: "3.15.1_0"),
			.init(name: "cairo", installed: "1.18.4_2+quartz+x11", available: "1.18.6_0")
		])
		XCTAssertEqual(MacPortsParser.parseOutdated("No installed ports are outdated."), [])
	}
	
	func testReadsActiveVariants() {
		let output = """
		The following ports are currently installed:
		  cairo @1.18.3_0 
		  cairo @1.18.4_2+quartz+x11 (active)
		"""
		XCTAssertEqual(MacPortsParser.activeVariants(in: output, name: "cairo"), "+quartz+x11")
		XCTAssertEqual(MacPortsParser.activeVariants(in: "  aom @3.14.1_0 (active)", name: "aom"), "")
	}
	
	func testBuildsArchiveURL() {
		let url = MacPortsParser.archiveURL(name: "cairo", version: "1.18.6_0", variants: "+quartz+x11", darwin: 25, arch: "x86_64")
		XCTAssertEqual(url?.absoluteString, "https://packages.macports.org/cairo/cairo-1.18.6_0+quartz+x11.darwin_25.x86_64.tbz2")
	}
	
	func testRejectsUnsafePortNames() {
		XCTAssertTrue(MacPortsParser.isValidPortName("py313-tkinter"))
		XCTAssertTrue(MacPortsParser.isValidPortName("gtk3+x11"))
		XCTAssertFalse(MacPortsParser.isValidPortName("foo; rm -rf /"))
		XCTAssertFalse(MacPortsParser.isValidPortName("-N"))
		XCTAssertFalse(MacPortsParser.isValidPortName("a b"))
	}
	
	func testMapsHomebrewNamesToPortNames() {
		XCTAssertTrue(MacPortsParser.candidateNames(forHomebrewFormula: "python@3.13").contains("python313"))
		XCTAssertTrue(MacPortsParser.candidateNames(forHomebrewFormula: "gtk+3").contains("gtk3"))
		XCTAssertTrue(MacPortsParser.candidateNames(forHomebrewFormula: "qtbase").contains("qt6-qtbase"))
		XCTAssertTrue(MacPortsParser.candidateNames(forHomebrewFormula: "python-tk@3.12").contains("py312-tkinter"))
	}
	
	func testFindsNewestArchiveInListing() {
		let html = """
		<a href="rust-1.98.0_0.darwin_25.x86_64.tbz2">a</a>
		<a href="rust-1.99.0_0.darwin_25.x86_64.tbz2">b</a>
		<a href="rust-2.0.0_0.darwin_25.arm64.tbz2">c</a>
		<a href="rust-9.0.0_0.darwin_24.x86_64.tbz2">d</a>
		<a href="rust-1.99.0_0.darwin_25.x86_64.tbz2.sig">e</a>
		"""
		XCTAssertEqual(MacPortsParser.newestArchiveVersion(inListing: html, port: "rust", darwin: 25, arch: "x86_64"), "1.99.0_0")
		XCTAssertNil(MacPortsParser.newestArchiveVersion(inListing: html, port: "rust", darwin: 27, arch: "x86_64"))
	}
	
	func testNoarchArchivesCountAsPrebuilt() {
		let html = "<a href=\"yt-dlp-2026.08.19_0+ffmpeg+python314.darwin_any.noarch.tbz2\">a</a><a href=\"yt-dlp-2026.06.09_0+python314.darwin_any.noarch.tbz2\">b</a>"
		XCTAssertEqual(MacPortsParser.newestArchiveVersion(inListing: html, port: "yt-dlp", darwin: 25, arch: "x86_64"), "2026.08.19_0+ffmpeg+python314")
	}
	
	func testChecksBothArchitectureSpecificAndNoarchURLs() {
		let urls = MacPortsParser.archiveURLs(name: "pipx", version: "1.17.2_0", variants: "+python314", darwin: 25, arch: "x86_64").map(\.lastPathComponent)
		XCTAssertEqual(urls, ["pipx-1.17.2_0+python314.darwin_25.x86_64.tbz2", "pipx-1.17.2_0+python314.darwin_any.noarch.tbz2"])
	}
	
	func testDetectsStaleIndexAgainstArchives() {
		XCTAssertFalse(MacPortsParser.archiveMatchesIndex(archiveVersion: "2.9.7_0", indexVersion: "2.9.6", indexRevision: "0"))
		XCTAssertTrue(MacPortsParser.archiveMatchesIndex(archiveVersion: "2026.08.19_0+ffmpeg+python314", indexVersion: "2026.08.19", indexRevision: "0"))
		XCTAssertFalse(MacPortsParser.archiveMatchesIndex(archiveVersion: "1.2.10_0", indexVersion: "1.2.1", indexRevision: "0"), "A longer version must not match by prefix")
		XCTAssertFalse(MacPortsParser.archiveMatchesIndex(archiveVersion: "1.25.0_1+gnutls", indexVersion: "1.25.0", indexRevision: "0"))
	}
	
	
	func testShellQuoting() {
		XCTAssertEqual(CommandRunner.shellQuote("it's"), "'it'\\''s'")
	}
	
	// MARK: MacPorts browsing
	
	func testParsesSearchLines() {
		let output = "Warning: port definitions are more than two weeks old\nwget\t1.25.0\tnet www\tinternet file retriever\nwget2\t2.2.1\tnet www\tGNU Wget2\nNo match for xyz found"
		let results = MacPortsParser.parseSearch(output)
		XCTAssertEqual(results.map(\.name), ["wget", "wget2"])
		XCTAssertEqual(results.first?.categories, ["net", "www"])
		XCTAssertEqual(results.first?.summary, "internet file retriever")
	}
	
	func testParsesInstalledOutput() {
		let output = "The following ports are currently installed:\n  aom @3.14.1_0 (active)\n  cairo @1.18.3_0\n  cairo @1.18.4_2+quartz+x11 (active)"
		let parsed = MacPortsParser.parseInstalled(output)
		XCTAssertEqual(parsed.map(\.name), ["aom", "cairo", "cairo"])
		XCTAssertEqual(parsed.filter(\.isActive).map(\.version), ["3.14.1_0", "1.18.4_2+quartz+x11"])
	}
	
	func testParsesInfo() {
		let info = MacPortsParser.parseInfo("Warning: old\nfullname: wget @1.25.0\ncategory: net, www\ndescription: internet file retriever")
		XCTAssertEqual(info["fullname"], "wget @1.25.0")
		XCTAssertEqual(info["category"], "net, www")
	}
	
	func testValidatesVariantSelections() {
		XCTAssertTrue(MacPortsParser.isValidVariantSelection(""))
		XCTAssertTrue(MacPortsParser.isValidVariantSelection("+x11 -quartz"))
		XCTAssertFalse(MacPortsParser.isValidVariantSelection("+x11; reboot"))
		XCTAssertFalse(MacPortsParser.isValidVariantSelection("x11"))
	}
	
	// MARK: Switching
	
	private func brew(_ name: String, alternative: String?) -> PackageUpdate {
		PackageUpdate(manager: .homebrew, name: name, installedVersion: "1", availableVersion: "2", state: .wouldCompile(reason: "x"),
					  alternative: alternative.map { .init(manager: .macPorts, name: $0, version: "1") })
	}
	
	private let ports = ["aom": "aom", "ffmpeg": "ffmpeg", "deno": "deno", "yt-dlp": "yt-dlp", "gh": "gh", "imagemagick": "imagemagick"]
	
	func testSwitchPullsDependentsIntoTheGroupAndOrdersThemFirst() {
		let reverse = ["aom": ["ffmpeg"], "ffmpeg": ["imagemagick"]]
		let plan = PackageSwitch.plan(selected: [brew("aom", alternative: "aom")], reverseDependencies: reverse, alternative: { self.ports[$0] })
		XCTAssertEqual(plan.groups.count, 1)
		XCTAssertEqual(plan.groups.first?.formulae, ["imagemagick", "ffmpeg", "aom"])
		XCTAssertEqual(plan.groups.first?.pulledIn, ["ffmpeg", "imagemagick"])
		XCTAssertTrue(plan.blocked.isEmpty)
	}
	
	func testSwitchBlocksGroupWhenADependentHasNoEquivalent() {
		let plan = PackageSwitch.plan(selected: [brew("deno", alternative: "deno")], reverseDependencies: ["deno": ["yt-dlp"]], alternative: { $0 == "deno" ? "deno" : nil })
		XCTAssertTrue(plan.groups.isEmpty)
		XCTAssertEqual(plan.blocked.first?.package, "deno")
		XCTAssertTrue(plan.blocked.first?.reason.contains("yt-dlp") ?? false)
	}
	
	func testSwitchRefusesOversizedGroups() {
		let reverse = ["aom": (0..<30).map { "dep\($0)" }]
		let plan = PackageSwitch.plan(selected: [brew("aom", alternative: "aom")], reverseDependencies: reverse, alternative: { $0 })
		XCTAssertTrue(plan.groups.isEmpty)
		XCTAssertTrue(plan.blocked.first?.reason.contains("limit") ?? false)
	}
	
	func testOverlappingSelectionsMergeIntoOneGroup() {
		let plan = PackageSwitch.plan(selected: [brew("a", alternative: "a"), brew("b", alternative: "b")], reverseDependencies: ["a": ["shared"], "b": ["shared"]], alternative: { $0 })
		XCTAssertEqual(plan.groups.count, 1)
		XCTAssertEqual(Set(plan.groups[0].formulae), ["a", "b", "shared"])
		XCTAssertEqual(plan.groups[0].formulae.first, "shared")
	}
	
	func testIndependentPackagesStaySeparateGroups() {
		let plan = PackageSwitch.plan(selected: [brew("gh", alternative: "gh"), brew("deno", alternative: "deno")], reverseDependencies: [:], alternative: { self.ports[$0] })
		XCTAssertEqual(plan.groups.count, 2)
	}
	
	func testRejectsUnsafePortNameFromAlternative() {
		let plan = PackageSwitch.plan(selected: [brew("evil", alternative: "x")], reverseDependencies: [:], alternative: { _ in "x; rm -rf /" })
		XCTAssertTrue(plan.groups.isEmpty)
		XCTAssertEqual(plan.blocked.count, 1)
	}
	
	
	// MARK: Privileged actions
	
	func testActionsProduceExactlyTheAllowedArguments() {
		XCTAssertEqual(PortAction.selfUpdate.arguments, ["-N", "selfupdate"])
		XCTAssertEqual(PortAction.install(ports: ["wget"], variants: ["+ssl"], binaryOnly: true).arguments, ["-N", "-p", "-b", "install", "wget", "+ssl"])
		XCTAssertEqual(PortAction.install(ports: ["a", "b"], variants: [], binaryOnly: false).arguments, ["-N", "-p", "install", "a", "b"])
		XCTAssertEqual(PortAction.upgrade(ports: ["a"]).arguments, ["-N", "-b", "upgrade", "a"])
		XCTAssertEqual(PortAction.uninstall(port: "a").arguments, ["-N", "uninstall", "a"])
	}
	
	func testActionsRoundTripThroughArguments() {
		let actions: [PortAction] = [.selfUpdate, .install(ports: ["wget"], variants: ["+ssl", "-x11"], binaryOnly: true), .install(ports: ["a", "b"], variants: [], binaryOnly: false), .upgrade(ports: ["a", "b"]), .uninstall(port: "py313-tkinter")]
		for action in actions { XCTAssertEqual(PortAction(arguments: action.arguments!), action) }
	}
	
	func testRejectsEverythingOutsideTheAllowList() {
		let rejected: [[String]] = [
			[], ["selfupdate"], ["-N"], ["-N", "sync"], ["-N", "clean", "--all", "foo"], ["-N", "-b", "upgrade"],
			["-N", "install", "foo"], ["-N", "-p", "-b", "install"], ["-N", "-p", "-b", "install", "foo; reboot"],
			["-N", "-p", "-b", "install", "-f", "foo"], ["-N", "uninstall", "a", "b"], ["-N", "uninstall", "--follow-dependents", "a"],
			["-N", "-p", "install", "file:///tmp/evil"], ["-N", "-p", "install", "../evil"], ["-N", "-p", "-b", "install", "a", "b", "+x11"],
			["-N", "-D", "/tmp", "selfupdate"], ["-v", "-N", "selfupdate"]
		]
		for arguments in rejected { XCTAssertNil(PortAction(arguments: arguments), "\(arguments) must be rejected") }
		XCTAssertNil(PortAction.install(ports: [], variants: [], binaryOnly: true).arguments)
		XCTAssertNil(PortAction.install(ports: Array(repeating: "a", count: 201), variants: [], binaryOnly: true).arguments)
	}
	
	func testRefusesPseudoPortNames() {
		for name in ["installed", "all", "inactive", "Outdated", "leaves"] {
			XCTAssertNil(PortAction.uninstall(port: name).arguments, "\(name) would act on many ports")
			if name != "inactive" { XCTAssertNil(PortAction(arguments: ["-N", "uninstall", name]), name) }
		}
		XCTAssertEqual(PortAction.uninstallInactive.arguments, ["-N", "uninstall", "inactive"])
		XCTAssertEqual(PortAction(arguments: ["-N", "uninstall", "inactive"]), .uninstallInactive)
	}
	
	func testGroupsInstalledPorts() {
		let all = MacPortsParser.parseInstalled("  aom @3.14.1_0\n  aom @3.15.1_0 (active)\n  glib2 @2.88.3_1+x11 (active)\n  bash @5.3.15_0")
		let ports = MacPortsParser.installedPorts(all: all, requested: ["glib2"], leaves: ["glib2", "bash"])
		XCTAssertEqual(ports.map(\.name), ["aom", "bash", "glib2"])
		XCTAssertEqual(ports[0].version, "3.15.1_0")
		XCTAssertEqual(ports[0].inactiveVersions, ["3.14.1_0"])
		XCTAssertEqual(ports[2].variants, "+x11")
		XCTAssertTrue(ports[2].isRequested)
		XCTAssertFalse(ports[1].isActive, "A port with no active version is flagged")
		XCTAssertTrue(ports[1].inactiveVersions.isEmpty)
	}
	
	func testParsesDependents() {
		XCTAssertEqual(MacPortsParser.parseDependents("shared-mime-info depends on bash\nWarning: old\ngit depends on bash"), ["shared-mime-info", "git"])
		XCTAssertEqual(MacPortsParser.parseDependents("Port bash has no dependents!"), [])
	}
	
	func testParsesVariants() {
		let output = """
		wget has the variants:
		[+]gnutls: SSL support via GnuTLS
		     * conflicts with ssl
		   metalink: Metalink support
		   ssl: SSL support via OpenSSL
		     * conflicts with gnutls
		   universal: Build for multiple architectures
		"""
		let variants = MacPortsParser.parseVariants(output)
		XCTAssertEqual(variants.map(\.name), ["gnutls", "metalink", "ssl", "universal"])
		XCTAssertEqual(variants.filter(\.isDefault).map(\.name), ["gnutls"])
		XCTAssertEqual(variants[0].conflicts, ["ssl"])
		XCTAssertEqual(variants[0].description, "SSL support via GnuTLS")
		XCTAssertTrue(MacPortsParser.parseVariants("Port nosuch not found").isEmpty)
	}
	
	func testSearchRanksNameMatchesFirst() {
		let ports = [
			CatalogPort(name: "gdown", version: "1", categories: ["net"], summary: "Downloader when Curl/Wget fails"),
			CatalogPort(name: "wget2", version: "1", categories: ["net"], summary: "successor"),
			CatalogPort(name: "libwget", version: "1", categories: ["devel"], summary: "library"),
			CatalogPort(name: "wget", version: "1", categories: ["net", "www"], summary: "retriever")
		]
		XCTAssertEqual(Catalog.search("wget", in: ports).map(\.name), ["wget", "wget2", "libwget", "gdown"])
		XCTAssertEqual(Catalog.search("WGET", in: ports, category: "devel").map(\.name), ["libwget"])
		XCTAssertEqual(Catalog.search("", in: ports, category: "www").map(\.name), ["wget"])
		XCTAssertEqual(Catalog.search("wget", in: ports, limit: 2).count, 2)
		XCTAssertEqual(Catalog.categories(in: ports).first?.name, "net")
	}
	
	private let wgetVariants = [
		PortVariant(name: "gnutls", description: "", isDefault: true, conflicts: ["ssl"]),
		PortVariant(name: "metalink", description: "", isDefault: false, conflicts: []),
		PortVariant(name: "ssl", description: "", isDefault: false, conflicts: ["gnutls"]),
		PortVariant(name: "universal", description: "", isDefault: false, conflicts: [])
	]
	
	func testVariantSelectionStartsAtDefaults() {
		let selection = VariantSelection(variants: wgetVariants)
		XCTAssertTrue(selection.isDefault)
		XCTAssertEqual(selection.arguments, [])
		XCTAssertEqual(selection.archiveSuffix, "+gnutls")
	}
	
	func testEnablingAVariantTurnsOffItsConflicts() {
		var selection = VariantSelection(variants: wgetVariants)
		selection.set("ssl", enabled: true)
		XCTAssertFalse(selection.isEnabled("gnutls"))
		XCTAssertEqual(selection.arguments, ["-gnutls", "+ssl"])
		XCTAssertEqual(selection.archiveSuffix, "+ssl")
		selection.set("metalink", enabled: true)
		XCTAssertEqual(selection.archiveSuffix, "+metalink+ssl", "Archive names list variants alphabetically")
		selection.set("gnutls", enabled: true)
		XCTAssertFalse(selection.isEnabled("ssl"), "Conflicts work in both directions")
	}
	
	func testVariantArgumentsAreAlwaysValidForTheHelper() {
		var selection = VariantSelection(variants: wgetVariants)
		selection.set("ssl", enabled: true)
		selection.set("universal", enabled: true)
		XCTAssertNotNil(PortAction.install(ports: ["wget"], variants: selection.arguments, binaryOnly: true).arguments)
		selection.set("nonexistent", enabled: true)
		XCTAssertFalse(selection.isEnabled("nonexistent"))
	}
	
	func testParsesDependencyTree() {
		let output = "The following ports are dependencies of wget @1.25.0_1:\n  gettext-runtime\n    libiconv\n  libidn2\n    libiconv\n  zlib"
		XCTAssertEqual(MacPortsParser.parseDependencyTree(output), ["gettext-runtime", "libiconv", "libidn2", "zlib"])
	}
	
	func testParsesDirectDependencies() {
		let output = "Full Name: wget @1.25.0_1+ssl\nExtract Dependencies: lzip\nBuild Dependencies:   gettext, perl5.34\nLibrary Dependencies: gettext-runtime, zlib, openssl3\nRuntime Dependencies: ca-certs\nTest Dependencies:    p5.34-io-socket-ssl"
		XCTAssertEqual(MacPortsParser.parseDirectDependencies(output), ["gettext-runtime", "zlib", "openssl3", "ca-certs"])
	}
	
	func testParsesInfoBlocks() {
		let blocks = MacPortsParser.parseInfoBlocks("name: a\nversion: 1\nrevision: 0\n--\nname: b\nversion: 2\nrevision: 1")
		XCTAssertEqual(blocks.map { $0["name"] }, ["a", "b"])
		XCTAssertEqual(blocks[1]["revision"], "1")
	}
	
	func testInstallPlanKnowsWhatWouldCompile() {
		let missing = [PlannedDependency(name: "a", version: "1_0", isPrebuilt: true), PlannedDependency(name: "b", version: "1_0", isPrebuilt: false)]
		let plan = InstallPlan(port: "x", prebuilt: .available(version: "1_0"), missingDependencies: missing, installedDependencies: 3)
		XCTAssertEqual(plan.wouldCompile, ["b"])
		XCTAssertFalse(plan.canInstallPrebuilt)
		let good = InstallPlan(port: "x", prebuilt: .available(version: "1_0"), missingDependencies: [missing[0]], installedDependencies: 3)
		XCTAssertTrue(good.canInstallPrebuilt)
		XCTAssertEqual(InstallPlan(port: "x", prebuilt: .unavailable, missingDependencies: [], installedDependencies: 0).wouldCompile, ["x"])
	}
	
	func testSplitsBatchedOutputIntoPerStepResults() {
		let output = "Selfupdate ok\n@@PORT-EXIT:0\nInstalling\nfailed\n@@PORT-EXIT:1\n"
		let results = PromptingPortRunner.splitResults(output, expected: 2, fallbackStatus: 0)
		XCTAssertEqual(results.map(\.status), [0, 1])
		XCTAssertEqual(results[1].output, "Installing\nfailed")
	}
	
	func testCancelledPromptMarksAllStepsAsNotRun() {
		let results = PromptingPortRunner.splitResults("execution error: User canceled. (-128)", expected: 2, fallbackStatus: 1)
		XCTAssertEqual(results.count, 2)
		XCTAssertTrue(results.allSatisfy { $0.status != 0 })
	}
	
	// MARK: Helper
	
	func testHelperRequirementNeedsATeamIdentifier() {
		XCTAssertNil(HelperConstants.requirement(identifier: "com.otstechs.macportsui", teamIdentifier: nil))
		XCTAssertNil(HelperConstants.requirement(identifier: "com.otstechs.macportsui", teamIdentifier: ""))
		XCTAssertNil(HelperConstants.requirement(identifier: "com.otstechs.macportsui", teamIdentifier: "abc\" or anchor apple"), "A team identifier must not be able to inject requirement syntax")
		XCTAssertEqual(HelperConstants.requirement(identifier: "com.otstechs.macportsui", teamIdentifier: "ABCDE12345"),
					   "anchor apple generic and identifier \"com.otstechs.macportsui\" and certificate leaf[subject.OU] = \"ABCDE12345\"")
	}
	
	func testHelperIsUnavailableInUnsignedBuilds() {
		guard case .unavailable = PrivilegedHelper.status else { return XCTFail("The test host has no embedded helper") }
	}
	
	func testRunnerFallsBackToPromptWithoutHelper() {
		XCTAssertTrue(PortPrivileges.runner is PromptingPortRunner)
	}
	
	// MARK: Version relations
	
	func testComparesPackageVersions() {
		XCTAssertEqual(PackageVersions.relation(of: "3.31.12_0", to: "4.4.4"), .older)
		XCTAssertEqual(PackageVersions.relation(of: "6.2.4_0+openssl", to: "6.2.2"), .newer)
		XCTAssertEqual(PackageVersions.relation(of: "1.25.0_1+gnutls", to: "1.25.0_2"), .same)
		XCTAssertEqual(PackageVersions.relation(of: "1.10.0", to: "1.9.0"), .newer, "Numbers compare numerically")
		XCTAssertEqual(PackageVersions.relation(of: "2026.08.19_0+ffmpeg", to: "2026.8.19"), .same)
		XCTAssertEqual(PackageVersions.base("1.25.0_1+gnutls"), "1.25.0")
	}
}
