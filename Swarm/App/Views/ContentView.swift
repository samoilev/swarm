import SwarmCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// Where the window is. Creating a tree is a destination now, not a sheet: the design
    /// gives it the whole window, with the card it will produce drawn live beside the form.
    private enum Destination: Equatable {
        case library
        case creating
        case workspace(FamilyTree)

        static func == (lhs: Destination, rhs: Destination) -> Bool {
            switch (lhs, rhs) {
            case (.library, .library), (.creating, .creating): true
            case let (.workspace(a), .workspace(b)): a.id == b.id
            default: false
            }
        }
    }

    @Environment(TreeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppLanguage.choiceCompletedKey) private var languageChoiceCompleted = false
    @State private var destination: Destination = .library
    /// The card whose diagram hands its geometry to the canvas while a tree opens.
    @State private var morphingTreeID: UUID?
    @Namespace private var treeMorph
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
        // A ZStack rather than a Group: the outgoing and incoming screens have to be in the
        // hierarchy together for one beat, or the card opening into a tree has nothing to
        // hand its geometry to.
        ZStack {
            if !languageChoiceCompleted {
                LanguageChooserView()
                    .transition(.opacity)
            } else {
                switch destination {
                case .workspace(let tree):
                    MainWorkspace(
                        tree: tree,
                        store: store,
                        initialToast: pendingToast,
                        morphNamespace: treeMorph,
                        morphingTreeID: morphingTreeID,
                        onBack: {
                            pendingToast = nil
                            navigate(to: .library)
                        }
                    )
                    // The crossfade runs on its own short clock while the surrounding
                    // transaction stays on the long spring. Without that split the canvas
                    // is still transparent for the whole of the morph and the one authored
                    // moment in the app happens where nobody can see it.
                    .transition(.opacity.animation(SepiaMotion.crossfade))

                case .creating:
                    // The write reports its own failures inline and leaves the form live,
                    // so a failed save no longer surfaces as an *import* error.
                    OnboardingView(
                        onCancel: { navigate(to: .library) },
                        onComplete: { newTree in
                            _ = try await store.addTreeVerified(newTree)
                            pendingToast = L10n.tr("Дерево «\(newTree.name)» создано")
                        },
                        onOpen: { newTree in open(newTree) }
                    )
                    .transition(.opacity)

                case .library:
                    TreeLibraryView(
                        trees: store.trees,
                        onSelect: { open($0) },
                        onCreate: { navigate(to: .creating) },
                        onImport: { showGEDCOMImporter = true },
                        onRevealInFinder: { tree in
                            let url = store.gedFileURL(for: tree)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        },
                        morphNamespace: treeMorph,
                        morphingTreeID: morphingTreeID
                    )
                    // Leaving, the library pulls very slightly toward the reader as it
                    // fades — the prototype's own gesture. It reads as diving into the
                    // card rather than as one picture being swapped for another.
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 1.06))
                        )
                        .animation(SepiaMotion.crossfade)
                    )
                }
            }
        }
        .sepiaMotion(SepiaMotion.crossfade, value: languageChoiceCompleted)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        // No auto-presented sheet on an empty library. The empty state itself offers
        // both ways in (create and import), which a modal that appears before the user
        // has seen the app cannot do.
        .onReceive(NotificationCenter.default.publisher(for: .openTreeRequested)) { note in
            guard let id = note.object as? UUID,
                  let tree = store.trees.first(where: { $0.id == id }) else { return }
            open(tree)
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

    /// The app's one authored moment. A card carries a small drawing of its tree, so
    /// opening it hands those nodes to the real cards on the canvas and the rest of the
    /// record fans in around them — rather than cutting from one screen to another.
    ///
    /// Under Reduce Motion it is a plain swap, and the morph is skipped entirely: matched
    /// geometry with no animation to carry it would snap.
    private func open(_ tree: FamilyTree) {
        guard !reduceMotion else {
            morphingTreeID = nil
            destination = .workspace(tree)
            return
        }
        morphingTreeID = tree.id
        withAnimation(SepiaMotion.layout) { destination = .workspace(tree) }
        // Release the morph once it has settled. Cards that keep publishing geometry for a
        // transition that finished will fight the canvas the next time the layout moves.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if case .workspace(let current) = destination, current.id == tree.id {
                morphingTreeID = nil
            }
        }
    }

    /// Every other screen change is a crossfade — the library and the new-tree flow are two
    /// rooms in one window, not two places on a map.
    private func navigate(to next: Destination) {
        morphingTreeID = nil
        if reduceMotion {
            destination = next
        } else {
            withAnimation(SepiaMotion.crossfade) { destination = next }
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
                open(result.tree)
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
