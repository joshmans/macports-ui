//
//  InstallPlan.swift
//  MacPortsKit
//
//  Choosing variants and previewing what an install would need.
//

import Foundation

/// The variants a user has switched on or off for one port, starting from the port's defaults.
public struct VariantSelection: Equatable, Sendable {
	
	public let variants: [PortVariant]
	public private(set) var enabled: Set<String>
	
	public init(variants: [PortVariant]) {
		self.variants = variants
		self.enabled = Set(variants.filter(\.isDefault).map(\.name))
	}
	
	public func isEnabled(_ name: String) -> Bool { enabled.contains(name) }
	
	/// Variants that conflict with the given one, in either direction.
	public func conflicts(of name: String) -> Set<String> {
		var result = Set(variants.first { $0.name == name }?.conflicts ?? [])
		for variant in variants where variant.conflicts.contains(name) { result.insert(variant.name) }
		result.remove(name)
		return result
	}
	
	/// Switches a variant. Turning one on turns off everything it conflicts with.
	public mutating func set(_ name: String, enabled isOn: Bool) {
		guard variants.contains(where: { $0.name == name }) else { return }
		if isOn {
			enabled.subtract(conflicts(of: name))
			enabled.insert(name)
		} else {
			enabled.remove(name)
		}
	}
	
	/// Whether the selection is the port's default.
	public var isDefault: Bool { enabled == Set(variants.filter(\.isDefault).map(\.name)) }
	
	/// The `+name` / `-name` arguments for `port install`, listing only what differs from the defaults.
	public var arguments: [String] {
		variants.compactMap { variant in
			let on = enabled.contains(variant.name)
			if on && !variant.isDefault { return "+\(variant.name)" }
			if !on && variant.isDefault { return "-\(variant.name)" }
			return nil
		}
	}
	
	/// The variants as they appear in archive file names: everything that is on, in alphabetical order.
	public var archiveSuffix: String {
		enabled.sorted().map { "+\($0)" }.joined()
	}
	
}

/// A port that would be installed along with the requested one.
public struct PlannedDependency: Identifiable, Hashable, Sendable {
	public var id: String { name }
	public let name: String
	public let version: String
	
	/// Whether an archive for this Mac matches the version in the local index. `nil` if the check failed.
	public let isPrebuilt: Bool?
}

public struct InstallPlan: Sendable {
	public let port: String
	
	/// Whether an archive exists for the chosen variants.
	public let prebuilt: PrebuiltStatus
	
	/// Dependencies that are not installed yet.
	public let missingDependencies: [PlannedDependency]
	
	/// How many dependencies are already installed.
	public let installedDependencies: Int
	
	/// Everything that would have to be compiled: the port itself and any dependency without an archive.
	public var wouldCompile: [String] {
		var names = [String]()
		if prebuilt != .unknown, !prebuilt.isAvailable { names.append(port) }
		names += missingDependencies.filter { $0.isPrebuilt == false }.map(\.name)
		return names
	}
	
	/// Whether `port install -b` is expected to succeed.
	public var canInstallPrebuilt: Bool {
		prebuilt.isAvailable && !missingDependencies.contains { $0.isPrebuilt == false }
	}
}

extension PrebuiltStatus {
	
	public var isAvailable: Bool {
		if case .available = self { return true }
		return false
	}
	
}

extension MacPortsParser {
	
	/// The unique port names in `port rdeps` output.
	static func parseDependencyTree(_ output: String) -> [String] {
		var seen = Set<String>()
		return output.split(separator: "\n").compactMap { line in
			guard line.hasPrefix(" ") else { return nil }
			let name = line.trimmingCharacters(in: .whitespaces)
			return isValidPortName(name) && seen.insert(name).inserted ? name : nil
		}
	}
	
	/// The library and runtime dependencies in `port deps` output, which applies the chosen variants.
	static func parseDirectDependencies(_ output: String) -> [String] {
		var names = [String]()
		for line in output.split(separator: "\n") {
			for prefix in ["Library Dependencies:", "Runtime Dependencies:"] where line.hasPrefix(prefix) {
				names += line.dropFirst(prefix.count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
			}
		}
		return names.filter(isValidPortName)
	}
	
	/// Parses `port info` output for several ports, blocks separated by `--`.
	static func parseInfoBlocks(_ output: String) -> [[String: String]] {
		output.components(separatedBy: "\n--\n").map { parseInfo($0) }.filter { $0["name"] != nil }
	}
	
}

extension PortsClient {
	
