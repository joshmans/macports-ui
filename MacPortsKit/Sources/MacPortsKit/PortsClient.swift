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
}

public enum PortsClient {
	
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
	
	/// Upgrades the given ports from prebuilt archives only, with one administrator prompt (or none with the helper).
	public static func upgrade(_ names: [String]) async -> ActionResult {
		await Task.detached { 
			let result = MacPortsPackageChecker.upgrade(names)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
	/// Refreshes the port index.
	public static func selfUpdate() async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.selfUpdate()
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

