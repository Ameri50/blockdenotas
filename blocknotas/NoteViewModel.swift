import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
final class NoteViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var folders: [Folder] = []
    @Published var currentFolder: Folder?
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .updatedAt
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentSettings: AppSettings?

    private let context: ModelContext
    private let apiKeyKey = "gemini_api_key"

    init(context: ModelContext) {
        self.context = context
        self.currentFolder = nil
        self.currentSettings = nil
        self.errorMessage = nil
        fetchSettings()
        fetchFolders()
        fetchNotes()
    }

    enum SortOrder: String, CaseIterable {
        case updatedAt = "updatedAt"
        case alphabetical = "alphabetical"
    }

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedNotes = currentFolder == nil ? notes : notes.filter { $0.folderID == currentFolder?.id }

        let filtered = query.isEmpty ? selectedNotes : selectedNotes.filter { note in
            let haystack = [note.title, note.content, note.tags].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }

        switch sortOrder {
        case .updatedAt:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .alphabetical:
            return filtered.sorted { $0.title.lowercased() < $1.title.lowercased() }
        }
    }

    var rootFolders: [Folder] {
        folders.filter { $0.parentFolder == nil }
    }

    func childFolders(of folder: Folder?) -> [Folder] {
        folders.filter { $0.parentFolder == folder }
    }

    func folderForNote(_ note: Note) -> Folder? {
        folders.first(where: { $0.id == note.folderID })
    }

    func fetchFolders() {
        do {
            let descriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)])
            folders = try context.fetch(descriptor)
        } catch {
            errorMessage = "No se pudieron cargar las carpetas: \(error.localizedDescription)"
        }
    }

    func fetchNotes() {
        do {
            let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            notes = try context.fetch(descriptor)
        } catch {
            errorMessage = "No se pudieron cargar las notas: \(error.localizedDescription)"
        }
    }

    func createFolder(name: String, parent: Folder? = nil) -> Folder? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "El nombre de la carpeta no puede estar vacío."
            return nil
        }

        let folder = Folder(name: trimmedName, parentFolder: parent)
        context.insert(folder)

        do {
            try context.save()
            fetchFolders()
            return folder
        } catch {
            errorMessage = "No se pudo crear la carpeta: \(error.localizedDescription)"
            return nil
        }
    }

    func updateFolder(_ folder: Folder, newName: String) -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "El nombre de la carpeta no puede estar vacío."
            return false
        }

        folder.name = trimmedName
        do {
            try context.save()
            fetchFolders()
            return true
        } catch {
            errorMessage = "No se pudo guardar la carpeta: \(error.localizedDescription)"
            return false
        }
    }

    func deleteFolder(_ folder: Folder) {
        context.delete(folder)
        do {
            try context.save()
            fetchFolders()
            fetchNotes()
        } catch {
            errorMessage = "No se pudo eliminar la carpeta: \(error.localizedDescription)"
        }
    }

    func saveNote(title: String, content: String, tags: [String], folder: Folder? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            errorMessage = "El título no puede estar vacío."
            return
        }

        let note = Note(title: trimmedTitle, content: trimmedContent, tags: tags, folder: folder)
        context.insert(note)
        do {
            try context.save()
            fetchNotes()
        } catch {
            errorMessage = "No se pudo guardar la nota: \(error.localizedDescription)"
        }
    }

    func updateNote(_ note: Note, title: String, content: String, tags: [String], folder: Folder? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            errorMessage = "El título no puede estar vacío."
            return
        }

        note.title = trimmedTitle
        note.content = trimmedContent
        note.folderID = folder?.id ?? note.folderID
        note.setTags(tags)
        note.updatedAt = Date()

        do {
            try context.save()
            fetchNotes()
        } catch {
            errorMessage = "No se pudo actualizar la nota: \(error.localizedDescription)"
        }
    }

    func deleteNote(_ note: Note) {
        context.delete(note)
        do {
            try context.save()
            fetchNotes()
        } catch {
            errorMessage = "No se pudo eliminar la nota: \(error.localizedDescription)"
        }
    }

    func saveAPIKey(_ key: String) {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "La API key no puede estar vacía."
            return
        }

        do {
            try KeychainManager.save(cleaned, forKey: apiKeyKey)
            fetchSettings()
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo guardar la API key: \(error.localizedDescription)"
        }
    }

    func loadAPIKey() -> String {
        do {
            return try KeychainManager.load(forKey: apiKeyKey)
        } catch {
            return ""
        }
    }

    func deleteAPIKey() {
        do {
            try KeychainManager.delete(forKey: apiKeyKey)
            fetchSettings()
        } catch {
            errorMessage = "No se pudo borrar la API key: \(error.localizedDescription)"
        }
    }

    func fetchSettings() {
        let descriptor = FetchDescriptor<AppSettings>(sortBy: [])
        if let settings = try? context.fetch(descriptor).first {
            currentSettings = settings
        } else {
            let settings = AppSettings()
            context.insert(settings)
            currentSettings = settings
            try? context.save()
        }

        let apiKey = loadAPIKey()
        currentSettings?.apiKeyConfigured = !apiKey.isEmpty
        if currentSettings != nil {
            try? context.save()
        }
    }
}
