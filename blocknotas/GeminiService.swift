import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)
    case decodingError
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Falta la API key de Gemini. Configúrela en Ajustes."
        case .invalidResponse:
            return "La respuesta del servicio no fue válida."
        case .httpError(let code):
            return "La API devolvió un error HTTP \(code)."
        case .decodingError:
            return "No se pudo procesar la respuesta de Gemini."
        case .requestFailed(let message):
            return message
        }
    }
}

struct GeminiService {
    static let shared = GeminiService()

    private let session: URLSession = .shared

    func sendMessage(_ message: String, notes: [Note], apiKey: String, model: String = "gemini-2.5-flash") async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.missingAPIKey
        }

        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedKey = cleanedKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanedKey
        let modelsToTry = Array(Set([model, "gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"]))
        let contextText = buildNotesContext(from: notes, userQuery: message)
        let prompt = """
        Contexto de notas del usuario:
        \(contextText)

        Pregunta del usuario:
        \(message)
        """

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var lastError: Error?

        for modelName in modelsToTry {
            let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(encodedKey)"
            guard let url = URL(string: endpoint) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            request.timeoutInterval = 30

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GeminiError.invalidResponse
                }

                if 200..<300 ~= httpResponse.statusCode {
                    do {
                        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
                        if let text = decoded.candidates.first?.content.parts.first?.text, !text.isEmpty {
                            return text
                        }
                        throw GeminiError.invalidResponse
                    } catch {
                        let bodyString = String(data: data, encoding: .utf8) ?? ""
                        throw GeminiError.requestFailed("No se pudo interpretar la respuesta de Gemini. \(bodyString)")
                    }
                }

                let bodyString = String(data: data, encoding: .utf8) ?? ""
                let lower = bodyString.lowercased()
                lastError = GeminiError.requestFailed("La API key no es válida o el modelo no está disponible. Usa una clave de Google AI Studio y prueba con gemini-2.5-flash o gemini-2.0-flash. Detalle: \(lower)")

                if lower.contains("model not found") || lower.contains("not found") || lower.contains("unsupported") || lower.contains("404") {
                    continue
                }
                throw lastError!
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw GeminiError.invalidResponse
    }

    func extractSuggestedNote(from text: String) -> (title: String, content: String)? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized.split(whereSeparator: { $0 == "\n" }).map(String.init)

        guard let titleLine = lines.first(where: { $0.lowercased().contains("título:") || $0.lowercased().contains("titulo:") || $0.lowercased().contains("title:") }) else {
            return nil
        }

        let titleValue = titleLine
            .components(separatedBy: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let contentLines = lines.filter { !($0.lowercased().contains("título:") || $0.lowercased().contains("titulo:") || $0.lowercased().contains("title:")) }
        let contentValue = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !titleValue.isEmpty, !contentValue.isEmpty else {
            return nil
        }

        return (titleValue, contentValue)
    }

    private func buildNotesContext(from notes: [Note], userQuery: String) -> String {
        let sorted = notes.sorted { $0.updatedAt > $1.updatedAt }
        let limit = min(sorted.count, 12)
        let selected = Array(sorted.prefix(limit))

        if selected.isEmpty {
            return "El usuario no tiene notas todavía."
        }

        let blocks = selected.enumerated().map { index, note in
            let tags = note.tagList.isEmpty ? "sin etiquetas" : note.tagList.joined(separator: ", ")
            return "- Nota \(index + 1): Título: \(note.title)\n  Etiquetas: \(tags)\n  Contenido: \(note.content)"
        }

        return blocks.joined(separator: "\n\n")
    }

    private var systemPrompt: String {
        """
        Eres un asistente útil para un usuario que guarda notas personales. Tienes acceso completo a todas sus notas del dispositivo.

        Tu trabajo es:
        - Buscar información relevante dentro de las notas del usuario.
        - Responder preguntas contextualizadas usando el contenido de esas notas.
        - Resumir grupos de notas cuando el usuario lo pida.
        - Sugerir conexiones, temas o categorías entre notas.
        - Ayudar a organizar y clasificar información.
        - Crear nuevas notas cuando el usuario lo solicite.

        Reglas:
        1. Usa el contenido disponible en las notas como fuente principal.
        2. Sé preciso, útil y contextual.
        3. Si el usuario pide crear una nota, usa este formato exacto en la respuesta:
           TÍTULO: <título claro y breve>
           CONTENIDO: <contenido completo>
        4. Responde en Markdown claro y estructurado.
        5. Si no encuentras información suficiente, dilo de forma honesta y propone una buena siguiente acción.
        6. No inventes contenido que no exista en las notas.
        """
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String
    }
}
