import Foundation
import SwiftUI

/// Shared application state.
@Observable
final class AppState {
    // Engine
    let bridge = PythonBridge()
    let audioCapturer = AudioCapturer()

    // Recording state
    var isRecording = false
    var isTranscribing = false
    var isLoading = false
    var statusMessage = "Ready"

    // Transcript
    var segments: [TranscriptSegment] = []
    var fullText = ""

    // Projects
    var projects: [Project] = []
    var selectedProjectId: UUID?

    // Language
    var selectedLanguage = "auto"

    // Settings
    var outputFormat: String = "both"
    var russianModel: String = "gigaam-v3-rnnt"
    var englishModel: String = "whisper-base"
    var pythonPath: String = "python3"

    // Recording session
    private var recordingStartTime: Date?
    private var currentAudioPath: URL?

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
    }

    private struct SavedTranscriptPaths {
        let audioPath: URL
        let txtPath: URL
        let jsonPath: URL
    }

    init() {
        loadSettings()
        projects = ProjectManager.loadProjects()
        if selectedProjectId == nil {
            selectedProjectId = projects.first?.id
        }
        if let project = selectedProject {
            selectedLanguage = project.defaultLanguage
        }
        bridge.onEvent = { [weak self] event in
            self?.handleEvent(event)
        }
        startEngine()
    }

    func startEngine() {
        guard !bridge.isRunning else { return }
        bridge.start(pythonPath: pythonPath)
    }

    func startRecording() {
        guard !isRecording, !isTranscribing else { return }
        guard let project = selectedProject else {
            statusMessage = "No project selected"
            return
        }

        // Ensure project folder exists
        let folderURL = project.folderURL
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Generate filename based on start time
        let now = Date()
        recordingStartTime = now
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let startStr = formatter.string(from: now)
        let audioPath = folderURL.appendingPathComponent("\(startStr).wav")
        currentAudioPath = audioPath

        isRecording = true
        isLoading = true
        segments = []
        fullText = ""
        statusMessage = "Starting capture..."

        Task {
            do {
                try await audioCapturer.startCapture(outputPath: audioPath)
                await MainActor.run {
                    isLoading = false
                    statusMessage = "Recording..."
                }
            } catch {
                await MainActor.run {
                    isRecording = false
                    isLoading = false
                    statusMessage = "Capture error: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        statusMessage = "Stopping..."

        Task {
            await audioCapturer.stopCapture()

            guard let audioPath = currentAudioPath,
                  let startTime = recordingStartTime else {
                await MainActor.run { statusMessage = "Ready" }
                return
            }

            // Rename file to include end time
            let endTime = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let startStr = formatter.string(from: startTime)
            let endStr = formatter.string(from: endTime)
            let endTimeOnly = String(endStr.suffix(8)) // HH-mm-ss

            let folder = audioPath.deletingLastPathComponent()
            let finalName = "\(startStr)--\(endTimeOnly)"
            let finalAudioPath = folder.appendingPathComponent("\(finalName).wav")
            let mixedAudioPath = audioPath.deletingPathExtension().appendingPathExtension("mixed.wav")
            let sourceAudioPath: URL = FileManager.default.fileExists(atPath: mixedAudioPath.path) ? mixedAudioPath : audioPath

            // Rename the best available audio file (prefer mixed stereo if present).
            try? FileManager.default.moveItem(at: sourceAudioPath, to: finalAudioPath)
            let transcribeAudioPath = FileManager.default.fileExists(atPath: finalAudioPath.path) ? finalAudioPath : sourceAudioPath
            if sourceAudioPath == mixedAudioPath, FileManager.default.fileExists(atPath: audioPath.path) {
                try? FileManager.default.removeItem(at: audioPath)
            }

            await MainActor.run {
                currentAudioPath = transcribeAudioPath
                statusMessage = "Transcribing..."
                isTranscribing = true
            }

            let project = selectedProject
            let language = project?.defaultLanguage ?? selectedLanguage
            let models = project?.defaultModels ?? (russian: russianModel, english: englishModel)

            // Send transcribe command to Python engine
            await MainActor.run {
                guard bridge.isRunning else {
                    statusMessage = "Engine not running"
                    isTranscribing = false
                    return
                }
                bridge.transcribe(
                    audioPath: transcribeAudioPath.path,
                    language: language,
                    russianModel: models.russian,
                    englishModel: models.english
                )
            }
        }
    }

    func setLanguage(_ lang: String) {
        selectedLanguage = lang
        guard lang == "ru" || lang == "en" else { return }
        guard var project = selectedProject else { return }
        project.defaultLanguage = Project.normalizedLanguage(lang)
        ProjectManager.updateProject(project)
        projects = ProjectManager.loadProjects()
        saveSettings()
    }

    func selectProject(id: UUID?) {
        selectedProjectId = id
        if let project = selectedProject {
            selectedLanguage = project.defaultLanguage
        }
        saveSettings()
    }

    func shutdown() {
        if isRecording {
            Task {
                await audioCapturer.stopCapture()
            }
        }
        bridge.terminate()
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: EngineEvent) {
        switch event.type {
        case "status":
            statusMessage = event.message ?? ""
            if event.state == "ready" {
                statusMessage = "Engine ready"
            }

        case "transcribing":
            statusMessage = event.message ?? "Transcribing..."

        case "transcript_complete":
            isTranscribing = false
            if let dtos = event.segments {
                segments = dtos.map { dto in
                    TranscriptSegment(
                        text: dto.text,
                        language: dto.language,
                        source: dto.source,
                        start: dto.start,
                        end: dto.end
                    )
                }
            }
            fullText = event.fullText ?? ""
            statusMessage = "Transcription complete (\(segments.count) segments)"

            // Save transcript files
            if let paths = saveTranscript() {
                runPostTranscriptionScript(paths)
            }

        case "error":
            statusMessage = "Error: \(event.message ?? "unknown")"
            isTranscribing = false
            isLoading = false

        default:
            break
        }
    }

    // MARK: - Save Transcript

    private func saveTranscript() -> SavedTranscriptPaths? {
        guard let audioPath = currentAudioPath else { return nil }
        let baseName = audioPath.deletingPathExtension().lastPathComponent
        let folder = audioPath.deletingLastPathComponent()
        let txtPath = folder.appendingPathComponent("\(baseName).txt")
        let jsonPath = folder.appendingPathComponent("\(baseName).json")

        if outputFormat == "text" || outputFormat == "both" {
            var lines: [String] = []
            for seg in segments {
                let ts = formatTimestamp(seg.start)
                let sourceTag = seg.source.map { "[\($0)]" } ?? ""
                lines.append("[\(ts)] [\(seg.language)]\(sourceTag) \(seg.text)")
            }
            let content = lines.joined(separator: "\n")
            try? content.write(to: txtPath, atomically: true, encoding: .utf8)
        }

        if outputFormat == "json" || outputFormat == "both" {
            let data: [String: Any] = [
                "segments": segments.map { seg in
                    var segmentData: [String: Any] = [
                        "start": seg.start,
                        "end": seg.end,
                        "text": seg.text,
                        "language": seg.language,
                    ]
                    if let source = seg.source {
                        segmentData["source"] = source
                    }
                    return segmentData
                },
                "full_text": fullText,
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
                try? jsonData.write(to: jsonPath)
            }
        }

        return SavedTranscriptPaths(audioPath: audioPath, txtPath: txtPath, jsonPath: jsonPath)
    }

    private func runPostTranscriptionScript(_ paths: SavedTranscriptPaths) {
        guard let project = selectedProject else { return }
        let script = project.postTranscriptionScript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return }

        let commandWithPaths = replacePlaceholder("TXT_PATH", in: script, with: shellQuote(paths.txtPath.path))
        let commandWithJSON = replacePlaceholder("JSON_PATH", in: commandWithPaths, with: shellQuote(paths.jsonPath.path))
        let commandWithAudio = replacePlaceholder("AUDIO_PATH", in: commandWithJSON, with: shellQuote(paths.audioPath.path))
        let command = normalizePostScriptCommand(commandWithAudio)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = project.folderURL
        var environment = ProcessInfo.processInfo.environment
        environment["TXT_PATH"] = paths.txtPath.path
        environment["JSON_PATH"] = paths.jsonPath.path
        environment["AUDIO_PATH"] = paths.audioPath.path
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            statusMessage = "Post script start failed: \(error.localizedDescription)"
            return
        }

        print("[PostScript cwd] \(project.folderURL.path)")
        print("[PostScript cmd] \(command)")

        process.terminationHandler = { [weak self] process in
            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[PostScript stdout] \(stdout)")
            }
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[PostScript stderr] \(stderr)")
            }

            DispatchQueue.main.async {
                guard let self else { return }
                if process.terminationStatus == 0 {
                    self.statusMessage = "Transcription complete (\(self.segments.count) segments), script done"
                } else {
                    self.statusMessage = "Post script failed (exit \(process.terminationStatus))"
                }
            }
        }
    }

    private func shellQuote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func normalizePostScriptCommand(_ command: String) -> String {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("codex exec ") else { return command }
        guard !normalized.contains("--skip-git-repo-check") else { return command }
        if let range = command.range(of: "codex exec") {
            return command.replacingCharacters(in: range, with: "codex exec --skip-git-repo-check")
        }
        return command
    }

    private func replacePlaceholder(_ placeholder: String, in script: String, with value: String) -> String {
        // Replace only bare placeholders like `TXT_PATH`, but skip shell vars like
        // `$TXT_PATH` and `${TXT_PATH...}`.
        let pattern = "(?<![\\w$\\{])" + NSRegularExpression.escapedPattern(for: placeholder) + "(?!\\w)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return script
        }
        let range = NSRange(script.startIndex..<script.endIndex, in: script)
        return regex.stringByReplacingMatches(in: script, options: [], range: range, withTemplate: value)
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        selectedLanguage = defaults.string(forKey: "selectedLanguage") ?? "auto"
        outputFormat = defaults.string(forKey: "outputFormat") ?? "both"
        russianModel = defaults.string(forKey: "russianModel") ?? "gigaam-v3-rnnt"
        englishModel = defaults.string(forKey: "englishModel") ?? "whisper-base"
        pythonPath = defaults.string(forKey: "pythonPath") ?? "python3"
        if let idStr = defaults.string(forKey: "selectedProjectId"),
           let uuid = UUID(uuidString: idStr) {
            selectedProjectId = uuid
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedLanguage, forKey: "selectedLanguage")
        defaults.set(outputFormat, forKey: "outputFormat")
        defaults.set(russianModel, forKey: "russianModel")
        defaults.set(englishModel, forKey: "englishModel")
        defaults.set(pythonPath, forKey: "pythonPath")
        if let id = selectedProjectId {
            defaults.set(id.uuidString, forKey: "selectedProjectId")
        }
    }
}
