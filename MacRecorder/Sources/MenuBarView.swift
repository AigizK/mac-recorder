import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status
        Text(appState.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        // Start / Stop
        if appState.isRecording {
            Button("Stop Recording") {
                appState.stopRecording()
            }
            .keyboardShortcut("s")
        } else if appState.isTranscribing {
            Text("Transcribing...")
                .foregroundStyle(.secondary)
        } else {
            Button(appState.isLoading ? "Loading..." : "Start Recording") {
                appState.startRecording()
            }
            .disabled(appState.isLoading || appState.selectedProject == nil)
            .keyboardShortcut("r")
        }

        Divider()

        // Language
        Menu("Language: \(languageLabel)") {
            Button("Auto") { appState.setLanguage("auto") }
                .disabled(appState.selectedLanguage == "auto")
            Button("Russian") { appState.setLanguage("ru") }
                .disabled(appState.selectedLanguage == "ru")
            Button("English") { appState.setLanguage("en") }
                .disabled(appState.selectedLanguage == "en")
        }

        // Project
        if appState.projects.isEmpty {
            Text("No projects")
                .foregroundStyle(.secondary)
        } else {
            Menu("Project: \(appState.selectedProject?.name ?? "None")") {
                ForEach(appState.projects) { project in
                    Button(project.name) {
                        appState.selectProject(id: project.id)
                    }
                    .disabled(appState.selectedProjectId == project.id)
                }
            }
        }

        Divider()

        // Windows
        Button("Show Transcript") {
            openWindow(id: "transcript")
        }
        .keyboardShortcut("t")

        Button("Manage Projects...") {
            openWindow(id: "projects")
        }

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",")

        Divider()

        // Segments count
        if !appState.segments.isEmpty {
            Text("\(appState.segments.count) segments")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
        }

        Button("Quit") {
            appState.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var languageLabel: String {
        switch appState.selectedLanguage {
        case "ru": return "Russian"
        case "en": return "English"
        default: return "Auto"
        }
    }
}
