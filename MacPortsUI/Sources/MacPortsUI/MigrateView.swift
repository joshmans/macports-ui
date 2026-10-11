import SwiftUI
import MacPortsKit

struct MigrateView: View {
	
	@ObservedObject var model: MigrateModel
	
	var body: some View {
		VStack(spacing: 0) {
			if !model.brewInstalled {
				ContentUnavailableMessage(title: "Homebrew is not installed", detail: "There is nothing to move over.", symbol: "shippingbox")
			} else if !model.portInstalled {
				ContentUnavailableMessage(title: "MacPorts is not installed", detail: "Expected at /opt/local/bin/port.", symbol: "shippingbox")
			} else {
				header
				Divider()
				content
				Divider()
				footer
			}
		}
		.toolbar {
			ToolbarItem {
				Button { Task { await model.refresh() } } label: { Label("Check Again", systemImage: "arrow.clockwise") }
					.disabled(model.isLoading || !model.brewInstalled)
			}
		}
		.task { await model.loadIfNeeded() }
		.sheet(item: $model.sheet) { sheet in
			SwitchSheet(sheet: sheet, cancel: { model.cancelSwitch() }, confirm: { model.confirmSwitch($0) })
		}
	}
	
	// MARK: Pieces
	
	private var header: some View {
		HStack {
			Text("Move outdated formulae to prebuilt MacPorts ports. Dependents move with them.")
				.font(.callout).foregroundStyle(.secondary)
			Spacer()
			Toggle("Only with an equivalent", isOn: $model.onlySwitchable).toggleStyle(.checkbox)
		}
		.padding(10)
	}
	
	@ViewBuilder private var content: some View {
		if model.formulae == nil {
			VStack(spacing: 12) {
				ProgressView()
				Text("Checking Homebrew and looking up MacPorts equivalents…").foregroundStyle(.secondary)
			}.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if model.visible.isEmpty {
			ContentUnavailableMessage(title: (model.formulae ?? []).isEmpty ? "Everything in Homebrew is up to date" : "Nothing to move over",
									  detail: (model.formulae ?? []).isEmpty ? nil : "None of the outdated formulae has a prebuilt MacPorts equivalent.", symbol: "checkmark.circle")
		} else {
			Table(model.visible, selection: $model.selection) {
				TableColumn("Formula") { formula in
					Text(formula.name).fontWeight(.medium)
				}
				.width(min: 120, ideal: 170)
				TableColumn("Installed") { Text($0.installedVersion).monospacedDigit() }.width(min: 70, ideal: 100)
				TableColumn("Homebrew") { formula in
					if formula.hasBottle {
						Label("Bottle", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
					} else {
						Label("Would compile", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
							.help(formula.reason ?? "")
					}
				}
				.width(min: 110, ideal: 130)
				TableColumn("MacPorts") { formula in
					if model.isPending(formula) {
						Label("Queued", systemImage: "clock").foregroundStyle(.secondary)
					} else if let alternative = formula.alternative {
						HStack(spacing: 6) {
							Text(PackageVersions.base(alternative.version)).monospacedDigit()
							relationBadge(formula.alternativeRelation)
						}
						.help("Port \(alternative.name)")
					} else {
						Text("No equivalent").foregroundStyle(.secondary)
					}
				}
				.width(min: 150, ideal: 180)
			}
		}
	}
	
	@ViewBuilder private func relationBadge(_ relation: PackageVersions.Relation?) -> some View {
		switch relation {
		case .older?: Text("older").font(.caption2).padding(.horizontal, 5).background(.orange.opacity(0.25), in: Capsule()).help("Older than the version you have now")
		case .newer?: Text("newer").font(.caption2).padding(.horizontal, 5).background(.green.opacity(0.25), in: Capsule())
		case .same?: Text("same").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule())
		case nil: EmptyView()
		}
	}
	
	private var footer: some View {
		HStack {
			if model.isLoading { ProgressView().controlSize(.small) }
			Text("\((model.formulae ?? []).count) outdated · \(model.switchableCount) with a MacPorts equivalent").foregroundStyle(.secondary)
			Spacer()
			Button("Switch to MacPorts…") { model.beginSwitch() }
				.buttonStyle(.borderedProminent)
				.disabled(model.selectedSwitchable.isEmpty)
		}
		.padding(10)
	}
	
}

struct SwitchSheet: View {
	
	let sheet: MigrateModel.Sheet
	let cancel: () -> Void
	let confirm: (SwitchPreview) -> Void
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			switch sheet {
			case .working:
				VStack(spacing: 12) {
					ProgressView()
					Text("Working out what depends on your selection and looking up MacPorts equivalents…").foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				Divider()
				HStack { Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction) }.padding(14)
			case .review(let preview):
				review(preview)
			}
		}
		.frame(width: 580, height: 440)
	}
	
	private func review(_ preview: SwitchPreview) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					Text(preview.canSwitch ? "Switch \(preview.formulaCount) package\(preview.formulaCount == 1 ? "" : "s") to MacPorts?" : "Nothing can be switched")
						.font(.title3.bold())
					if preview.canSwitch {
						Text("Every MacPorts port is installed first, from prebuilt archives only. A Homebrew formula is uninstalled only after all ports of its group are confirmed installed, dependents first. Homebrew never removes anything else, and nothing is forced.")
							.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
						Text("MacPorts versions can be older than Homebrew's, and /opt/local/bin should come before /usr/local/bin on your PATH.")
							.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
					}
					if !preview.outdatedIndex.isEmpty {
						Label("Your MacPorts index is out of date for \(preview.outdatedIndex.count) port\(preview.outdatedIndex.count == 1 ? "" : "s"), so their archives would not be found. It is refreshed first.", systemImage: "clock.badge.exclamationmark")
							.foregroundStyle(.orange).font(.callout)
					}
					ForEach(Array(preview.groups.enumerated()), id: \.offset) { _, group in
						VStack(alignment: .leading, spacing: 3) {
							ForEach(group) { entry in
								HStack(spacing: 6) {
									Text("\(entry.formula) → port \(entry.port)").fontWeight(entry.isPulledIn ? .regular : .medium)
									if let version = entry.portVersion { Text(version).foregroundStyle(.secondary).monospacedDigit() }
									if entry.isOlder { Text("older than your \(entry.installedVersion ?? "")").font(.caption).foregroundStyle(.orange) }
									if entry.isPulledIn { Text("depends on your selection").font(.caption).foregroundStyle(.secondary) }
								}
								.font(.callout)
							}
						}
						.padding(8).frame(maxWidth: .infinity, alignment: .leading)
						.background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 6))
					}
					if !preview.blocked.isEmpty {
						Text("Staying in Homebrew").font(.headline)
						ForEach(preview.blocked) { item in
							Text("• \(item.package): \(item.reason)").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(20)
			}
			Divider()
			HStack {
				Spacer()
				Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
				Button("Switch") { confirm(preview) }
					.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
					.disabled(!preview.canSwitch)
			}
			.padding(14)
		}
	}
	
}
