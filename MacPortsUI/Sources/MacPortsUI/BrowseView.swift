import SwiftUI
import MacPortsKit

struct BrowseView: View {
	
	@ObservedObject var model: BrowseModel
	
	var body: some View {
		Group {
			if !model.portInstalled {
				ContentUnavailableMessage(title: "MacPorts is not installed", detail: "Expected at /opt/local/bin/port.", symbol: "shippingbox")
			} else if model.catalog == nil {
				VStack(spacing: 12) {
					ProgressView()
					Text("Loading the port catalog…").foregroundStyle(.secondary)
				}.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				HSplitView {
					list.frame(minWidth: 320)
					detailPane.frame(minWidth: 280, idealWidth: 360)
				}
			}
		}
		.searchable(text: $model.search, prompt: "Search \(model.catalog.map { "\($0.count.formatted()) " } ?? "")ports")
		.toolbar {
			ToolbarItem {
				Menu {
					Button("All Categories") { model.category = nil }
					Divider()
					ForEach(model.categories, id: \.name) { category in
						Button("\(category.name) (\(category.count.formatted()))") { model.category = category.name }
					}
				} label: {
					Label(model.category ?? "Category", systemImage: "line.3.horizontal.decrease.circle")
				}
				.disabled(model.catalog == nil)
			}
		}
		.task { await model.loadIfNeeded() }
	}
	
	// MARK: Results
	
	@ViewBuilder private var list: some View {
		VStack(spacing: 0) {
			if !model.hasQuery {
				ContentUnavailableMessage(title: "Search the ports tree", detail: "Type a name or a word from the description, or pick a category.", symbol: "magnifyingglass")
			} else if model.results.isEmpty {
				ContentUnavailableMessage(title: "No ports found", detail: nil, symbol: "questionmark.circle")
			} else {
				Table(model.results, selection: $model.selection) {
					TableColumn("Port") { port in
						HStack(spacing: 6) {
							Text(port.name).fontWeight(.medium)
							if model.installedVersions[port.name] != nil {
								Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
							}
						}
					}
					.width(min: 120, ideal: 160)
					TableColumn("Version") { Text($0.version).monospacedDigit() }.width(min: 60, ideal: 90)
					TableColumn("Description") { Text($0.summary).foregroundStyle(.secondary).lineLimit(1) }
				}
				Divider()
				HStack {
					Text(model.results.count >= BrowseModel.limit ? "Showing the first \(BrowseModel.limit). Narrow the search to see more." : "\(model.results.count) ports")
						.foregroundStyle(.secondary)
					Spacer()
				}
				.padding(8)
			}
		}
	}
	
	// MARK: Detail
	
	@ViewBuilder private var detailPane: some View {
		if model.selection == nil {
			ContentUnavailableMessage(title: "Select a port", detail: nil, symbol: "shippingbox")
		} else if model.detailIsLoading {
			VStack(spacing: 12) {
				ProgressView()
				Text("Checking prebuilt availability…").foregroundStyle(.secondary)
			}.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if let detail = model.detail {
			PortDetailView(detail: detail, installedVersion: model.installedVersions[detail.name], isInstalling: model.isInstalling) { name in
				Task { await model.install(name) }
			}
			.id(detail.name)
		} else {
			ContentUnavailableMessage(title: "No details available", detail: "The port could not be read from the local index.", symbol: "exclamationmark.triangle")
		}
	}
	
}

struct PortDetailView: View {
	
	let detail: PortDetail
	let installedVersion: String?
	let isInstalling: Bool
	let install: (String) -> Void
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				VStack(alignment: .leading, spacing: 2) {
					Text(detail.name).font(.title2.bold())
					Text("\(detail.version)_\(detail.revision)").foregroundStyle(.secondary).monospacedDigit()
				}
				Text(detail.summary).font(.headline)
				
				prebuiltRow
				
				if let installedVersion {
					Label("Installed: \(installedVersion)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
				} else {
					Button { install(detail.name) } label: { Label("Install Prebuilt", systemImage: "arrow.down.circle") }
						.buttonStyle(.borderedProminent)
						.disabled(isInstalling || !canInstall)
						.help(canInstall ? "Installs from prebuilt archives only. It fails instead of compiling." : "No prebuilt archive for this Mac, so installing would compile.")
				}
				
				if !detail.longDescription.isEmpty {
					Text(detail.longDescription).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
				}
				
				Divider()
				facts
				
				if !detail.variants.isEmpty {
					Divider()
					Text("Variants").font(.headline)
					ForEach(detail.variants) { variant in
						VStack(alignment: .leading, spacing: 1) {
							HStack(spacing: 6) {
								Text(variant.name).fontWeight(.medium)
								if variant.isDefault { Text("default").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule()) }
							}
							Text(variant.description).font(.callout).foregroundStyle(.secondary)
							if !variant.conflicts.isEmpty {
								Text("Conflicts with \(variant.conflicts.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
							}
						}
					}
				}
				
				if !detail.dependencies.isEmpty {
					Divider()
					Text("Library dependencies").font(.headline)
					Text(detail.dependencies.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding()
		}
	}
	
	private var canInstall: Bool {
		if case .available = detail.prebuilt { return true }
		return false
	}
	
	@ViewBuilder private var prebuiltRow: some View {
		switch detail.prebuilt {
		case .available(let version):
			Label("Prebuilt for this Mac (\(version))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
		case .differentVersion(let archive, let index):
			VStack(alignment: .leading, spacing: 2) {
				Label("Prebuilt archive is a different version", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
				Text("Server has \(archive); your index wants \(index). Refresh the index on the Outdated screen, then look again.").font(.callout).foregroundStyle(.secondary)
			}
		case .unavailable:
			Label("No prebuilt archive for this Mac. Installing would compile.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
		case .unknown:
			Label("Could not check prebuilt availability.", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
		}
	}
	
	private var facts: some View {
		Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
			if !detail.categories.isEmpty { fact("Categories", detail.categories.joined(separator: ", ")) }
			if let license = detail.license { fact("License", license) }
			if let homepage = detail.homepage, let url = URL(string: homepage), url.scheme?.hasPrefix("http") == true {
				GridRow {
					Text("Homepage").foregroundStyle(.secondary)
					Link(homepage, destination: url).lineLimit(1)
				}
			}
		}
	}
	
	private func fact(_ title: String, _ value: String) -> some View {
		GridRow {
			Text(title).foregroundStyle(.secondary)
			Text(value).textSelection(.enabled)
		}
	}
	
}
