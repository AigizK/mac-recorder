import Foundation

/// Manages the Python ASR engine subprocess and JSON pipe communication.
@Observable
final class PythonBridge {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var onEvent: ((EngineEvent) -> Void)?
    var isRunning: Bool { process?.isRunning ?? false }

    /// Launch the Python engine subprocess.
    func start(pythonPath: String = "python3") {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let engineDir = findEngineDirectory()
        let resolvedPython = resolvePython(pythonPath, engineDir: engineDir)

        print("[PythonBridge] Using python: \(resolvedPython)")
        print("[PythonBridge] Engine dir: \(engineDir?.path ?? "not found")")

        process.executableURL = URL(fileURLWithPath: resolvedPython)
        process.arguments = ["-m", "mac_recorder_engine"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let dir = engineDir {
            process.currentDirectoryURL = dir
        }

        // Set PYTHONPATH to include the engine src
        var env = ProcessInfo.processInfo.environment
        if let dir = engineDir {
            let srcPath = dir.appendingPathComponent("src").path
            if let existing = env["PYTHONPATH"] {
                env["PYTHONPATH"] = "\(srcPath):\(existing)"
            } else {
                env["PYTHONPATH"] = srcPath
            }
        }
        if let hfHome = macRecorderSupportDirectory()?.appendingPathComponent("hf-cache") {
            try? FileManager.default.createDirectory(at: hfHome, withIntermediateDirectories: true)
            env["HF_HOME"] = hfHome.path
        }
        process.environment = env

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        // Read stdout line by line in background
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleStdoutData(data)
        }

        // Log stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                print("[engine/stderr] \(line)")
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.stdinPipe = nil
                self?.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stderrPipe?.fileHandleForReading.readabilityHandler = nil
            }
        }

        do {
            try process.run()
        } catch {
            print("Failed to start Python engine: \(error)")
        }
    }

    /// Send a command to the Python engine.
    func send(command: EngineCommand) {
        guard let pipe = stdinPipe else { return }
        do {
            let data = try encoder.encode(command)
            pipe.fileHandleForWriting.write(data)
            pipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
        } catch {
            print("Failed to encode command: \(error)")
        }
    }

    /// Send a transcribe command for the given audio file.
    func transcribe(audioPath: String, language: String, russianModel: String, englishModel: String) {
        send(command: EngineCommand(
            type: "transcribe",
            audioPath: audioPath,
            language: language,
            russianModel: russianModel,
            englishModel: englishModel
        ))
    }

    /// Terminate the Python process.
    func terminate() {
        stdinPipe?.fileHandleForWriting.closeFile()
        process?.terminate()
        process = nil
    }

    // MARK: - Private

    private var stdoutBuffer = Data()

    private func handleStdoutData(_ data: Data) {
        stdoutBuffer.append(data)

        // Split by newlines and process complete JSON lines
        while let range = stdoutBuffer.range(of: "\n".data(using: .utf8)!) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<range.lowerBound)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...range.lowerBound)

            guard !lineData.isEmpty else { continue }

            do {
                let event = try decoder.decode(EngineEvent.self, from: lineData)
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(event)
                }
            } catch {
                if let text = String(data: lineData, encoding: .utf8) {
                    print("[engine/stdout] (non-JSON): \(text)")
                }
            }
        }
    }

    private func findEngineDirectory() -> URL? {
        let installedEngine = macRecorderSupportDirectory()?.appendingPathComponent("engine")
        let bundledEngine = Bundle.main.resourceURL?.appendingPathComponent("engine-template")
        let candidates = [
            installedEngine,
            bundledEngine,
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("engine"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("engine"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("projects/mac-recorder/engine"),
        ].compactMap { $0 }
        for url in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }

    /// Resolve python path: prefer venv python inside engine/.venv, then user-specified path.
    private func resolvePython(_ pythonPath: String, engineDir: URL?) -> String {
        // If user gave an absolute path that exists, use it directly
        if pythonPath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: pythonPath) {
            return pythonPath
        }
        // Try venv python inside the engine directory
        if let dir = engineDir {
            let venvPython = dir.appendingPathComponent(".venv/bin/python3").path
            if FileManager.default.isExecutableFile(atPath: venvPython) {
                print("[PythonBridge] Found venv python: \(venvPython)")
                return venvPython
            }
        }
        // Fallback: try homebrew pythons
        for candidate in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return pythonPath
    }

    private func macRecorderSupportDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MacRecorder", isDirectory: true)
    }
}
