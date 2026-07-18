import AppKit
import FamilyTreeCore
import SwiftUI

/// Lets the user pick a portrait (3:4) rectangle from a freshly-chosen photo before it
/// becomes the card thumbnail. The selection can be moved and resized (aspect-locked);
/// `onConfirm` returns the cropped image at full resolution.
struct PhotoCropView: View {
    let image: NSImage
    var aspect: CGFloat = SepiaTheme.portraitAspect // width ÷ height
    let onCancel: () -> Void
    let onConfirm: (NSImage) -> Void

    @State private var imageFrame: CGRect = .zero // where the image is drawn (view coords)
    @State private var crop: CGRect = .zero // selection rect (same coords)
    @State private var moveStart: CGRect?
    @State private var resizeStart: CGRect?

    private let minSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("Кадрировать фото")).font(SepiaTheme.display(size: 18)).foregroundColor(SepiaTheme.ink)
                Spacer()
                Text(L10n.tr("Перетащите рамку, потяните угол для размера"))
                    .font(SepiaTheme.body(size: 11)).foregroundColor(SepiaTheme.inkSoft)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)

            Divider().overlay(SepiaTheme.toolbarLine)

            GeometryReader { geo in
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)

                    // Dim everything outside the selection.
                    Group {
                        dimBar(CGRect(x: imageFrame.minX, y: imageFrame.minY, width: imageFrame.width, height: crop.minY - imageFrame.minY))
                        dimBar(CGRect(x: imageFrame.minX, y: crop.maxY, width: imageFrame.width, height: imageFrame.maxY - crop.maxY))
                        dimBar(CGRect(x: imageFrame.minX, y: crop.minY, width: crop.minX - imageFrame.minX, height: crop.height))
                        dimBar(CGRect(x: crop.maxX, y: crop.minY, width: imageFrame.maxX - crop.maxX, height: crop.height))
                    }
                    .allowsHitTesting(false)

                    // Draggable interior.
                    Color.clear
                        .frame(width: crop.width, height: crop.height)
                        .contentShape(Rectangle())
                        .position(x: crop.midX, y: crop.midY)
                        .gesture(moveGesture)

                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: crop.width, height: crop.height)
                        .position(x: crop.midX, y: crop.midY)
                        .allowsHitTesting(false)

                    // Resize handle (bottom-right corner).
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(SepiaTheme.ink.opacity(0.3), lineWidth: 1))
                        .frame(width: 20, height: 20)
                        .position(x: crop.maxX, y: crop.maxY)
                        .gesture(resizeGesture)
                }
                .onAppear { layout(in: geo.size) }
                .onChange(of: geo.size) { _, newSize in layout(in: newSize) }
            }
            .background(Color.black.opacity(0.9))

            Divider().overlay(SepiaTheme.toolbarLine)

            HStack {
                Button(L10n.tr("Отмена")) { onCancel() }.buttonStyle(SepiaButtonStyle())
                Spacer()
                Button(L10n.tr("Готово")) { if let c = cropped() { onConfirm(c) } }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
        .background(SepiaTheme.paper)
    }

    private func dimBar(_ r: CGRect) -> some View {
        Rectangle().fill(Color.black.opacity(0.5))
            .frame(width: max(0, r.width), height: max(0, r.height))
            .position(x: r.midX, y: r.midY)
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if moveStart == nil { moveStart = crop }
                guard let s = moveStart else { return }
                var r = s
                r.origin.x = min(max(imageFrame.minX, s.minX + v.translation.width), imageFrame.maxX - s.width)
                r.origin.y = min(max(imageFrame.minY, s.minY + v.translation.height), imageFrame.maxY - s.height)
                crop = r
            }
            .onEnded { _ in moveStart = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if resizeStart == nil { resizeStart = crop }
                guard let s = resizeStart else { return }
                let maxW = min(imageFrame.maxX - s.minX, (imageFrame.maxY - s.minY) * aspect)
                let w = min(max(minSize, s.width + v.translation.width), maxW)
                crop = CGRect(x: s.minX, y: s.minY, width: w, height: w / aspect)
            }
            .onEnded { _ in resizeStart = nil }
    }

    /// Aspect-fit the image into `size` and seed a centered selection.
    private func layout(in size: CGSize) {
        guard image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0 else { return }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        let frame = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        imageFrame = frame
        // Largest centered 3:4 rect that fits the image, at 90%.
        var cw = frame.width, ch = cw / aspect
        if ch > frame.height { ch = frame.height; cw = ch * aspect }
        cw *= 0.9; ch *= 0.9
        crop = CGRect(x: frame.midX - cw / 2, y: frame.midY - ch / 2, width: cw, height: ch)
    }

    /// Crop the source image (full resolution) to the selection.
    private func cropped() -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              imageFrame.width > 0, imageFrame.height > 0 else { return nil }
        let sx = CGFloat(cg.width) / imageFrame.width
        let sy = CGFloat(cg.height) / imageFrame.height
        let rect = CGRect(
            x: (crop.minX - imageFrame.minX) * sx,
            y: (crop.minY - imageFrame.minY) * sy,
            width: crop.width * sx,
            height: crop.height * sy
        ).integral
        guard let out = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }
}
