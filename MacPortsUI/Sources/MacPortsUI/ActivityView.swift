import SwiftUI

struct ActivityView: View {
	
	@ObservedObject var activity: ActivityModel
	
	var body: some View {
		Group {
			if activity.jobs.isEmpty {
				ContentUnavailableMessage(title: "Nothing queued", detail: "Installs, upgrades and removals you start show up here with their logs.", symbol: "list.bullet.rectangle")
			} else {
				HSplitView {
					List(activity.jobs.reversed(), selection: $activity.selectedJobID) { job in
						ActivityRow(job: job)
					}
					.frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
					
					if let job = activity.jobs.first(where: { $0.id == activity.selectedJobID }) {
						ActivityDetail(job: job, activity: activity).frame(minWidth: 320)
					} else {
						ContentUnavailableMessage(title: "Select an item", detail: nil, symbol: "text.alignleft")
					}
				}
			}
		}
		.toolbar {
			ToolbarItem {
				Button { activity.clearFinished() } label: { Label("Clear Finished", systemImage: "trash") }
					.help("Remove finished items from the list")
					.disabled(!activity.jobs.contains { !$0.status.isActive })
			}
		}
		.onAppear { activity.markFailuresSeen() }
	}
	
}

struct ActivityRow: View {
	
	@ObservedObject var job: ActivityJob
	
	var body: some View {
		HStack(spacing: 8) {
			StatusIcon(status: job.status)
			VStack(alignment: .leading, spacing: 2) {
				Text(job.title).lineLimit(2)
				Text(subtitle).font(.caption).foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 2)
		.tag(job.id)
	}
	
	private var subtitle: String {
		switch job.status {
		case .queued: return "Waiting"
		case .running: return "Running"
		case .cancelled: return "Cancelled"
		case .succeeded, .failed:
			let when = (job.finishedAt ?? job.createdAt).formatted(date: .omitted, time: .shortened)
			return "\(job.status == .failed ? "Failed" : "Done") at \(when) · \(durationText(job.duration))"
		}
	}
	
}

struct StatusIcon: View {
	
	let status: ActivityJob.Status
	
	var body: some View {
		Group {
			switch status {
			case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
			case .running: ProgressView().controlSize(.small)
			case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
			case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
			case .cancelled: Image(systemName: "minus.circle").foregroundStyle(.secondary)
			}
		}
		.frame(width: 18)
	}
	
}

struct ActivityDetail: View {
	
	@ObservedObject var job: ActivityJob
	let activity: ActivityModel
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				StatusIcon(status: job.status)
				Text(job.title).font(.headline)
				Spacer()
				if job.status == .queued {
					Button("Cancel") { activity.cancel(job) }
				}
			}
			if job.status == .running {
				Text("Running. A command that has started can't be stopped safely, so wait for it to finish.").font(.caption).foregroundStyle(.secondary)
			}
			if job.status == .queued {
				Text("Waiting for the items before it. MacPorts runs one change at a time.").font(.caption).foregroundStyle(.secondary)
			}
			ScrollViewReader { proxy in
				ScrollView {
					VStack(alignment: .leading, spacing: 0) {
						Text(job.log.isEmpty ? " " : job.log)
							.font(.system(.caption, design: .monospaced))
							.textSelection(.enabled)
							.frame(maxWidth: .infinity, alignment: .leading)
						Color.clear.frame(height: 1).id("end")
					}
				}
				.onChange(of: job.log) { _ in proxy.scrollTo("end") }
			}
			.padding(8)
			.background(.quaternary.opacity(0.4))
			.clipShape(RoundedRectangle(cornerRadius: 6))
		}
		.padding()
	}
	
}

func durationText(_ interval: TimeInterval?) -> String {
	guard let interval else { return "" }
	let seconds = Int(interval.rounded())
	return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
}
