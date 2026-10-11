import SwiftUI
import MacPortsKit

struct InstallSheet: View {
	
	@ObservedObject var flow: InstallFlowModel
	let cancel: () -> Void
	let install: (_ buildFromSource: Bool) -> Void
	
	@State private var confirmingSource = false
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					VStack(alignment: .leading, spacing: 2) {
						Text("Install \(flow.detail.name)").font(.title2.bold())
						Text("\(flow.detail.version)_\(flow.detail.revision)").foregroundStyle(.secondary).monospacedDigit()
					}
					if !flow.detail.variants.isEmpty { variants }
					planSection
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(20)
			}
			Divider()
			footer
		}
		.frame(width: 540, height: 560)
		.task { flow.refreshPlan() }
		.confirmationDialog("Compile from source?", isPresented: $confirmingSource) {
			Button("Build from Source") { install(true) }
			Button("Cancel", role: .cancel) {}
		} message: {
			let names = flow.plan?.wouldCompile ?? []
			Text("This compiles \(names.prefix(6).joined(separator: ", "))\(names.count > 6 ? " and \(names.count - 6) more" : ""). It can take a long time, and MacPorts runs the build scripts as administrator.")
		}
	}
	
	// MARK: Variants
	
	private var variants: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Variants").font(.headline)
				Spacer()
				Button("Reset to Defaults") { flow.resetVariants() }.disabled(flow.selection.isDefault).buttonStyle(.link)
			}
			ForEach(flow.detail.variants) { variant in
				Toggle(isOn: Binding(get: { flow.selection.isEnabled(variant.name) }, set: { flow.setVariant(variant.name, enabled: $0) })) {
					VStack(alignment: .leading, spacing: 1) {
						HStack(spacing: 6) {
							Text(variant.name).fontWeight(.medium)
							if variant.isDefault { Text("default").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule()) }
						}
						Text(variant.description).font(.callout).foregroundStyle(.secondary)
						let others = flow.selection.conflicts(of: variant.name)
						if !others.isEmpty {
							Text("Conflicts with \(others.sorted().joined(separator: ", ")); turning this on turns those off.").font(.caption).foregroundStyle(.orange)
						}
					}
				}
				.toggleStyle(.checkbox)
			}
		}
	}
	
	// MARK: Plan
	
	@ViewBuilder private var planSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("What this needs").font(.headline)
			if flow.isPlanning || flow.plan == nil {
				HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking archives and dependencies…").foregroundStyle(.secondary) }
			} else if let plan = flow.plan {
				portRow(plan)
				if plan.installedDependencies > 0 {
					Label("\(plan.installedDependencies) dependencies already installed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
				}
				if plan.missingDependencies.isEmpty {
					Label("No additional ports to install", systemImage: "checkmark.circle").foregroundStyle(.secondary)
				} else {
					Text("\(plan.missingDependencies.count) more port\(plan.missingDependencies.count == 1 ? "" : "s") will be installed:").foregroundStyle(.secondary)
					VStack(alignment: .leading, spacing: 2) {
						ForEach(plan.missingDependencies) { dependency in
							HStack {
								Text(dependency.name)
								Text(dependency.version).foregroundStyle(.secondary).monospacedDigit()
								Spacer()
								switch dependency.isPrebuilt {
								case true?: Label("Prebuilt", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
								case false?: Label("Would compile", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
								case nil: Label("Unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
								}
							}
							.font(.callout)
						}
					}
					.padding(8).background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 6))
				}
			}
		}
	}
	
	@ViewBuilder private func portRow(_ plan: InstallPlan) -> some View {
		switch plan.prebuilt {
		case .available(let version):
			Label("Prebuilt archive for these variants (\(version))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
		case .unavailable:
			Label("No prebuilt archive for these variants. Installing would compile \(plan.port).", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
		case .differentVersion, .unknown:
			Label("Could not check the prebuilt archive.", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
		}
	}
	
	// MARK: Footer
	
	private var footer: some View {
		HStack {
			if let plan = flow.plan, !flow.isPlanning, !plan.canInstallPrebuilt {
				Text("Prebuilt install is not possible with these choices.").font(.callout).foregroundStyle(.orange)
			}
			Spacer()
			Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
			if let plan = flow.plan, !flow.isPlanning, !plan.canInstallPrebuilt, !plan.wouldCompile.isEmpty {
				Button("Build from Source…") { confirmingSource = true }
			}
			Button("Install Prebuilt") { install(false) }
				.buttonStyle(.borderedProminent)
				.keyboardShortcut(.defaultAction)
				.disabled(flow.isPlanning || !(flow.plan?.canInstallPrebuilt ?? false))
		}
		.padding(14)
	}
	
}
