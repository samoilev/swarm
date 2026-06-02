import SwiftUI
import AppKit

/// A small square preview for an attachment: the image itself for pictures,
/// otherwise a document icon with the file's format (e.g. PDF, DOCX).
struct AttachmentThumbnail: View {
    let url: URL
    let isImage: Bool
    let format: String
    var size: CGFloat = 44

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if isImage, let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5).fill(SepiaTheme.photoA.opacity(0.3))
                VStack(spacing: 1) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: size * 0.34))
                        .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                    if !format.isEmpty {
                        Text(format)
                            .font(SepiaTheme.ui(size: max(7, size * 0.16)))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
        .task(id: url) {
            guard isImage, image == nil else { return }
            let loaded = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
            image = loaded
        }
    }
}
