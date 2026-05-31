import Foundation

/// GEDCOM-based persistence for family trees.
/// Each tree is stored as a separate .ged file in ~/Library/Application Support/FamilyTreeStudio/
/// Photos are stored in a Media/ subfolder next to each .ged file.
@Observable
final class TreeStore {
    var trees: [FamilyTree] = []
    
    private let storageFolder: URL
    
    /// Maps tree UUID → .ged file URL for saving back
    private var fileMap: [UUID: URL] = [:]
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("FamilyTreeStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        storageFolder = appFolder
        load()
    }
    
    // MARK: - Load all .ged files from storage folder
    
    func load() {
        trees = []
        fileMap = [:]
        
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: nil) else { return }
        
        let gedFiles = files.filter { $0.pathExtension.lowercased() == "ged" }
        
        for url in gedFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let parsed = try GEDCOMParser.parse(from: url)
                let tree = FamilyTree(name: parsed.name, subtitle: parsed.subtitle)
                // Use filename (without extension) as a stable identifier
                // Preserve tree UUID from filename if it's a UUID
                let stem = url.deletingPathExtension().lastPathComponent
                if let existingId = UUID(uuidString: stem) {
                    tree.id = existingId
                }
                tree.homePersonId = parsed.homePersonId
                tree.rootUnionId = parsed.rootUnionId
                tree.people = parsed.people
                tree.unions = parsed.unions
                
                trees.append(tree)
                fileMap[tree.id] = url
            } catch {
                print("Failed to load \(url.lastPathComponent): \(error)")
            }
        }
        
        // Migration: if old JSON exists and no .ged files, import it
        let legacyURL = storageFolder.appendingPathComponent("trees.json")
        if trees.isEmpty && fm.fileExists(atPath: legacyURL.path) {
            migrateFromJSON(legacyURL)
        }
    }
    
    // MARK: - Save a specific tree to its .ged file
    
    func save() {
        for tree in trees {
            saveTree(tree)
        }
    }
    
    func saveTree(_ tree: FamilyTree) {
        tree.updatedAt = Date()
        let url = fileURL(for: tree)
        let mediaFolder = storageFolder.appendingPathComponent("Media_\(tree.id.uuidString)", isDirectory: true)
        let content = GEDCOMSerializer.serialize(tree: tree, mediaFolder: mediaFolder)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            fileMap[tree.id] = url
        } catch {
            print("Failed to save tree \(tree.name): \(error)")
        }
    }
    
    func addTree(_ tree: FamilyTree) {
        trees.append(tree)
        saveTree(tree)
    }
    
    func deleteTree(_ tree: FamilyTree) {
        trees.removeAll(where: { $0.id == tree.id })
        // Remove .ged file
        if let url = fileMap[tree.id] {
            try? FileManager.default.removeItem(at: url)
            fileMap.removeValue(forKey: tree.id)
        }
        // Remove media folder
        let mediaFolder = storageFolder.appendingPathComponent("Media_\(tree.id.uuidString)")
        try? FileManager.default.removeItem(at: mediaFolder)
    }
    
    // MARK: - Import external .ged file
    
    func importGEDCOM(from url: URL) throws -> FamilyTree {
        let parsed = try GEDCOMParser.parse(from: url)
        let tree = FamilyTree(name: parsed.name, subtitle: parsed.subtitle)
        tree.homePersonId = parsed.homePersonId
        tree.rootUnionId = parsed.rootUnionId
        tree.people = parsed.people
        tree.unions = parsed.unions
        addTree(tree)
        return tree
    }
    
    // MARK: - Export .ged to a user-chosen location
    
    func exportGEDCOM(tree: FamilyTree, to url: URL) {
        let mediaFolder = url.deletingLastPathComponent().appendingPathComponent("Media", isDirectory: true)
        let content = GEDCOMSerializer.serialize(tree: tree, mediaFolder: mediaFolder)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Helpers
    
    /// Public access to the .ged file path for a tree
    func gedFileURL(for tree: FamilyTree) -> URL {
        fileURL(for: tree)
    }
    
    private func fileURL(for tree: FamilyTree) -> URL {
        if let existing = fileMap[tree.id] { return existing }
        return storageFolder.appendingPathComponent("\(tree.id.uuidString).ged")
    }
    
    // MARK: - Legacy JSON Migration
    
    private func migrateFromJSON(_ jsonURL: URL) {
        do {
            let data = try Data(contentsOf: jsonURL)
            let oldTrees = try JSONDecoder().decode([FamilyTree].self, from: data)
            for tree in oldTrees {
                trees.append(tree)
                saveTree(tree)
            }
            // Rename old file as backup
            let backup = jsonURL.appendingPathExtension("bak")
            try? FileManager.default.moveItem(at: jsonURL, to: backup)
            print("Migrated \(oldTrees.count) tree(s) from JSON to GEDCOM")
        } catch {
            print("JSON migration failed: \(error)")
        }
    }
}

