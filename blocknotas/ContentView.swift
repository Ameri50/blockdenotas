import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            NotesTabView(modelContext: modelContext)
                .tabItem {
                    Label("Notas", systemImage: "note.text")
                }

            ChatTabView(modelContext: modelContext)
                .tabItem {
                    Label("IA", systemImage: "sparkles")
                }
        }
        .tint(.purple)
        .background(LinearGradient(colors: [Color.purple.opacity(0.08), Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
    }
}

struct NotesTabView: View {
    @StateObject private var viewModel: NoteViewModel
    @State private var isShowingEditor = false
    @State private var editingNote: Note?
    @State private var showSettings = false
    @State private var showFolderSheet = false
    @State private var showFolderMenu = false
    @State private var folderName = ""
    @State private var folderParent: Folder?
    @State private var editingFolder: Folder?

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: NoteViewModel(context: modelContext))
    }

    private var currentFolderLabel: String {
        viewModel.currentFolder?.name ?? "Todas"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.purple.opacity(0.06), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    folderBar

                    if viewModel.filteredNotes.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(viewModel.filteredNotes) { note in
                                NavigationLink(value: note) {
                                    NoteRow(note: note)
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .swipeActions {
                                    Button(role: .destructive) {
                                        viewModel.deleteNote(note)
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("NotasAI")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFolderMenu = true
                    } label: {
                        Label("Carpetas", systemImage: "folder")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingNote = nil
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar notas")
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note, viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingEditor) {
                NoteEditorView(note: editingNote, mode: editingNote == nil ? .new : .edit, selectedFolder: viewModel.currentFolder) { title, content, tags in
                    if let note = editingNote {
                        let targetFolder = viewModel.currentFolder ?? viewModel.folderForNote(note)
                        viewModel.updateNote(note, title: title, content: content, tags: tags, folder: targetFolder)
                    } else {
                        viewModel.saveNote(title: title, content: content, tags: tags, folder: viewModel.currentFolder)
                    }
                    isShowingEditor = false
                    editingNote = nil
                }
            }
            .sheet(isPresented: $showFolderSheet) {
                FolderEditorSheet(title: editingFolder == nil ? "Crear carpeta" : "Editar carpeta", parent: folderParent, existingFolder: editingFolder) { name, parent in
                    if let folder = editingFolder {
                        _ = viewModel.updateFolder(folder, newName: name)
                        viewModel.currentFolder = folder
                    } else if let created = viewModel.createFolder(name: name, parent: parent) {
                        viewModel.currentFolder = created
                    }
                    showFolderSheet = false
                    folderName = ""
                    folderParent = nil
                    editingFolder = nil
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    apiKey: viewModel.loadAPIKey(),
                    onSave: { key in
                        viewModel.saveAPIKey(key)
                        showSettings = false
                    },
                    onDelete: {
                        viewModel.deleteAPIKey()
                        showSettings = false
                    }
                )
            }
            .sheet(isPresented: $showFolderMenu) {
                FolderActionsSheet(
                    currentFolder: viewModel.currentFolder,
                    onCreateRoot: {
                        folderParent = nil
                        showFolderMenu = false
                        showFolderSheet = true
                    },
                    onCreateSubfolder: {
                        guard viewModel.currentFolder != nil else {
                            viewModel.errorMessage = "Selecciona una carpeta antes de crear una subcarpeta."
                            showFolderMenu = false
                            return
                        }
                        folderParent = viewModel.currentFolder
                        editingFolder = nil
                        showFolderMenu = false
                        showFolderSheet = true
                    },
                    onEditCurrent: {
                        guard let current = viewModel.currentFolder else { return }
                        editingFolder = current
                        folderParent = current.parentFolder
                        showFolderMenu = false
                        showFolderSheet = true
                    },
                    onGoBack: {
                        if let current = viewModel.currentFolder {
                            viewModel.currentFolder = current.parentFolder
                        }
                        showFolderMenu = false
                    },
                    onChangeSort: { sort in
                        viewModel.sortOrder = sort
                        showFolderMenu = false
                    }
                )
            }
        }
        .onAppear {
            viewModel.fetchNotes()
            viewModel.fetchFolders()
            viewModel.fetchSettings()
        }
        .alert(item: Binding(
            get: { viewModel.errorMessage.map { AlertMessage(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { alert in
            Alert(title: Text("Aviso"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var folderBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    viewModel.currentFolder = nil
                } label: {
                    HStack(spacing: 8) {
                        Text(currentFolderLabel)
                            .font(.headline.weight(.semibold))
                        Image(systemName: "folder.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)

                if let current = viewModel.currentFolder {
                    Text("/\(current.name)")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)

            let visibleFolders = viewModel.currentFolder == nil ? viewModel.rootFolders : viewModel.childFolders(of: viewModel.currentFolder)
            if !visibleFolders.isEmpty || viewModel.currentFolder == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FolderChip(title: "Todas", isActive: viewModel.currentFolder == nil) {
                            viewModel.currentFolder = nil
                        }

                        ForEach(visibleFolders) { folder in
                            FolderChip(title: folder.name, isActive: viewModel.currentFolder == folder) {
                                viewModel.currentFolder = folder
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.purple.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "note.text")
                    .font(.system(size: 52))
                    .foregroundStyle(.purple)
            }

            Text("Sin notas aún")
                .font(.title2.weight(.semibold))

            Text("Crea tu primera nota para comenzar a organizar tus ideas.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                editingNote = nil
                isShowingEditor = true
            } label: {
                Label("Nueva nota", systemImage: "plus")
                    .frame(maxWidth: 220)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(note.updatedAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(note.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !note.tagList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(note.tagList, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.14))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(height: 28)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

struct NoteDetailView: View {
    let note: Note
    @ObservedObject var viewModel: NoteViewModel
    @State private var showEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note.title)
                    .font(.largeTitle.weight(.bold))

                HStack(spacing: 16) {
                    Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(note.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "pencil")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !note.tagList.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(note.tagList, id: \.self) { tag in
                                Text(tag)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.purple.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Text(note.content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NoteEditorView(note: note, mode: .edit, selectedFolder: viewModel.currentFolder) { title, content, tags in
                let targetFolder = viewModel.currentFolder ?? viewModel.folderForNote(note)
                viewModel.updateNote(note, title: title, content: content, tags: tags, folder: targetFolder)
                showEditor = false
            }
        }
    }
}

struct NoteEditorView: View {
    let note: Note?
    let mode: EditMode
    let selectedFolder: Folder?
    let onSave: (String, String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var titleText: String = ""
    @State private var contentText: String = ""
    @State private var tagsText: String = ""

    enum EditMode {
        case new
        case edit
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .new {
                    Section("Título") {
                        TextField("Título de la nota", text: $titleText)
                    }
                }

                Section("Contenido") {
                    TextEditor(text: $contentText)
                        .frame(minHeight: 320)
                        .padding(.vertical, 4)
                }

                Section("Etiquetas") {
                    TextField("ej: trabajo, personal, ideas", text: $tagsText)
                }
            }
            .navigationTitle(mode == .new ? "Nueva nota" : "Editar nota")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(titleText, contentText, parseTags(tagsText))
                        dismiss()
                    }
                    .disabled(mode == .new && titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let note {
                titleText = note.title
                contentText = note.content
                tagsText = note.tagList.joined(separator: ", ")
            }
        }
    }

    private func parseTags(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct FolderEditorSheet: View {
    let title: String
    let parent: Folder?
    let existingFolder: Folder?
    let onSave: (String, Folder?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    init(title: String, parent: Folder?, existingFolder: Folder? = nil, onSave: @escaping (String, Folder?) -> Void) {
        self.title = title
        self.parent = parent
        self.existingFolder = existingFolder
        self.onSave = onSave
        _name = State(initialValue: existingFolder?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre de la carpeta") {
                    TextField("Ej: Trabajo", text: $name)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let finalParent = existingFolder?.parentFolder ?? parent
                        onSave(name, finalParent)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct FolderChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(width: 110, height: 72)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxHeight: 72)
            .background(isActive ? Color.purple.opacity(0.18) : Color(.secondarySystemBackground))
            .foregroundStyle(isActive ? .purple : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct FolderActionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentFolder: Folder?
    let onCreateRoot: () -> Void
    let onCreateSubfolder: () -> Void
    let onEditCurrent: () -> Void
    let onGoBack: () -> Void
    let onChangeSort: (NoteViewModel.SortOrder) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Carpetas") {
                    Button(action: onCreateRoot) {
                        Label("Nueva carpeta", systemImage: "folder.badge.plus")
                    }

                    Button(action: onCreateSubfolder) {
                        Label("Nueva subcarpeta", systemImage: "folder.fill.badge.plus")
                    }

                    if currentFolder != nil {
                        Button(action: onEditCurrent) {
                            Label("Editar carpeta", systemImage: "square.and.pencil")
                        }

                        Button(action: onGoBack) {
                            Label("Volver a la carpeta anterior", systemImage: "arrow.uturn.left")
                        }
                    }
                }

                Section("Orden") {
                    Button(action: { onChangeSort(.updatedAt); dismiss() }) {
                        Label("Fecha", systemImage: "checkmark")
                    }
                    Button(action: { onChangeSort(.alphabetical); dismiss() }) {
                        Label("Alfabético", systemImage: "textformat")
                    }
                }
            }
            .navigationTitle("Opciones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @State private var apiKey: String
    let onSave: (String) -> Void
    let onDelete: () -> Void

    init(apiKey: String, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        _apiKey = State(initialValue: apiKey)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini API Key") {
                    SecureField("Pega tu API key", text: $apiKey)
                        .textContentType(.password)
                }

                Section {
                    Button("Guardar", action: {
                        onSave(apiKey)
                    })
                    .foregroundStyle(.purple)

                    Button("Eliminar clave guardada", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle("Configuración")
        }
    }
}

struct ChatTabView: View {
    @StateObject private var viewModel: ChatViewModel

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(context: modelContext, noteContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.messages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 46))
                            .foregroundStyle(.purple)
                        Text("Habla con tu asistente de notas")
                            .font(.title3.weight(.semibold))
                        Text("Pregunta por tareas, resumenes, organizaciones o pide que genere una nota nueva.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(viewModel.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let last = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Escribe tu pregunta...", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .padding(.vertical, 6)

                    Button {
                        viewModel.sendMessage()
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Asistente IA")
            .safeAreaInset(edge: .bottom) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                Text(message.role == "user" ? "Tú" : "NotasAI")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(message.role == "user" ? .purple : .secondary)

                markdownText(message.content)
                    .padding(12)
                    .frame(maxWidth: 280, alignment: message.role == "user" ? .trailing : .leading)
                    .background(message.role == "user" ? Color.purple.opacity(0.12) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if message.role == "assistant" {
                Spacer()
            }
        }
    }

    private func markdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        }
        return Text(text)
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
