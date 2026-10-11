//
//  Homebrew.swift
//  MacPortsKit
//
//  Moving Homebrew formulae over to prebuilt MacPorts ports.
//

import Foundation

/// Decides whether Homebrew has a prebuilt bottle for a given machine.
enum HomebrewBottles {
	
	private static let releaseNames: [(major: Int, name: String)] = [
		(27, "golden_gate"), (26, "tahoe"), (15, "sequoia"), (14, "sonoma"), (13, "ventura"), (12, "monterey"), (11, "big_sur")
	]
	
	/// The bottle tags usable on the given system, newest first. Homebrew falls back to bottles built for older macOS releases.
	static func usableTags(arm64: Bool, macOSMajor: Int) -> [String] {
		let prefix = arm64 ? "arm64_" : ""
		return releaseNames.filter { $0.major <= macOSMajor }.map { prefix + $0.name } + ["all"]
	}
	
	static func hasBottle(files: Set<String>, arm64: Bool, macOSMajor: Int) -> Bool {
		!files.isDisjoint(with: usableTags(arm64: arm64, macOSMajor: macOSMajor))
	}
	
}

/// The prebuilt MacPorts port that could replace a Homebrew formula.
public struct MacPortsAlternative: Hashable, Sendable {
	public let name: String
	public let version: String
	
	public init(name: String, version: String) {
		self.name = name
		self.version = version
	}
}

/// An outdated Homebrew formula.
public struct HomebrewFormula: Identifiable, Hashable, Sendable {
	public var id: String { name }
	public let name: String
	public let installedVersion: String
	public let availableVersion: String
	
	/// Whether Homebrew can upgrade it without compiling.
	public let hasBottle: Bool
	
	/// Why Homebrew would have to compile it, if it would.
	public let reason: String?
	
	/// The prebuilt MacPorts equivalent, if one exists.
	public let alternative: MacPortsAlternative?
	
	public init(name: String, installedVersion: String, availableVersion: String, hasBottle: Bool, reason: String?, alternative: MacPortsAlternative?) {
		self.name = name
		self.installedVersion = installedVersion
		self.availableVersion = availableVersion
		self.hasBottle = hasBottle
		self.reason = reason
		self.alternative = alternative
	}
	
	/// How the MacPorts version relates to the one installed from Homebrew.
	public var alternativeRelation: PackageVersions.Relation? {
		alternative.map { PackageVersions.relation(of: $0.version, to: installedVersion) }
	}
}

/// What a switch would do, for the user to review before anything changes.
public struct SwitchPreview: Sendable {
	
	public struct Entry: Identifiable, Hashable, Sendable {
		public var id: String { formula }
		public let formula: String
		public let port: String
		public let portVersion: String?
		
		/// The version installed from Homebrew, known only for the packages the user selected.
		public let installedVersion: String?
		
		/// Whether the MacPorts version is older than the Homebrew one.
		public let isOlder: Bool
		
		/// Whether it is only included because it depends on something the user selected.
		public let isPulledIn: Bool
	}
	
	public struct Blocked: Identifiable, Hashable, Sendable {
		public var id: String { package }
		public let package: String
		public let reason: String
	}
	
	/// Groups of formulae that move together, in the order Homebrew can uninstall them: dependents first.
	public let groups: [[Entry]]
	public let blocked: [Blocked]
	
	/// Ports whose local index version no longer matches the prebuilt archive. The index is refreshed first.
	public let outdatedIndex: [String]
	
	let planGroups: [PackageSwitch.Group]
	
	public var formulaCount: Int { groups.reduce(0) { $0 + $1.count } }
	public var canSwitch: Bool { !groups.isEmpty }
	
	/// Every port that would be installed.
	var ports: [String] { Array(Set(planGroups.flatMap { $0.ports.values })).sorted() }
	
}

public enum HomebrewClient {
	
