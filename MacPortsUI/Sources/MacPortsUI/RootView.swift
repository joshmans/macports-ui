import SwiftUI
import MacPortsKit

struct RootView: View {
	
	enum Section: String, CaseIterable, Identifiable {
		case outdated = "Outdated"
		case installed = "Installed"
		case browse = "Browse"
		var id: String { rawValue }
		var symbol: String {
			switch self {
			case .outdated: return "arrow.down.circle"
			case .installed: return "shippingbox"
			case .browse: return "magnifyingglass"
			}
		}
	}
	
	@StateObject private var activity: ActivityModel
	@StateObject private var outdated: OutdatedModel
	@StateObject private var installed: InstalledModel
	@StateObject private var browse: BrowseModel
	@State private var section: Section? = .outdated
	@State private var showingHelper = false
	
	init() {
		let activity = ActivityModel()
		_activity = StateObject(wrappedValue: activity)
		_outdated = StateObject(wrappedValue: OutdatedModel(activity: activity))
		_installed = StateObject(wrappedValue: InstalledModel(activity: activity))
		_browse = StateObject(wrappedValue: BrowseModel(activity: activity))
	}
	
	var body: some View {
		NavigationSplitView {
			List(Section.allCases, selection: $section) { section in
				Label(section.rawValue, systemImage: section.symbol).tag(section)
			}
			.navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
		} detail: {
			// The models live here, so switching sections keeps each screen's data.
			switch section ?? .outdated {
			case .outdated: OutdatedView(model: outdated)
			case .installed: InstalledView(model: installed)
			case .browse: BrowseView(model: browse)
			}
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button { showingHelper = true } label: { Label("Helper", systemImage: "gearshape") }
					.help("Privileged helper: change ports without a password prompt")
			}
		}
		.onChange(of: section) { newValue in
			// Installing or uninstalling elsewhere changes what is installed.
			if newValue == .installed, installed.ports != nil { Task { await installed.refresh() } }
		}
		.sheet(isPresented: $showingHelper) {
			VStack(spacing: 0) {
				HelperSettingsView()
				HStack { Spacer(); Button("Done") { showingHelper = false }.keyboardShortcut(.defaultAction) }.padding([.horizontal, .bottom])
			}
		}
		.sheet(isPresented: Binding(get: { activity.log != nil }, set: { if !$0 { activity.log = nil } })) { ActivitySheet(activity: activity) }
	}
	
}

struct ActivitySheet: View {
	
	@ObservedObject var activity: ActivityModel
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if activity.isLive {
				HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Working…").font(.headline) }
			} else {
				Label(activity.failed ? "Something went wrong" : "Done", systemImage: activity.failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
					.font(.headline).foregroundStyle(activity.failed ? .red : .green)
			}
			ScrollViewReader { proxy in
				ScrollView {
					VStack(alignment: .leading, spacing: 0) {
						Text(activity.log ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
						Color.clear.frame(height: 1).id("end")
					}
				}
				.onChange(of: activity.log) { _ in proxy.scrollTo("end") }
			}
			.padding(8).background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 6))
			HStack { Spacer(); Button("Close") { activity.log = nil }.keyboardShortcut(.defaultAction).disabled(activity.isLive) }
		}
		.padding()
		.frame(width: 620, height: 400)
		.interactiveDismissDisabled(activity.isLive)
	}
	
}
