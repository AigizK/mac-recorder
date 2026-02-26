import Foundation

// MARK: - Commands (Swift -> Python)

struct TranscribeConfig: Codable {
    let audioPath: String
    var language: String = "auto"
    var russianModel: String = "gigaam-v3-rnnt"
    var englishModel: String = "whisper-base"

    enum CodingKeys: String, CodingKey {
        case audioPath = "audio_path"
        case language
        case russianModel = "russian_model"
        case englishModel = "english_model"
    }
}

struct EngineCommand: Codable {
    let type: String
    var audioPath: String?
    var language: String?
    var russianModel: String?
    var englishModel: String?

    enum CodingKeys: String, CodingKey {
        case type
        case audioPath = "audio_path"
        case language
        case russianModel = "russian_model"
        case englishModel = "english_model"
    }
}

// MARK: - Events (Python -> Swift)

struct EngineEvent: Codable {
    let type: String

    // status
    var state: String?
    var message: String?

    // transcript_complete
    var segments: [TranscriptSegmentDTO]?
    var fullText: String?

    enum CodingKeys: String, CodingKey {
        case type, state, message, segments
        case fullText = "full_text"
    }
}

struct TranscriptSegmentDTO: Codable {
    let start: Double
    let end: Double
    let text: String
    let language: String
    let source: String?
}

// MARK: - Transcript Segment (for UI)

struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let language: String
    let source: String?
    let start: Double
    let end: Double

    var formattedTime: String {
        let h = Int(start) / 3600
        let m = (Int(start) % 3600) / 60
        let s = Int(start) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
