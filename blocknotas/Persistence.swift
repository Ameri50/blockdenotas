import Foundation
import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init() {
        let schema = Schema([
            Note.self,
            ChatMessage.self,
            AppSettings.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("No se pudo crear ModelContainer: \(error)")
        }
    }

    @MainActor
    static func ensureDefaultSettings(in context: ModelContext) {
        let descriptor = FetchDescriptor<AppSettings>(sortBy: [])
        guard let settings = try? context.fetch(descriptor).first else {
            let defaults = AppSettings()
            context.insert(defaults)
            return
        }
        _ = settings
    }
}
