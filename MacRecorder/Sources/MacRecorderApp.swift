import SwiftUI

@main
struct MacRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appState.isRecording ? .red : .primary)
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Transcript", id: "transcript") {
            TranscriptView(appState: appState)
                .frame(minWidth: 500, minHeight: 400)
                .background(WindowKeyHelper())
        }

        Window("Projects", id: "projects") {
            ProjectsView(appState: appState)
                .frame(minWidth: 500, minHeight: 400)
                .background(WindowKeyHelper())
        }

        Settings {
            SettingsView(appState: appState)
                .frame(minWidth: 500, minHeight: 400)
                .background(WindowKeyHelper())
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched from `swift run`/raw executable there may be no app bundle metadata.
        // Force accessory mode so MenuBarExtra is allowed to appear in the menu bar.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Makes the hosting NSWindow become key window so text fields accept keyboard input.
/// Needed for LSUIElement (menu bar) apps where windows don't auto-become key.
struct WindowKeyHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            view.window?.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