	private static let environment = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]
	
	/// Without this, Homebrew silently removes other "unneeded" formulae too, which would remove things the user did not choose.
	static let uninstallEnvironment = environment.merging(["HOMEBREW_NO_AUTOREMOVE": "1"]) { $1 }
	
	static var brewPath: String? {
		["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
	}
	
	public static var isInstalled: Bool { brewPath != nil }
	
	
	// MARK: - Outdated formulae
	
	/// Lists outdated formulae, whether Homebrew could upgrade each without compiling, and the prebuilt MacPorts equivalent of each.
	public static func fetchOutdated() async -> [HomebrewFormula] {
		await Task.detached(priority: .userInitiated) { fetchOutdatedBlocking() }.value
	}
	
	static func fetchOutdatedBlocking(arm64: Bool = SystemInfo.isARM, macOSMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> [HomebrewFormula] {
		guard let brew = brewPath else { return [] }
		
		let outdated = CommandRunner.run(brew, ["outdated", "--formula", "--json=v2"], environment: environment)
		guard let root = json(outdated.output)?["formulae"] as? [[String: Any]], !root.isEmpty else { return [] }
		
		let names = root.compactMap { $0["name"] as? String }
		let info = CommandRunner.run(brew, ["info", "--formula", "--json=v2"] + names, environment: environment)
		var details = [String: [String: Any]]()
		for entry in (json(info.output)?["formulae"] as? [[String: Any]]) ?? [] {
			if let name = entry["name"] as? String { details[name] = entry }
		}
		
		func hasBottle(_ name: String) -> Bool {
			let stable = (details[name]?["bottle"] as? [String: Any])?["stable"] as? [String: Any]
			let files = Set((stable?["files"] as? [String: Any])?.keys.map { $0 } ?? [])
			return HomebrewBottles.hasBottle(files: files, arm64: arm64, macOSMajor: macOSMajor)
		}
		
		// Equivalents are looked up over the network, so do them side by side.
		let lock = NSLock()
		var alternatives = [String: MacPortsAlternative]()
		DispatchQueue.concurrentPerform(iterations: names.count) { index in
			guard let found = MacPortsPackageChecker.equivalent(forHomebrewFormula: names[index]) else { return }
			lock.lock(); alternatives[names[index]] = MacPortsAlternative(name: found.name, version: found.version); lock.unlock()
		}
		
		let outdatedNames = Set(names)
		return root.compactMap { entry in
			guard let name = entry["name"] as? String else { return nil }
			let installed = (entry["installed_versions"] as? [String])?.last ?? "?"
			let available = entry["current_version"] as? String ?? "?"
			
			var reason: String?
			if !hasBottle(name) {
				reason = "No prebuilt bottle for this Mac"
			} else if let dependencies = details[name]?["dependencies"] as? [String],
					  let blocker = dependencies.first(where: { outdatedNames.contains($0) && !hasBottle($0) }) {
				reason = "Needs \(blocker), which has no prebuilt bottle"
			}
			return HomebrewFormula(name: name, installedVersion: installed, availableVersion: available, hasBottle: reason == nil, reason: reason, alternative: alternatives[name])
		}.sorted { $0.name < $1.name }
	}
	
	
	// MARK: - Reverse dependencies
	
	/// For each installed formula, the installed formulae that depend on it at runtime. One call instead of a slow `brew uses` per formula.
	static func reverseDependencies() -> [String: [String]] {
		guard let brew = brewPath else { return [:] }
		return reverseDependencies(fromInfoJSON: CommandRunner.run(brew, ["info", "--json=v2", "--installed", "--formula"], environment: environment).output)
	}
	
	static func reverseDependencies(fromInfoJSON output: String) -> [String: [String]] {
		guard let formulae = json(output)?["formulae"] as? [[String: Any]] else { return [:] }
		var reverse = [String: [String]]()
		for formula in formulae {
			guard let name = formula["name"] as? String,
				  let installed = (formula["installed"] as? [[String: Any]])?.last,
				  let dependencies = installed["runtime_dependencies"] as? [[String: Any]] else { continue }
			for dependency in dependencies.compactMap({ $0["full_name"] as? String }) {
				reverse[dependency, default: []].append(name)
			}
		}
		return reverse
	}
	
	static func json(_ output: String) -> [String: Any]? {
		// Skip any warnings printed before the JSON document.
		guard let start = output.firstIndex(of: "{"), let data = String(output[start...]).data(using: .utf8) else { return nil }
		return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
	}
	
	
	// MARK: - Removing
	
	static func isInstalled(formula name: String) -> Bool {
		guard let brew = brewPath else { return false }
		return CommandRunner.run(brew, ["list", "--formula", "--versions", name], environment: environment).output
			.split(separator: "\n").contains { $0.hasPrefix(name + " ") }
	}
	
	/// Uninstalls a formula. Homebrew itself refuses if other formulae still depend on it, and this never passes `--force` or `--ignore-dependencies`.
	static func uninstall(formula name: String) -> CommandRunner.Result {
		guard let brew = brewPath else { return .init(status: -1, output: "Homebrew is not installed.") }
		return CommandRunner.run(brew, ["uninstall", "--formula", name], environment: uninstallEnvironment)
	}
	
	
	// MARK: - Switching
	
	/// Works out what switching the given formulae would do, without changing anything.
	public static func previewSwitch(of selected: [HomebrewFormula]) async -> SwitchPreview {
		await Task.detached(priority: .userInitiated) { previewSwitchBlocking(of: selected) }.value
	}
	
	static func previewSwitchBlocking(of selected: [HomebrewFormula]) -> SwitchPreview {
		let candidates = selected.filter { $0.alternative != nil }
		let reverse = reverseDependencies()
		
		var known = [String: MacPortsAlternative?]()
		for formula in candidates { known[formula.name] = .some(formula.alternative) }
		
		// Look up the equivalents of everything that would move, in parallel. Chains that are too large are blocked anyway, so they are skipped.
		let wanted = candidates.reduce(into: Set<String>()) { result, formula in
			let chain = PackageSwitch.closure(of: formula.name, reverseDependencies: reverse)
			if chain.count <= PackageSwitch.maximumGroupSize { result.formUnion(chain) }
		}.subtracting(known.keys).sorted()
		let lock = NSLock()
		var found = [String: MacPortsAlternative?]()
		DispatchQueue.concurrentPerform(iterations: wanted.count) { index in
			let alternative = MacPortsPackageChecker.equivalent(forHomebrewFormula: wanted[index]).map { MacPortsAlternative(name: $0.name, version: $0.version) }
			lock.lock(); found[wanted[index]] = .some(alternative); lock.unlock()
		}
		known.merge(found) { first, _ in first }
		
		let updates = candidates.map {
			PackageUpdate(manager: .homebrew, name: $0.name, installedVersion: $0.installedVersion, availableVersion: $0.availableVersion, state: .wouldCompile(reason: $0.reason ?? ""))
		}
		let plan = PackageSwitch.plan(selected: updates, reverseDependencies: reverse) { known[$0]??.name }
		
		// Prebuilt archives are published for the newest port versions. A stale local index asks for versions that no longer exist.
		let planned = Set(plan.groups.flatMap { $0.ports.values })
		var archiveVersions = [String: String]()
		for alternative in known.values.compactMap({ $0 }) where planned.contains(alternative.name) { archiveVersions[alternative.name] = alternative.version }
		let outdatedIndex = MacPortsPackageChecker.portsWithOutdatedIndex(archiveVersions)
		
		let installedVersions = Dictionary(uniqueKeysWithValues: selected.map { ($0.name, $0.installedVersion) })
		let groups = plan.groups.map { group in
			group.formulae.map { formula -> SwitchPreview.Entry in
				let version = known[formula]??.version
				let installed = installedVersions[formula]
				let older = version.flatMap { v in installed.map { PackageVersions.relation(of: v, to: $0) == .older } } ?? false
				return SwitchPreview.Entry(formula: formula, port: group.ports[formula] ?? "?", portVersion: version.map(PackageVersions.base),
										   installedVersion: installed.map(PackageVersions.base), isOlder: older, isPulledIn: group.pulledIn.contains(formula))
			}
		}
		return SwitchPreview(groups: groups, blocked: plan.blocked.map { .init(package: $0.package, reason: $0.reason) }, outdatedIndex: outdatedIndex, planGroups: plan.groups)
	}
	
	/// Switches the previewed formulae to MacPorts.
	///
	/// Every port is installed first, from prebuilt archives only. A group of Homebrew formulae is uninstalled only after all of its ports are confirmed installed, dependents first, and the group stops at the first removal that fails. The returned status is 0 only if every group was fully switched.
	public static func executeSwitch(_ preview: SwitchPreview, onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached { executeSwitchBlocking(preview, onOutput: onOutput) }.value
	}
	
	static func executeSwitchBlocking(_ preview: SwitchPreview, backend: SwitchBackend = LiveSwitchBackend(), onOutput: (@Sendable (String) -> Void)?) -> ActionResult {
		let log = LogBuffer(forward: onOutput)
		if let problem = backend.unavailableReason { return ActionResult(status: -1, output: problem) }
		
		let ports = preview.ports
		log.add("Installing \(ports.count) MacPorts port(s) from prebuilt archives…\n")
		
		// Refreshing a stale index and installing share one administrator prompt. Installs are split into chunks to keep each command short.
		var actions = [PortAction]()
		if !preview.outdatedIndex.isEmpty { actions.append(.selfUpdate) }
		for chunk in ports.chunked(into: 100) { actions.append(.install(ports: chunk, variants: [], binaryOnly: true)) }
		backend.runPortActions(actions, onOutput: { log.add($0) })
		
		// One call tells which ports ended up installed. Nothing leaves Homebrew unless its whole group is there.
		let active = backend.activePorts()
		var completeGroups = 0
		for group in preview.planGroups {
			let missing = group.ports.values.filter { !active.contains($0) }
			guard missing.isEmpty else {
				log.add("\nKept \(group.formulae.joined(separator: ", ")) in Homebrew: MacPorts did not install \(missing.sorted().joined(separator: ", ")).\n")
				continue
			}
			var failed = false
			for formula in group.formulae {
				guard backend.isInstalled(formula: formula) else {
					log.add("\(formula): already removed from Homebrew.\n")
					continue
				}
				log.add("\nRemoving \(formula) from Homebrew…\n")
				let removal = backend.uninstall(formula: formula)
				log.add(String(removal.output.suffix(600)) + "\n")
				if removal.status != 0 {
					log.add("Stopped this group at \(formula). The remaining formulae were left in place; their MacPorts copies stay installed.\n")
					failed = true
					break
				}
			}
			if !failed { completeGroups += 1 }
		}
		
		let done = completeGroups == preview.planGroups.count
		log.add(done ? "\nSwitched \(preview.formulaCount) package(s) to MacPorts.\n" : "\nSome groups were not switched. See above.\n")
		return ActionResult(status: done ? 0 : 1, output: log.text)
	}
	
}

/// What a switch needs from the machine. Replaced in tests, so the removal logic can be checked without touching Homebrew or MacPorts.
protocol SwitchBackend {
	
	/// A message if the switch cannot run at all.
	var unavailableReason: String? { get }
	
	func runPortActions(_ actions: [PortAction], onOutput: @escaping (String) -> Void)
	func activePorts() -> Set<String>
	func isInstalled(formula: String) -> Bool
	func uninstall(formula: String) -> CommandRunner.Result
	
}

struct LiveSwitchBackend: SwitchBackend {
	
	var unavailableReason: String? {
		if !MacPortsPackageChecker.isInstalled { return "MacPorts is not installed." }
		if !HomebrewClient.isInstalled { return "Homebrew is not installed." }
		return nil
	}
	
	func runPortActions(_ actions: [PortAction], onOutput: @escaping (String) -> Void) {
		_ = MacPortsPackageChecker.runBatch(actions, onOutput: onOutput)
	}
	
	func activePorts() -> Set<String> { MacPortsPackageChecker.activePorts() }
	func isInstalled(formula: String) -> Bool { HomebrewClient.isInstalled(formula: formula) }
	func uninstall(formula: String) -> CommandRunner.Result { HomebrewClient.uninstall(formula: formula) }
	
}

/// Collects output from several threads while passing it on as it arrives.
final class LogBuffer: @unchecked Sendable {
	
	private let lock = NSLock()
	private var storage = ""
	private let forward: (@Sendable (String) -> Void)?
	
	init(forward: (@Sendable (String) -> Void)?) { self.forward = forward }
	
	func add(_ text: String) {
		lock.lock(); storage += text; lock.unlock()
		forward?(text)
	}
	
	var text: String { lock.lock(); defer { lock.unlock() }; return storage }
	
}

extension Array {
	
	/// Splits the array into consecutive pieces of at most `size` elements.
	func chunked(into size: Int) -> [[Element]] {
		guard size > 0 else { return [self] }
		return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
	}
	
}
