import SwiftUI

struct YouTubeResolutionView: View {
    @ObservedObject var model: EmbeddedWorkspace
    let url: URL
    @State private var heights: [Int] = []
    @State private var selectedHeight = 0
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Save YouTube video", systemImage: "arrow.down.circle").font(.title2.bold())
            if loading { ProgressView("Checking available resolutions…") }
            else if let error {
                Text(error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await load() } }
            } else {
                Picker("Resolution", selection: $selectedHeight) {
                    Text("Best available (\(heights.first ?? 0)p)").tag(0)
                    ForEach(heights, id: \.self) { height in Text("\(height)p").tag(height) }
                }
                Text("Saves MP4 with audio. Higher resolutions need more space and time. FFmpeg merges the streams without re-encoding.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.showingVideoOptions = false }.keyboardShortcut(.cancelAction)
                Button("Choose destination…") { model.chooseVideoResolution(selectedHeight == 0 ? nil : selectedHeight) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(loading || heights.isEmpty || error != nil)
            }
        }.padding(26).frame(width: 460)
        .task { await load() }
        .onDisappear { model.cancelVideoResolutionCheck() }
    }

    @MainActor private func load() async {
        loading = true; error = nil; heights = []
        defer { loading = false }
        do { heights = try await model.readVideoResolutions(url: url) }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