	/// Works out what installing a port with the given variants would need, without changing anything.
	///
	/// Build and test dependencies are left out, because an install from archives does not need them.
	public static func planInstall(of name: String, version: String, revision: String, selection: VariantSelection) async -> InstallPlan {
		await Task.detached(priority: .userInitiated) {
			let port = MacPortsPackageChecker.portPath
			let darwin = SystemInfo.darwinMajor
			let arch = SystemInfo.machine
			
			let own: PrebuiltStatus
			let urls = MacPortsParser.archiveURLs(name: name, version: "\(version)_\(revision)", variants: selection.archiveSuffix, darwin: darwin, arch: arch)
			if urls.contains(where: Network.exists) {
				own = .available(version: "\(version)_\(revision)\(selection.archiveSuffix)")
			} else if Network.exists(URL(string: "https://packages.macports.org/\(name)/")!) {
				own = .unavailable
			} else {
				own = .unknown
			}
			
			// `port rdeps` ignores variants, so ask `port deps` for the direct dependencies of the chosen variants and expand those.
			guard PortAction.isValidPortName(name), selection.arguments.allSatisfy(PortAction.isValidVariant) else {
				return InstallPlan(port: name, prebuilt: .unknown, missingDependencies: [], installedDependencies: 0)
			}
			let direct = MacPortsParser.parseDirectDependencies(CommandRunner.run(port, ["deps", name] + selection.arguments).output)
			var tree = direct
			if !direct.isEmpty {
				let nested = MacPortsParser.parseDependencyTree(CommandRunner.run(port, ["rdeps", "--index", "--no-build", "--no-test"] + direct).output)
				var seen = Set(direct)
				tree += nested.filter { seen.insert($0).inserted }
			}
			let installedNames = Set(MacPortsParser.parseInstalled(CommandRunner.run(port, ["installed"]).output).filter(\.isActive).map(\.name))
			let missing = tree.filter { !installedNames.contains($0) }
			
			var dependencies = [PlannedDependency]()
			if !missing.isEmpty {
				let info = MacPortsParser.parseInfoBlocks(CommandRunner.run(port, ["info", "--index", "--name", "--version", "--revision"] + missing).output)
				var versions = [String: (version: String, revision: String)]()
				for block in info { if let n = block["name"], let v = block["version"] { versions[n] = (v, block["revision"] ?? "0") } }
				
				let lock = NSLock()
				var found = [PlannedDependency?](repeating: nil, count: missing.count)
				DispatchQueue.concurrentPerform(iterations: missing.count) { index in
					let dependency = missing[index]
					let known = versions[dependency]
					var prebuilt: Bool?
					if let known, let url = URL(string: "https://packages.macports.org/\(dependency)/"), let html = Network.get(url) {
						prebuilt = MacPortsParser.newestArchiveVersion(inListing: html, port: dependency, darwin: darwin, arch: arch)
							.map { MacPortsParser.archiveMatchesIndex(archiveVersion: $0, indexVersion: known.version, indexRevision: known.revision) } ?? false
					}
					let planned = PlannedDependency(name: dependency, version: known.map { "\($0.version)_\($0.revision)" } ?? "?", isPrebuilt: prebuilt)
					lock.lock(); found[index] = planned; lock.unlock()
				}
				dependencies = found.compactMap { $0 }
			}
			
			return InstallPlan(port: name, prebuilt: own, missingDependencies: dependencies, installedDependencies: tree.count - missing.count)
		}.value
	}
	
	/// Installs a port with the given variant arguments. By default only prebuilt archives are used and the install fails instead of compiling.
	public static func install(_ name: String, variants: [String], buildFromSource: Bool = false, onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.install([name], variants: variants.joined(separator: " "), buildFromSource: buildFromSource, onOutput: onOutput)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
}
