import AppKit
import SwiftUI

struct DownloadsView: View {
    @ObservedObject var model: EmbeddedWorkspace
    @ObservedObject private var center: DownloadCenter
    @Environment(\.dismiss) private var dismiss
    init(model: EmbeddedWorkspace) { self.model = model; self.center = model.downloadCenter }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle").font(.title2.bold())
                Spacer()
                Button("Clear Finished") { center.clearFinished() }.disabled(!center.entries.contains { $0.state != .running })
            }.padding(20)
            if center.entries.isEmpty {
                ContentUnavailableView("No downloads this session", systemImage: "arrow.down.circle", description: Text("Saved media and website downloads appear here. Clearing history never deletes saved files."))
            } else {
                List(Array(center.entries.reversed())) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.destination.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if entry.state == .running {
                                Button("Cancel") { center.cancel(entry.id) }
                            } else if entry.state == .completed {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.destination]) }
                            } else if entry.canRetry {
                                Button("Retry…") { model.retryDownload(entry.id) }
                                    .disabled(entry.source == "YouTube" && (model.savingMedia || !model.allowsYouTubeDownloads))
                            }
                        }
                        Text("\(entry.account) · \(entry.source) · \(entry.started.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if entry.state == .running {
                            if let fraction = entry.progress { ProgressView(value: fraction) }
                            else { ProgressView().controlSize(.small) }
                        }
                        Text(entry.error ?? entry.detail).font(.caption)
                            .foregroundStyle(entry.state == .failed ? .red : .secondary)
                            .textSelection(.enabled)
                    }.padding(.vertical, 8)
                }.listStyle(.plain)
            }
            Divider()
            HStack {
                Text("History is kept for this session and cleared when MailPort locks.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 650, height: 480)
    }
}
