import SwiftUI
import UniformTypeIdentifiers

/// Minimal in-memory document wrapper so already-rendered bytes (PNG/PDF) can be
/// written through the native `.fileExporter` modifier.
struct RenderedFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.png, .pdf]
    }

    var data: Data
    var type: UTType

    init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        self.type = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
