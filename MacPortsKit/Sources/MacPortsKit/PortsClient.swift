//
//  PortsClient.swift
//  MacPortsKit
//
//  The public surface the app uses. Everything here is async and safe to call from the main actor.
//

import Foundation

/// An installed port with a newer version available.
public struct OutdatedPort: Identifiable, Hashable, Sendable {
	public var id: String { name }
	public let name: String
	public let installedVersion: String
	public let availableVersion: String
	
	/// The active variants, such as `+quartz+x11`.
	public let variants: String
	
	/// Whether a prebuilt archive for the new version exists for this Mac.
	public let isPrebuilt: Bool
	
	/// How the new version relates to the installed one. `.same` means only the revision changed.
	public var relation: PackageVersions.Relation {
		PackageVersions.relation(of: availableVersion, to: installedVersion)
	}
}

public struct OutdatedReport: Sendable {
	public let ports: [OutdatedPort]
	
	/// Whether MacPorts reports its port definitions as old, so the list may be incomplete or point to archives that no longer exist.
	public let indexIsStale: Bool
	
	/// When the local port index was last refreshed.
	public let indexDate: Date?
}

public struct ActionResult: Sendable {
	public let status: Int32
	public let output: String
	public var succeeded: Bool { status == 0 }
	
	public init(status: Int32, output: String) {
		self.status = status
		self.output = output
	}
}

/// The state of the optional privileged helper, which removes the administrator prompt.
public enum HelperState: Equatable, Sendable {
	case unavailable(reason: String)
	case notRegistered
	case requiresApproval
	case enabled
}

public enum PortsClient {
	
	// MARK: - Privileged helper
	
	public static var helperState: HelperState {
		switch PrivilegedHelper.status {
		case .unavailable(let reason): return .unavailable(reason: reason)
		case .notRegistered: return .notRegistered
		case .requiresApproval: return .requiresApproval
		case .enabled: return .enabled
		}
	}
	
	/// Whether the user has turned the helper on.
	public static var helperIsOptedIn: Bool { PrivilegedHelper.isOptedIn }
	
	/// Registers the helper. Afterwards `helperState` may be `.requiresApproval`.
	public static func enableHelper() throws { try PrivilegedHelper.enable() }
	
	public static func disableHelper() { PrivilegedHelper.disable() }
	
	public static func openLoginItemsSettings() { PrivilegedHelper.openSystemSettings() }
	
	
	// MARK: - Ports
	
	
	public static var isInstalled: Bool { MacPortsPackageChecker.isInstalled }
	
	/// The modification date of the local port index.
	public static var indexDate: Date? {
		let path = "/opt/local/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports/PortIndex"
		return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
	}
	
	/// Lists outdated ports and checks, in parallel, which of them have prebuilt archives.
	public static func fetchOutdated() async -> OutdatedReport {
		await Task.detached(priority: .userInitiated) { fetchOutdatedBlocking() }.value
	}
	
