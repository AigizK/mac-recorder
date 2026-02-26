import Foundation

struct Project: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var folderPath: String
    var defaultLanguage: String
    var postTranscriptionScript: String

    init(
        id: UUID = UUID(),
        name: String,
        folderPath: String,
        defaultLanguage: String = "ru",
        postTranscriptionScript: String = ""
    ) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.defaultLanguage = Self.normalizedLanguage(defaultLanguage)
        self.postTranscriptionScript = postTranscriptionScript
    }

    /// Resolved URL for the folder path, expanding ~ if needed.
    var folderURL: URL {
        URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath)
    }

    var defaultModels: (russian: String, english: String) {
        // Russian uses GigaAM v3 RNNT, English uses Parakeet TDT.
        ("gigaam-v3-rnnt", "nemo-parakeet-tdt-0.6b-v3")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case folderPath
        case defaultLanguage
        case postTranscriptionScript
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Project"
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath) ?? ""
        let decodedLanguage = try container.decodeIfPresent(String.self, forKey: .defaultLanguage) ?? "ru"
        defaultLanguage = Self.normalizedLanguage(decodedLanguage)
        postTranscriptionScript = try container.decodeIfPresent(String.self, forKey: .postTranscriptionScript) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(Self.normalizedLanguage(defaultLanguage), forKey: .defaultLanguage)
        try container.encode(postTranscriptionScript, forKey: .postTranscriptionScript)
    }

    static func normalizedLanguage(_ language: String) -> String {
        language == "en" ? "en" : "ru"
    }
}

/// Manages CRUD operations on projects, persisted in UserDefaults.
enum ProjectManager {
    private static let key = "projects"

    static func loadProjects() -> [Project] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Project].self, from: data)) ?? []
    }

    static func saveProjects(_ projects: [Project]) {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func addProject(_ project: Project) {
        var projects = loadProjects()
        projects.append(project)
        saveProjects(projects)
    }

    static func deleteProject(id: UUID) {
        var projects = loadProjects()
        projects.removeAll { $0.id == id }
        saveProjects(projects)
    }

    static func updateProject(_ project: Project) {
        var projects = loadProjects()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
            saveProjects(projects)
        }
    }
}
