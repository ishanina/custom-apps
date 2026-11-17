import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: DataStore
    @State private var pendingDelete: Routine?

    var body: some View {
        List(selection: $store.selectedRoutineID) {
            Section {
                ForEach(store.routines) { routine in
                    RoutineRow(routine: routine)
                        .tag(routine.id)
                        .contextMenu {
                            Button("Start") { store.play(routine.id) }
                                .disabled(routine.steps.isEmpty)
                            Divider()
                            Button("Duplicate") { store.duplicate(routine) }
                            Button("Export…") { store.export(routine) }
                            Divider()
                            Button("Delete…", role: .destructive) { pendingDelete = routine }
                        }
                }
                .onMove { store.routines.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Routines")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button { store.newRoutine() } label: {
                    Label("New Routine", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                Spacer()
                Button { store.importRoutines() } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help("Import routines from JSON")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { routine in
            Button("Delete Routine", role: .destructive) { store.delete(id: routine.id) }
        } message: { _ in
            Text("This can't be undone. Export it first if you might want it back.")
        }
    }
}

private struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(routine.name.isEmpty ? "Untitled" : routine.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if routine.backgroundAudio != .none {
                    Image(systemName: routine.backgroundAudio.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .help("Plays \(routine.backgroundAudio == .podcast ? "a podcast" : "a Spotify playlist")")
                }
            }
            HStack(spacing: 4) {
                Text("\(routine.steps.count) step\(routine.steps.count == 1 ? "" : "s")")
                if !routine.steps.isEmpty {
                    Text("·")
                    Text(routine.durationSummary)
                }
                Spacer(minLength: 4)
                if let done = routine.lastCompletedAt {
                    Label {
                        Text(done, format: .relative(presentation: .named))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent.opacity(0.8))
                    }
                    .labelStyle(CompactLabelStyle())
                    .help("Last completed \(done.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            CompositionBar(steps: routine.steps, height: 4, spacing: 1.5)
        }
        .padding(.vertical, 5)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}