	/// Upgrades the given ports from prebuilt archives only, with one administrator prompt (or none with the helper). With the helper, `onOutput` receives the log while the command runs.
	public static func upgrade(_ names: [String], onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.upgrade(names, onOutput: onOutput)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
	/// Refreshes the port index.
	public static func selfUpdate(onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.selfUpdate(onOutput: onOutput)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
	
	// MARK: - Implementation
	
	static func fetchOutdatedBlocking() -> OutdatedReport {
		guard isInstalled else { return OutdatedReport(ports: [], indexIsStale: false, indexDate: nil) }
		
		let output = CommandRunner.run(MacPortsPackageChecker.portPath, ["outdated"]).output
		let entries = MacPortsParser.parseOutdated(output)
		let darwin = SystemInfo.darwinMajor
		let arch = SystemInfo.machine
		
		let lock = NSLock()
		var ports = [OutdatedPort?](repeating: nil, count: entries.count)
		DispatchQueue.concurrentPerform(iterations: entries.count) { index in
			let entry = entries[index]
			let installed = CommandRunner.run(MacPortsPackageChecker.portPath, ["installed", entry.name]).output
			let variants = MacPortsParser.activeVariants(in: installed, name: entry.name)
			let urls = MacPortsParser.archiveURLs(name: entry.name, version: entry.available, variants: variants, darwin: darwin, arch: arch)
			let port = OutdatedPort(name: entry.name, installedVersion: entry.installed, availableVersion: entry.available, variants: variants, isPrebuilt: urls.contains(where: Network.exists))
			lock.lock(); ports[index] = port; lock.unlock()
		}
		
		return OutdatedReport(ports: ports.compactMap { $0 }, indexIsStale: output.contains("more than two weeks old"), indexDate: indexDate)
	}
	
}


// MARK: - Installed ports

/// An installed port, with what the Installed screen needs to know about it.
public struct InstalledPort: Identifiable, Hashable, Sendable {
	public var id: String { name }
	public let name: String
	
	/// The active version, or the newest one if none is active.
	public let version: String
	
	/// The variants of that version, such as `+quartz+x11`.
	public let variants: String
	
	/// Whether the user asked for this port, as opposed to it being installed as a dependency.
	public let isRequested: Bool
	
	/// Whether no other installed port depends on it.
	public let isLeaf: Bool
	
	/// Whether any version of the port is active.
	public let isActive: Bool
	
	/// Older versions that are installed but not active.
	public let inactiveVersions: [String]
}

extension MacPortsParser {
	
	/// Groups `port installed` entries into one `InstalledPort` per name.
	static func installedPorts(all: [(name: String, version: String, isActive: Bool)], requested: Set<String>, leaves: Set<String>) -> [InstalledPort] {
		Dictionary(grouping: all, by: \.name).map { name, entries in
			let current = entries.first(where: \.isActive) ?? entries.last!
			let full = current.version
			let variants = full.firstIndex(of: "+").map { String(full[$0...]) } ?? ""
			return InstalledPort(name: name, version: String(full.prefix { $0 != "+" }), variants: variants,
								 isRequested: requested.contains(name), isLeaf: leaves.contains(name), isActive: current.isActive,
								 inactiveVersions: entries.filter { !$0.isActive && $0.version != full }.map(\.version))
		}.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}
	
	/// Parses `port dependents NAME` output (`foo depends on NAME`).
	static func parseDependents(_ output: String) -> [String] {
		output.split(separator: "\n").compactMap { line in
			guard !line.hasPrefix("Warning:"), let range = line.range(of: " depends on ") else { return nil }
			let name = String(line[..<range.lowerBound])
			return isValidPortName(name) ? name : nil
		}
	}
	
}

extension PortsClient {
	
	/// Lists installed ports.
	public static func fetchInstalled() async -> [InstalledPort] {
		await Task.detached(priority: .userInitiated) {
			guard isInstalled else { return [] }
			let port = MacPortsPackageChecker.portPath
			let all = MacPortsParser.parseInstalled(CommandRunner.run(port, ["installed"]).output)
			let requested = Set(MacPortsParser.parseInstalled(CommandRunner.run(port, ["installed", "requested"]).output).map(\.name))
			let leaves = Set(MacPortsParser.parseInstalled(CommandRunner.run(port, ["echo", "leaves"]).output).map(\.name))
			return MacPortsParser.installedPorts(all: all, requested: requested, leaves: leaves)
		}.value
	}
	
	/// The installed ports that depend on the given port.
	public static func dependents(of name: String) async -> [String] {
		guard PortAction.isValidPortName(name) else { return [] }
		return await Task.detached {
			MacPortsParser.parseDependents(CommandRunner.run(MacPortsPackageChecker.portPath, ["dependents", name]).output)
		}.value
	}
	
	/// Uninstalls a port. MacPorts refuses if other ports depend on it, and that is never overridden.
	public static func uninstall(_ name: String, onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.run(.uninstall(port: name), onOutput: onOutput)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
	/// Removes all inactive versions of all ports.
	public static func uninstallInactive(onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.run(.uninstallInactive, onOutput: onOutput)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
}
