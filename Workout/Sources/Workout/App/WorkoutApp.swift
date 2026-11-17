import SwiftUI

@main
struct WorkoutApp: App {
    @StateObject private var store = DataStore()

    var body: some Scene {
        WindowGroup("Workout") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Routine") { store.newRoutine() }
                    .keyboardShortcut("n")
                    .disabled(store.playingRoutineID != nil)
                Button("Import Routines…") { store.importRoutines() }
                    .keyboardShortcut("o")
                    .disabled(store.playingRoutineID != nil)
            }
            CommandMenu("Workout") {
                Button("Start Selected Routine") {
                    if let id = store.selectedRoutineID { store.play(id) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.playingRoutineID != nil || store.selectedRoutineID.flatMap(store.routine(id:))?.steps.isEmpty != false)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        ZStack {
            if let id = store.playingRoutineID {
                PlayerView(routineID: id) { store.playingRoutineID = nil }
                    .transition(.opacity)
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 360)
                } detail: {
                    detail
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.playingRoutineID)
        #if DEBUG
        .onAppear { DebugScenes.apply(to: store) }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        if let id = store.selectedRoutineID, store.routine(id: id) != nil {
            RoutineEditorView(routine: binding(for: id))
                .id(id)
        } else {
            WelcomeView()
        }
    }

    /// Looks the routine up by id on every access, so deleting it can't leave
    /// a dangling index binding behind.
    private func binding(for id: UUID) -> Binding<Routine> {
        Binding(
            get: { store.routine(id: id) ?? Routine(id: id) },
            set: { newValue in
                guard let idx = store.routines.firstIndex(where: { $0.id == id }) else { return }
                var updated = newValue
                updated.updatedAt = Date()
                store.routines[idx] = updated
            }
        )
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 96, height: 96)
                Image(systemName: "figure.run")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 6) {
                Text(store.routines.isEmpty ? "Build your first routine" : "Pick a routine")
                    .font(.rounded(26, .bold))
                Text("Mix follow-along videos, timed exercises, rests and dance breaks.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { store.newRoutine() } label: {
                    Label("New Routine", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                Button { store.importRoutines() } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}
