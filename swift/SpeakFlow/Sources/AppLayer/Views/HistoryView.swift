import Domain
import SwiftUI

struct HistoryView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var selectedID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            searchBar
            statsBar
            historyList
        }
        .padding(28)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.largeTitle.bold())
                Text("Search and manage past dictations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(runtime.historyStats.totalCount) total")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcripts…", text: Binding(
                    get: { runtime.historyQuery },
                    set: { runtime.updateHistoryQuery($0) }
                ))
                .textFieldStyle(.plain)
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            Button { runtime.reloadHistory() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)

            Button {
                guard let selected = selectedRecord else { return }
                runtime.copyHistory(selected)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.glass)
            .disabled(selectedRecord == nil)

            Button(role: .destructive) {
                guard let selected = selectedRecord else { return }
                runtime.deleteHistory(selected)
                selectedID = nil
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .disabled(selectedRecord == nil)
        }
    }

    private var statsBar: some View {
        HStack(spacing: 18) {
            Label(runtime.historyStats.latestSourceApp, systemImage: "app.badge")
            Label(runtime.historyStats.topSourceApp, systemImage: "star.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if runtime.history.isEmpty {
                    emptyState
                } else {
                    ForEach(runtime.history) { row in
                        HistoryRow(
                            row: row,
                            selected: selectedID == row.id,
                            onSelect: { selectedID = row.id },
                            onCopy: { runtime.copyHistory(row) },
                            onDelete: {
                                runtime.deleteHistory(row)
                                if selectedID == row.id { selectedID = nil }
                            }
                        )
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.slash")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No dictations yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Hold Fn and speak to get started.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var selectedRecord: HistoryRecord? {
        runtime.history.first(where: { $0.id == selectedID })
    }
}

private struct HistoryRow: View {
    let row: HistoryRecord
    let selected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTimestamp(row.createdAt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.sourceApp ?? "Unknown")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 130, alignment: .leading)

                Text(row.finalText)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .glassEffect(
                selected ? .regular.tint(.accentColor.opacity(0.3)) : .regular,
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func displayTimestamp(_ raw: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parserFallback = ISO8601DateFormatter()
        if let date = parser.date(from: raw) ?? parserFallback.date(from: raw) {
            let f = DateFormatter()
            f.locale = .current
            f.timeZone = .current
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: date)
        }
        return raw
    }
}
