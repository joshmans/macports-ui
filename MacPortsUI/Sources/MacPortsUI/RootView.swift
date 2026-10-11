import SwiftUI
import MacPortsKit

struct RootView: View {
	
	enum Section: String, CaseIterable, Identifiable {
		case outdated = "Outdated"
		case installed = "Installed"
		case browse = "Browse"
		case migrate = "Migrate"
		case activity = "Activity"
		var id: String { rawValue }
		var symbol: String {
			switch self {
			case .outdated: return "arrow.down.circle"
			case .installed: return "shippingbox"
			case .browse: return "magnifyingglass"
			case .migrate: return "arrow.left.arrow.right"
			case .activity: return "list.bullet.rectangle"
			}
		}
	}
	
	@StateObject private var activity: ActivityModel
	@StateObject private var outdated: OutdatedModel
	@StateObject private var installed: InstalledModel
	@StateObject private var browse: BrowseModel
	@StateObject private var migrate: MigrateModel
	@State private var section: Section? = .outdated
	@State private var showingHelper = false
	
	init() {
		let activity = ActivityModel()
		_activity = StateObject(wrappedValue: activity)
		_outdated = StateObject(wrappedValue: OutdatedModel(activity: activity))
		_installed = StateObject(wrappedValue: InstalledModel(activity: activity))
		_browse = StateObject(wrappedValue: BrowseModel(activity: activity))
		_migrate = StateObject(wrappedValue: MigrateModel(activity: activity))
	}
	
	var body: some View {
		NavigationSplitView {
			List(Section.allCases, selection: $section) { section in
				row(for: section)
			}
			.navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
		} detail: {
			// The models live here, so switching sections keeps each screen's data.
			switch section ?? .outdated {
			case .outdated: OutdatedView(model: outdated)
			case .installed: InstalledView(model: installed)
			case .browse: BrowseView(model: browse)
			case .migrate: MigrateView(model: migrate)
			case .activity: ActivityView(activity: activity)
			}
		}
		.overlay(alignment: .bottom) { notice }
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
	}
	
	@ViewBuilder private func row(for section: Section) -> some View {
		let label = Label(section.rawValue, systemImage: section.symbol).tag(section)
		if section == .activity {
			if activity.activeCount > 0 {
				label.badge(activity.activeCount)
			} else if activity.unseenFailures > 0 {
				label.badge(Text("!"))
			} else {
				label
			}
		} else {
			label
		}
	}
	
	/// A short message when something was queued, with a way to see it.
	@ViewBuilder private var notice: some View {
		if let text = activity.notice, section != .activity {
			HStack(spacing: 10) {
				Image(systemName: "list.bullet.rectangle")
				Text(text).lineLimit(1)
				Button("Show") { section = .activity; activity.dismissNotice() }.buttonStyle(.link)
			}
			.padding(.horizontal, 14).padding(.vertical, 9)
			.background(.regularMaterial, in: Capsule())
			.shadow(radius: 4, y: 1)
			.padding(.bottom, 16)
			.transition(.move(edge: .bottom).combined(with: .opacity))
		}
	}
	
}
