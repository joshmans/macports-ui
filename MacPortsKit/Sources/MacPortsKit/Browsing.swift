//
//  Browsing.swift
//  MacPortsKit
//
//  The port catalog, port details and prebuilt availability for the Browse screen.
//

import Foundation

/// A port in the catalog.
public struct CatalogPort: Identifiable, Hashable, Sendable {
	public var id: String { name }
	public let name: String
	public let version: String
	public let categories: [String]
	public let summary: String
	
	public init(name: String, version: String, categories: [String], summary: String) {
		self.name = name
		self.version = version
		self.categories = categories
		self.summary = summary
	}
}

public struct PortVariant: Identifiable, Hashable, Sendable {
	public var id: String { name }
	public let name: String
	public let description: String
	
	/// Whether the variant is on unless you turn it off.
	public let isDefault: Bool
	
	public let conflicts: [String]
}

/// Whether a port can be installed from a prebuilt archive on this Mac.
public enum PrebuiltStatus: Hashable, Sendable {
	/// An archive for the version in the local index exists.
	case available(version: String)
	
	/// Archives exist, but not for the version in the local index. Refreshing the index may fix an install, or the build farm may not have caught up.
	case differentVersion(archive: String, index: String)
	
	/// No archive for this Mac. Installing would compile.
	case unavailable
	
	/// The check could not be made, for example because the network is down.
	case unknown
}

public struct PortDetail: Sendable {
	public let name: String
	public let version: String
	public let revision: String
	public let categories: [String]
	public let summary: String
	public let longDescription: String
	public let homepage: String?
	public let license: String?
	public let variants: [PortVariant]
	public let dependencies: [String]
	public let prebuilt: PrebuiltStatus
}

extension MacPortsParser {
	
	/// Parses `port variants NAME` output.
	static func parseVariants(_ output: String) -> [PortVariant] {
		var result = [PortVariant]()
		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			let text = String(line)
			if text.trimmingCharacters(in: .whitespaces).hasPrefix("* conflicts with") {
				guard let last = result.popLast() else { continue }
				let names = text.components(separatedBy: "conflicts with").last?.split(separator: " ").map(String.init) ?? []
				result.append(PortVariant(name: last.name, description: last.description, isDefault: last.isDefault, conflicts: names))
				continue
			}
			// Variant lines start with a three character marker: `[+]`, `[-]`, `(+)` or spaces.
			guard text.count > 3, let colon = text.firstIndex(of: ":"), !text.hasPrefix("Warning:"), !text.contains(" has the variants") else { continue }
			let marker = String(text.prefix(3))
			let name = text.dropFirst(3)[..<colon].trimmingCharacters(in: .whitespaces)
			guard !name.isEmpty, name.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { continue }
			let description = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			result.append(PortVariant(name: name, description: description, isDefault: marker.contains("+"), conflicts: []))
		}
		return result
	}
	
	/// Splits a comma separated `port info` value.
	static func parseList(_ value: String?) -> [String] {
		(value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
	}
	
	/// Ranks a catalog entry for a search term: 0 exact name, 1 name prefix, 2 name contains, 3 summary contains, nil no match.
	static func searchRank(_ port: CatalogPort, term: String) -> Int? {
		let name = port.name.lowercased()
		if name == term { return 0 }
		if name.hasPrefix(term) { return 1 }
		if name.contains(term) { return 2 }
		if port.summary.localizedCaseInsensitiveContains(term) { return 3 }
		return nil
	}
	
	/// How many ports each category has, most populated first.
	static func categoryCounts(_ ports: [CatalogPort]) -> [(name: String, count: Int)] {
		var counts = [String: Int]()
		for port in ports { for category in port.categories { counts[category, default: 0] += 1 } }
		return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
	}
	
}

public enum Catalog {
	
	/// Ports matching a search term, best matches first, optionally restricted to a category.
	public static func search(_ term: String, in ports: [CatalogPort], category: String? = nil, limit: Int = 500) -> [CatalogPort] {
		let term = term.trimmingCharacters(in: .whitespaces).lowercased()
		let pool = category.map { category in ports.filter { $0.categories.contains(category) } } ?? ports
		if term.isEmpty { return Array(pool.prefix(limit)) }
		let ranked = pool.compactMap { port in MacPortsParser.searchRank(port, term: term).map { (port, $0) } }
		return ranked.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }.prefix(limit).map(\.0)
	}
	
	/// How many ports each category has, most populated first.
	public static func categories(in ports: [CatalogPort]) -> [(name: String, count: Int)] {
		MacPortsParser.categoryCounts(ports)
	}
	
}

extension PortsClient {
	
	/// Loads the whole port catalog (about 40,000 ports, a few seconds), so searching can be instant.
	public static func fetchCatalog() async -> [CatalogPort] {
		await Task.detached(priority: .userInitiated) {
			guard isInstalled else { return [] }
			let output = CommandRunner.run(MacPortsPackageChecker.portPath, ["search", "--line", "--name", "--glob", "*"]).output
			return MacPortsParser.parseSearch(output).map { CatalogPort(name: $0.name, version: $0.version, categories: $0.categories, summary: $0.summary) }
		}.value
	}
	
	/// Details of one port, including whether a prebuilt archive exists for this Mac.
	public static func detail(of name: String) async -> PortDetail? {
		guard PortAction.isValidPortName(name) else { return nil }
		return await Task.detached(priority: .userInitiated) {
			let port = MacPortsPackageChecker.portPath
			let fields = ["--version", "--revision", "--category", "--description", "--long_description", "--homepage", "--license", "--depends_lib"]
			let info = MacPortsParser.parseInfo(CommandRunner.run(port, ["info", "--index"] + fields + [name]).output)
			guard let version = info["version"] else { return nil }
			let revision = info["revision"] ?? "0"
			let variants = MacPortsParser.parseVariants(CommandRunner.run(port, ["variants", name]).output)
			
			var status = PrebuiltStatus.unknown
			if let url = URL(string: "https://packages.macports.org/\(name)/"), let html = Network.get(url) {
				if let archive = MacPortsParser.newestArchiveVersion(inListing: html, port: name, darwin: SystemInfo.darwinMajor, arch: SystemInfo.machine) {
					status = MacPortsParser.archiveMatchesIndex(archiveVersion: archive, indexVersion: version, indexRevision: revision)
						? .available(version: archive) : .differentVersion(archive: archive, index: "\(version)_\(revision)")
				} else {
					status = .unavailable
				}
			} else if Network.exists(URL(string: "https://packages.macports.org/")!) {
				// The server answers but has no directory for this port: nothing was ever built.
				status = .unavailable
			}
			
			return PortDetail(name: name, version: version, revision: revision, categories: MacPortsParser.parseList(info["category"]),
							  summary: info["description"] ?? "", longDescription: info["long_description"] ?? "",
							  homepage: info["homepage"], license: info["license"], variants: variants,
							  dependencies: MacPortsParser.parseList(info["depends_lib"]), prebuilt: status)
		}.value
	}
	
	/// Installs a port from a prebuilt archive only. It fails instead of compiling.
	public static func install(_ name: String, onOutput: (@Sendable (String) -> Void)? = nil) async -> ActionResult {
		await Task.detached {
			let result = MacPortsPackageChecker.install([name], buildFromSource: false, onOutput: onOutput)
			return ActionResult(status: result.status, output: result.output)
		}.value
	}
	
}
