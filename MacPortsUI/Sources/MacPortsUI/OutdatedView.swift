import SwiftUI
import MacPortsKit

struct OutdatedView: View {
	
	@ObservedObject var model: OutdatedModel
	
	var body: some View {
		VStack(spacing: 0) {
			if !model.portInstalled {
				ContentUnavailableMessage(title: "MacPorts is not installed", detail: "Expected at /opt/local/bin/port.", symbol: "shippingbox")
			} else {
				if model.report?.indexIsStale == true { staleBanner }
				content
				Divider()
				footer
			}
		}
		.toolbar { toolbar }
		.task { await model.refresh() }
	}
	
	// MARK: Pieces
	
	@ViewBuilder private var content: some View {
		if model.report == nil {
			VStack(spacing: 12) {
				ProgressView()
				Text("Checking for updates and prebuilt archives…").foregroundStyle(.secondary)
			}.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if model.ports.isEmpty {
			ContentUnavailableMessage(title: "Everything is up to date", detail: nil, symbol: "checkmark.circle")
		} else {
			Table(model.ports, selection: $model.selection) {
				TableColumn("Port") { Text($0.name).fontWeight(.medium) }
				TableColumn("Installed") { Text($0.installedVersion).monospacedDigit() }
				TableColumn("Available") { port in
					HStack(spacing: 4) {
						Text(port.availableVersion).monospacedDigit()
						if port.relation == .same { Text("(revision)").foregroundStyle(.secondary) }
					}
				}
				TableColumn("Archive") { port in
					if port.isPrebuilt {
						Label("Prebuilt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
					} else {
						Label("Would compile", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
							.help("No prebuilt archive for this Mac yet. If the port index is old, refresh it first.")
					}
				}
				.width(min: 120, ideal: 140)
			}
		}
	}
	
	private var staleBanner: some View {
		HStack {
			Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
			Text("The port index is more than two weeks old. Versions and archive availability may be wrong.")
			Spacer()
			Button("Refresh Index") { Task { await model.refreshIndex() } }.disabled(model.isBusy)
		}
		.padding(10)
		.background(.orange.opacity(0.12))
	}
	
	private var footer: some View {
		HStack {
			switch model.phase {
			case .checking: ProgressView().controlSize(.small); Text("Checking…")
			case .working(let text): ProgressView().controlSize(.small); Text(text)
			case .idle:
				if let report = model.report {
					Text("\(report.ports.count) outdated · \(model.prebuilt.count) prebuilt")
					if let date = report.indexDate {
						Text("· index \(date.formatted(.relative(presentation: .named)))")
					}
				}
			}
			Spacer()
			Button("Upgrade Selected") { Task { await model.upgrade(model.selectedPrebuilt) } }
				.disabled(model.isBusy || model.selectedPrebuilt.isEmpty)
			Button("Upgrade All Prebuilt") { Task { await model.upgrade(model.prebuilt) } }
				.buttonStyle(.borderedProminent)
				.disabled(model.isBusy || model.prebuilt.isEmpty)
		}
		.foregroundStyle(.secondary)
		.padding(10)
	}
	
	@ToolbarContentBuilder private var toolbar: some ToolbarContent {
		ToolbarItem {
			Button { Task { await model.refresh() } } label: { Label("Check Again", systemImage: "arrow.clockwise") }
				.disabled(model.isBusy || !model.portInstalled)
		}
		ToolbarItem {
			Button { Task { await model.refreshIndex() } } label: { Label("Refresh Index", systemImage: "arrow.triangle.2.circlepath") }
				.help("Run port selfupdate")
				.disabled(model.isBusy || !model.portInstalled)
		}
	}
	
}

struct ContentUnavailableMessage: View {
	let title: String
	let detail: String?
	let symbol: String
	
	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary)
			Text(title).font(.title3)
			if let detail { Text(detail).foregroundStyle(.secondary) }
		}.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
