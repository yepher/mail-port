import SwiftUI
import MailPortCore

struct QuickSwitcherView: View {
    @ObservedObject var model: EmbeddedWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focus: Bool
    private var results: [QuickSwitchItem] { model.quickSwitchItems(matching: query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Go to an account, service, or pin", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($focus)
                    .onSubmit { choose(highlighted) }
            }.padding(14)
            Divider()
            if results.isEmpty {
                Text("No matches").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, index: index).id(index)
                            }
                        }.padding(6)
                    }.onChange(of: highlighted) { _, value in proxy.scrollTo(value) }
                }
            }
        }
        .frame(width: 460, height: 340)
        .background {
            // Unmodified arrow shortcuts reach these before the text field handles them.
            Group {
                Button("Previous") { move(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("Next") { move(1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.opacity(0).accessibilityHidden(true)
        }
        .onAppear { focus = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private func row(_ item: QuickSwitchItem, index: Int) -> some View {
        let color = model.accounts.first { $0.id == item.accountID }.map { Color(nsColor: $0.nsColor) } ?? .secondary
        return Button { choose(index) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).foregroundStyle(color).frame(width: 20)
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
            .background(index == highlighted ? color.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlighted = (highlighted + delta + results.count) % results.count
    }

    private func choose(_ index: Int) {
        let items = results
        guard items.indices.contains(index) else { return }
        dismiss()
        model.go(to: items[index])
    }
}
