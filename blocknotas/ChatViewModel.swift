import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var apiKeyStatus: String = "No configurada"

    private let context: ModelContext
    private let noteContext: ModelContext
    private let service = GeminiService.shared

    init(context: ModelContext, noteContext: ModelContext) {
        self.context = context
        self.noteContext = noteContext
        self.errorMessage = nil
        loadHistory()
        refreshAPIKeyStatus()
    }

    func loadHistory() {
        do {
            let descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
            messages = try context.fetch(descriptor)
        } catch {
            errorMessage = "No se pudo cargar el historial del chat: \(error.localizedDescription)"
        }
    }

    func refreshAPIKeyStatus() {
        let key: String
        do {
            key = try KeychainManager.load(forKey: "gemini_api_key")
            apiKeyStatus = key.isEmpty ? "No configurada" : "Configurada"
        } catch {
            apiKeyStatus = "No configurada"
        }
    }

    func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: "user", content: text)
        context.insert(userMessage)
        draft = ""
        messages.append(userMessage)
        isSending = true
        errorMessage = nil

        Task {
            do {
                let key = try KeychainManager.load(forKey: "gemini_api_key")
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GeminiError.missingAPIKey
                }

                let notes = try fetchNotes()
                let response = try await service.sendMessage(text, notes: notes, apiKey: key)

                let aiMessage = ChatMessage(role: "assistant", content: response)
                context.insert(aiMessage)
                try context.save()

                await MainActor.run {
                    messages.append(aiMessage)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "La API key no funciona o el modelo no está disponible. Prueba otra clave de Google AI Studio y usa un modelo como gemini-2.5-flash o gemini-2.0-flash.\n\nDetalle: \(error.localizedDescription)"
                }
            }
        }
    }

    func generateNoteFromConversation() -> Note? {
        guard let lastAssistant = messages.last(where: { $0.role == "assistant" }) else { return nil }
        guard let candidate = GeminiService.shared.extractSuggestedNote(from: lastAssistant.content) else { return nil }
        let note = Note(title: candidate.title, content: candidate.content)
        noteContext.insert(note)
        try? noteContext.save()
        return note
    }

    private func fetchNotes() throws -> [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try noteContext.fetch(descriptor)
    }
}
