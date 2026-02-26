import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ASRSettingsTab(appState: appState)
                .tabItem {
                    Label("ASR", systemImage: "waveform")
                }
        }
        .padding()
        .frame(minWidth: 500)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Output") {
                Picker("Format:", selection: $appState.outputFormat) {
                    Text("Text + JSON").tag("both")
                    Text("Text only").tag("text")
                    Text("JSON only").tag("json")
                }
            }

            Section("Python") {
                TextField("Python Path:", text: $appState.pythonPath)
                    .help("Path to python3 with mac-recorder-engine installed")
            }

            HStack {
                Spacer()
                Button("Save") {
                    appState.saveSettings()
                }
                .keyboardShortcut(.return)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ASR

struct ASRSettingsTab: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Language") {
                Picker("Recognition Language:", selection: $appState.selectedLanguage) {
                    Text("Auto-detect").tag("auto")
                    Text("Russian").tag("ru")
                    Text("English").tag("en")
                }
            }

            Section("Models") {
                TextField("Russian Model:", text: $appState.russianModel)
                    .help("onnx-asr model name for Russian (e.g. gigaam-v3-rnnt)")
                TextField("English Model:", text: $appState.englishModel)
                    .help("onnx-asr model name for English (e.g. nemo-parakeet-tdt-0.6b-v3)")
            }

            HStack {
                Spacer()
                Button("Save") {
                    appState.saveSettings()
                }
                .keyboardShortcut(.return)
            }
        }
        .formStyle(.grouped)
    }
}
