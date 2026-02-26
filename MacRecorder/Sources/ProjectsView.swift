import SwiftUI

struct ProjectsView: View {
    @Bindable var appState: AppState
    @State private var newName = ""
    @State private var newFolder = ""
    @State private var newDefaultLanguage = "ru"
    @State private var newPostScript = ""
    @State private var editingProject: Project?

    var body: some View {
        VStack(spacing: 0) {
            // Project list
            List(selection: Binding(
                get: { appState.selectedProjectId },
                set: { appState.selectProject(id: $0) }
            )) {
                ForEach(appState.projects) { project in
                    ProjectRow(project: project, isSelected: appState.selectedProjectId == project.id)
                        .tag(project.id)
                        .contextMenu {
                            Button("Edit...") { editingProject = project }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteProject(project)
                            }
                        }
                }
            }
            .listStyle(.inset)

            Divider()

            // Add new project
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Project Name", text: $newName)
                        .textFieldStyle(.roundedBorder)

                    Button("Folder...") {
                        chooseFolder()
                    }

                    Button("Add") {
                        addProject()
                    }
                    .disabled(newName.isEmpty || newFolder.isEmpty)
                }

                HStack(spacing: 8) {
                    Picker("Default Language", selection: $newDefaultLanguage) {
                        Text("Russian").tag("ru")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    TextField("Post script (uses TXT_PATH JSON_PATH AUDIO_PATH)", text: $newPostScript)
                        .textFieldStyle(.roundedBorder)
                }

                if !newFolder.isEmpty {
                    Text(newFolder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Projects")
        .frame(minWidth: 400, minHeight: 300)
        .sheet(item: $editingProject) { project in
            EditProjectSheet(project: project) { updated in
                ProjectManager.updateProject(updated)
                appState.projects = ProjectManager.loadProjects()
                if appState.selectedProjectId == updated.id {
                    appState.selectProject(id: updated.id)
                }
                editingProject = nil
            }
        }
    }

    private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.newFolder = url.path
            }
        }
    }

    private func addProject() {
        let project = Project(
            name: newName,
            folderPath: newFolder,
            defaultLanguage: newDefaultLanguage,
            postTranscriptionScript: newPostScript
        )
        ProjectManager.addProject(project)
        appState.projects = ProjectManager.loadProjects()
        appState.selectProject(id: project.id)
        newName = ""
        newFolder = ""
        newDefaultLanguage = "ru"
        newPostScript = ""
    }

    private func deleteProject(_ project: Project) {
        ProjectManager.deleteProject(id: project.id)
        appState.projects = ProjectManager.loadProjects()
        if appState.selectedProjectId == project.id {
            appState.selectProject(id: appState.projects.first?.id)
        }
    }
}

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .fontWeight(isSelected ? .semibold : .regular)
            Text("Language: \(project.defaultLanguage.uppercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(project.folderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct EditProjectSheet: View {
    @State var project: Project
    let onSave: (Project) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Project")
                .font(.headline)

            Form {
                TextField("Name:", text: $project.name)
                Picker("Default language:", selection: $project.defaultLanguage) {
                    Text("Russian").tag("ru")
                    Text("English").tag("en")
                }
                HStack {
                    TextField("Folder:", text: $project.folderPath)
                    Button("Browse...") {
                        NSApp.activate(ignoringOtherApps: true)
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Select"
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                project.folderPath = url.path
                            }
                        }
                    }
                }
                TextField("Post script:", text: $project.postTranscriptionScript)
                    .help("Use TXT_PATH JSON_PATH AUDIO_PATH placeholders.")
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    project.defaultLanguage = Project.normalizedLanguage(project.defaultLanguage)
                    onSave(project)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(project.name.isEmpty || project.folderPath.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}
