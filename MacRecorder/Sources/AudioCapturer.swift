import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Captures system audio via ScreenCaptureKit and microphone via AVAudioEngine,
/// then writes a stereo WAV: left channel is microphone, right channel is system audio.
final class AudioCapturer: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var systemAudioFile: AVAudioFile?
    private var micAudioFile: AVAudioFile?
    private var micEngine: AVAudioEngine?
    private var outputPath: URL?
    private var micTempPath: URL?
    private var micFramesWritten: AVAudioFramePosition = 0
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private let queue = DispatchQueue(label: "com.macrecorder.audiocapture")

    var isCapturing: Bool { stream != nil }

    /// Start capturing system audio and microphone, writing to the given WAV path.
    func startCapture(outputPath: URL) async throws {
        self.outputPath = outputPath
        let micPath = outputPath.deletingPathExtension().appendingPathExtension("mic.wav")
        self.micTempPath = micPath
        self.micFramesWritten = 0
        try? FileManager.default.removeItem(at: micPath)

        do {
            try await ensureMicrophonePermission()
            try startMicrophoneCapture(outputPath: micPath)

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                throw AudioCaptureError.noDisplay
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 16000
            config.channelCount = 1
            // Minimal video settings (we only need audio)
            config.width = 2
            config.height = 2

            let systemFile = try AVAudioFile(
                forWriting: outputPath,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            self.systemAudioFile = systemFile

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            self.stream = stream

            try await stream.startCapture()
        } catch {
            stopMicrophoneCapture()
            stream = nil
            systemAudioFile = nil
            micAudioFile = nil
            self.outputPath = nil
            self.micTempPath = nil
            micFramesWritten = 0
            try? FileManager.default.removeItem(at: micPath)
            throw error
        }
    }

    /// Stop capture and close the audio file.
    func stopCapture() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stopMicrophoneCapture()

        stream = nil
        systemAudioFile = nil
        micAudioFile = nil

        if let outputPath, let micTempPath, micFramesWritten > 0 {
            do {
                try mixMicIntoSystemAudio(systemAudioPath: outputPath, micAudioPath: micTempPath)
            } catch {
                print("[AudioCapturer] Mix error: \(error)")
            }
        }

        if let micTempPath {
            try? FileManager.default.removeItem(at: micTempPath)
        }

        outputPath = nil
        self.micTempPath = nil
        micFramesWritten = 0
    }

    enum AudioCaptureError: Error, LocalizedError {
        case noDisplay
        case microphonePermissionDenied
        case noMicrophoneInput

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for audio capture"
            case .microphonePermissionDenied:
                return "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
            case .noMicrophoneInput:
                return "No microphone input device available."
            }
        }
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            guard granted else { throw AudioCaptureError.microphonePermissionDenied }
        case .restricted, .denied:
            throw AudioCaptureError.microphonePermissionDenied
        @unknown default:
            throw AudioCaptureError.microphonePermissionDenied
        }
    }

    private func startMicrophoneCapture(outputPath: URL) throws {
        let micFile = try AVAudioFile(
            forWriting: outputPath,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.micAudioFile = micFile

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noMicrophoneInput
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.noMicrophoneInput
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let micAudioFile = self.micAudioFile else { return }
            guard let converted = self.convertToOutputFormat(buffer: buffer, converter: converter) else { return }
            guard converted.frameLength > 0 else { return }
            do {
                try micAudioFile.write(from: converted)
                self.micFramesWritten += AVAudioFramePosition(converted.frameLength)
            } catch {
                print("[AudioCapturer] Microphone write error: \(error)")
            }
        }

        engine.prepare()
        try engine.start()
        self.micEngine = engine
    }

    private func stopMicrophoneCapture() {
        if let inputNode = micEngine?.inputNode {
            inputNode.removeTap(onBus: 0)
        }
        micEngine?.stop()
        micEngine = nil
    }

    private func convertToOutputFormat(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var provided = false
        converter.convert(to: outputBuffer, error: &error) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return buffer
        }

        if let error {
            print("[AudioCapturer] Microphone convert error: \(error)")
            return nil
        }

        return outputBuffer
    }

    private func mixMicIntoSystemAudio(systemAudioPath: URL, micAudioPath: URL) throws {
        let mixedPath = systemAudioPath.deletingPathExtension().appendingPathExtension("mixed.wav")
        try? FileManager.default.removeItem(at: mixedPath)
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 2)!

        // Keep file handles scoped so they are fully closed before replacing the source file.
        do {
            let systemFile = try AVAudioFile(forReading: systemAudioPath)
            let micFile = try AVAudioFile(forReading: micAudioPath)
            let mixedFile = try AVAudioFile(
                forWriting: mixedPath,
                settings: stereoFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            let chunk: AVAudioFrameCount = 4096
            while true {
                guard let systemBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunk),
                      let micBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunk) else {
                    break
                }

                try systemFile.read(into: systemBuffer, frameCount: chunk)
                try micFile.read(into: micBuffer, frameCount: chunk)

                let outFrames = max(systemBuffer.frameLength, micBuffer.frameLength)
                guard outFrames > 0 else { break }

                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: outFrames),
                      let leftData = outBuffer.floatChannelData?[0],
                      let rightData = outBuffer.floatChannelData?[1],
                      let sysData = systemBuffer.floatChannelData?[0],
                      let micData = micBuffer.floatChannelData?[0] else {
                    break
                }

                outBuffer.frameLength = outFrames
                let sysFrames = Int(systemBuffer.frameLength)
                let micFrames = Int(micBuffer.frameLength)

                for i in 0..<Int(outFrames) {
                    // Left: microphone, Right: system/speaker audio.
                    leftData[i] = i < micFrames ? micData[i] : 0
                    rightData[i] = i < sysFrames ? sysData[i] : 0
                }

                try mixedFile.write(from: outBuffer)
            }
        }

        try? FileManager.default.removeItem(at: systemAudioPath)
        try FileManager.default.moveItem(at: mixedPath, to: systemAudioPath)
    }
}

