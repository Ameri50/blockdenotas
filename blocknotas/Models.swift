import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var parentFolder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Folder.parentFolder) var childFolders: [Folder] = []

    init(name: String, createdAt: Date = .now, parentFolder: Folder? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.parentFolder = parentFolder
    }
}

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var tags: String
    var folderID: UUID?

    init(title: String, content: String, createdAt: Date = .now, updatedAt: Date = .now, tags: [String] = [], folder: Folder? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = Note.normalize(tags)
        self.folderID = folder?.id
    }

    var tagList: [String] {
        let parsed = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parsed
    }

    func setTags(_ newTags: [String]) {
        self.tags = Note.normalize(newTags)
        self.updatedAt = Date()
    }

    static func normalize(_ values: [String]) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
            .uniqued()
        return cleaned.joined(separator: ", ")
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var createdAt: Date

    init(role: String, content: String, createdAt: Date = .now) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var apiKeyConfigured: Bool
    var lastModel: String
    var sortMode: String

    init(apiKeyConfigured: Bool = false, lastModel: String = "gemini-2.5-flash", sortMode: String = "updatedAt") {
        self.id = UUID()
        self.apiKeyConfigured = apiKeyConfigured
        self.lastModel = lastModel
        self.sortMode = sortMode
    }
}

extension Array where Element == String {
    func uniqued() -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for value in self {
            let key = value.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(value)
            }
        }
        return unique
    }
}
