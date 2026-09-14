import AppKit
import SwarmCore
import SwiftUI

/// The person's pictures as a scrollable row of miniatures: the portrait first, then
/// every image attachment. It only appears when there is more than one — a lone
/// portrait is already the largest thing in the header, and a strip repeating it would
/// be a scroller with nothing to scroll.
///
/// Tiles share a height and keep their own width. Family photos arrive in whatever
/// shape the camera or the scanner left them in, and cropping them all to one aspect
/// is how a group photograph becomes three faces and a shoulder.
struct PersonPhotoStrip: View {
    let person: Person
    let tree: FamilyTree
    var store: TreeStore
    var onOpen: (Int) -> Void

    private let height: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(Array(person.photoRefs.enumerated()), id: \.element.id) { index, ref in
                    Button { onOpen(index) } label: {
                        PhotoTile(person: person, ref: ref, url: url(for: ref), height: height)
                    }
                    .buttonStyle(.plain)
                    .help(label(for: ref))
                    .accessibilityLabel(label(for: ref))
                }
            }
        }
        .frame(height: height)
    }

    private func url(for ref: PersonPhotoRef) -> URL? {
        guard case let .attachment(attachment) = ref else { return nil }
        return store.attachmentURL(attachment, in: tree)
    }

    private func label(for ref: PersonPhotoRef) -> String {
        switch ref {
        case .portrait: L10n.tr("Открыть фото")
        case let .attachment(attachment): L10n.tr("Открыть «\(attachment.originalName)»")
        }
    }
}

private struct PhotoTile: View {
    let person: Person
    let ref: PersonPhotoRef
    let url: URL?
    let height: CGFloat

    @State private var image: NSImage?

    private let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                SepiaTheme.photoA.opacity(0.35)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
        .sepiaMotion(SepiaMotion.state, value: image != nil)
        // Keyed on the person and the portrait's revision as well as the picture: every
        // portrait tile has the same identity, so walking from one record to the next
        // reuses this view, and a key of `ref` alone would leave the old face in it.
        .task(id: "\(person.id)-\(ref.id)-\(person.photoRevision)") { image = await load() }
    }

    /// A portrait-shaped placeholder until the file says otherwise, so the row does not
    /// reflow from nothing as the tiles land.
    private var width: CGFloat {
        guard let image, image.size.height > 0 else { return height * SepiaTheme.portraitAspect }
        // ponytail: clamped, so one panorama can't take the whole strip on its own.
        return height * min(2, max(0.5, image.size.width / image.size.height))
    }

    private func load() async -> NSImage? {
        switch ref {
        case .portrait:
            // Already downsampled and cached for the canvas cards; a second reader is free.
            return PortraitThumbnail.image(for: person)
        case .attachment:
            guard let url else { return nil }
            return await Task.detached(priority: .utility) { PortraitThumbnail.image(url: url) }.value
        }
    }
}