extension AudioCapturer: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let systemAudioFile else { return }
        guard sampleBuffer.isValid else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        // Convert CMSampleBuffer to PCM buffer
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        let numSamples = sampleBuffer.numSamples
        guard numSamples > 0 else { return }

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &dataLength, dataPointerOut: &dataPointer)
        guard status == noErr, let dataPointer else { return }

        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        let sampleRate = asbd.pointee.mSampleRate

        guard let inputFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount)
        ) else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(numSamples)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Copy float data into the PCM buffer
        let bytesPerFrame = Int(asbd.pointee.mBytesPerFrame)
        let totalBytes = numSamples * bytesPerFrame

        if channelCount == 1 {
            // Mono: copy directly
            if let dest = pcmBuffer.floatChannelData?[0] {
                memcpy(dest, dataPointer, min(totalBytes, dataLength))
            }
        } else {
            // Multi-channel: mix down to mono for our output format
            // ScreenCaptureKit typically provides float32 interleaved
            let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
            if let dest = pcmBuffer.floatChannelData?[0] {
                for i in 0..<numSamples {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += floatPointer[i * channelCount + ch]
                    }
                    dest[i] = sum / Float(channelCount)
                }
            }
        }

        // If sample rates differ, do simple conversion
        if abs(sampleRate - 16000) > 1 {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return }
            let ratio = 16000.0 / sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(numSamples) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }

            if error == nil {
                do {
                    try systemAudioFile.write(from: outputBuffer)
                } catch {
                    print("[AudioCapturer] Write error: \(error)")
                }
            }
        } else {
            // Same sample rate, write directly
            do {
                try systemAudioFile.write(from: pcmBuffer)
            } catch {
                print("[AudioCapturer] Write error: \(error)")
            }
        }
    }
}
