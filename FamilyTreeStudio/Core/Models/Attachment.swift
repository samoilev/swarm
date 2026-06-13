import Foundation

/// A file attached to a person. Only metadata lives in the model — the bytes are
/// stored strictly locally on disk inside the tree's `Attachments/` folder.
public struct Attachment: Identifiable, Codable, Hashable {
    public var id: UUID
    /// Filename on disk inside `<tree>/Attachments/`, e.g. "<uuid>.pdf".
    /// A UUID-based name avoids collisions between files sharing an original name.
    public var storedName: String
    /// Original name as chosen by the user, used for display, e.g. "Свидетельство.pdf".
    public var originalName: String

    public init(id: UUID = UUID(), storedName: String, originalName: String) {
        self.id = id
        self.storedName = storedName
        self.originalName = originalName
    }

    /// Uppercased file extension for display, e.g. "PDF". Empty if the name has none.
    public var format: String {
        (originalName as NSString).pathExtension.uppercased()
    }

    /// Whether this attachment is an image and should be shown as a thumbnail.
    public var isImage: Bool {
        let ext = (originalName as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"].contains(ext)
    }
}
