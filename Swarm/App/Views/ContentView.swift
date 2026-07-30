import SwarmCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(TreeStore.self) private var store
    @AppStorage(AppLanguage.choiceCompletedKey) private var languageChoiceCompleted = false
    @State private var selectedTree: FamilyTree?
    @State private var showOnboarding = false
    @State private var showGEDCOMImporter = false
    @State private var importError: String?
    @State private var pendingImportURL: URL?
    @State private var importPreview: ImportResult?
    @State private var queuedOpenURL: URL?
    /// Confirmation the workspace shows once, on arrival, for a tree that was just
    /// written. Creating a whole family record used to be the app's only silent write.
    @State private var pendingToast: String?
    @State private var showHelp = false

    private var gedcomType: UTType {
        UTType(filenameExtension: "ged") ?? .plainText
    }

    var body: some View {
        Group {
            if !languageChoiceCompleted {
                LanguageChooserView()
            } else if let tree = selectedTree {
                MainWorkspace(
                    tree: tree,
                    store: store,
                    initialToast: pendingToast,
                    onBack: {
                        selectedTree = nil
                        pendingToast = nil
                    }
                )
            } else {
                TreeLibraryView(
                    trees: store.trees,
                    onSelect: { selectedTree = $0 },
                    onCreate: { showOnboarding = true },
                    onImport: { showGEDCOMImporter = true },
                    onRevealInFinder: { tree in
                        let url = store.gedFileURL(for: tree)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                )
            }
        }
        // The sheet reports its own failures inline and dismisses itself on success, so
        // a write that fails no longer surfaces as an *import* error over a live form.
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { newTree in
                _ = try await store.addTreeVerified(newTree)
                pendingToast = L10n.tr("Дерево «\(newTree.name)» создано")
                selectedTree = newTree
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        // No auto-presented sheet on an empty library. The empty state itself offers
        // both ways in (create and import), which a modal that appears before the user
        // has seen the app cannot do.
        .onReceive(NotificationCenter.default.publisher(for: .newTreeRequested)) { _ in
            if languageChoiceCompleted { showOnboarding = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTreeRequested)) { note in
            guard let id = note.object as? UUID,
                  let tree = store.trees.first(where: { $0.id == id }) else { return }
            selectedTree = tree
        }
        .onReceive(NotificationCenter.default.publisher(for: .helpRequested)) { _ in
            showHelp = true
        }
        .onChange(of: languageChoiceCompleted) { _, completed in
            guard completed, let url = queuedOpenURL else { return }
            queuedOpenURL = nil
            previewGEDCOM(from: url)
        }
        // Folders are selectable too: an exported archive is a folder, and choosing it —
        // rather than the .ged buried inside — is what lets macOS read the photos and
        // attachments stored beside the file.
        .fileImporter(isPresented: $showGEDCOMImporter, allowedContentTypes: [gedcomType, .folder]) { result in
            switch result {
            case .success(let url): previewGEDCOM(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(
            get: { importPreview != nil },
            set: { if !$0 { cancelImportPreview() } }
        )) {
            if let importPreview {
                ImportPreviewView(result: importPreview, onCancel: cancelImportPreview, onImport: commitImportPreview)
            }
        }
        .onOpenURL { url in
            if languageChoiceCompleted {
                previewGEDCOM(from: url)
            } else {
                queuedOpenURL = url
            }
        }
        .alert(L10n.tr("Не удалось импортировать файл"), isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func previewGEDCOM(from url: URL) {
        // The scope has to stay open across staging, not just the read of the .ged
        // itself: a folder selection is what carries access to Media/ and Attachments/.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let source = try store.resolveImportSource(url)
            let localCopy = try store.prepareImportPreview(from: source)
            var result = try GEDCOMCodec.parse(localCopy)
            result.report.diagnostics.append(contentsOf: store.stagedImportDiagnostics(for: localCopy))
            pendingImportURL = localCopy
            importPreview = result
        } catch {
            importError = importFailureMessage(error)
        }
    }

    /// A file the app was not allowed to read is not a damaged file, and saying so sends
    /// the reader off to repair an archive that is perfectly intact.
    private func importFailureMessage(_ error: Error) -> String {
        if let storeError = error as? TreeStoreError, let description = storeError.errorDescription {
            return description
        }
        let nsError = error as NSError
        let denied = nsError.domain == NSCocoaErrorDomain &&
            (nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError)
        if denied {
            return L10n.tr(
                "Нет доступа к этому файлу. Выберите папку архива целиком — тогда macOS разрешит прочитать и фотографии с вложениями рядом с ним.\n\n\(error.localizedDescription)"
            )
        }
        return L10n.tr("Файл повреждён или имеет неподдерживаемый формат.\n\n\(error.localizedDescription)")
    }

    private func commitImportPreview() {
        guard let url = pendingImportURL else { return }
        Task { @MainActor in
            do {
                let result = try await store.importGEDCOM(from: url)
                store.discardImportPreview(at: url)
                pendingImportURL = nil
                importPreview = nil
                selectedTree = result.tree
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func cancelImportPreview() {
        if let pendingImportURL { store.discardImportPreview(at: pendingImportURL) }
        pendingImportURL = nil
        importPreview = nil
    }
}
