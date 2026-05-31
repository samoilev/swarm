import SwiftUI

struct ContentView: View {
    @Environment(TreeStore.self) private var store
    @State private var selectedTree: FamilyTree?
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if let tree = selectedTree {
                MainWorkspace(tree: tree, store: store, onBack: { selectedTree = nil })
            } else {
                TreeLibraryView(
                    trees: store.trees,
                    onSelect: { selectedTree = $0 },
                    onCreate: { showOnboarding = true },
                    onImport: { importGEDCOM() },
                    onRevealInFinder: { tree in
                        let url = store.gedFileURL(for: tree)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                )
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { newTree in
                store.addTree(newTree)
                selectedTree = newTree
                showOnboarding = false
            }
        }
        .onAppear {
            if store.trees.isEmpty {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTreeRequested)) { _ in
            showOnboarding = true
        }
    }
    
    private func importGEDCOM() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ged") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Выберите файл GEDCOM (.ged) для импорта"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let tree = try store.importGEDCOM(from: url)
                selectedTree = tree
            } catch {
                print("Import failed: \(error)")
            }
        }
    }
}
