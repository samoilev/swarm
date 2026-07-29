import AppKit
import CoreGraphics
import CoreText
import SwarmCore
import SwiftUI

/// Renders every person as their own card, sorted alphabetically by name, one card
/// per page (A4 portrait). A card whose content overflows continues onto further
/// pages; the next person always begins on a fresh page.
struct PersonCardsPDFExporter {
    private static let pageW: CGFloat = 595 // A4 portrait @ 72 dpi
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 48
    private static let footerBaseline: CGFloat = 30 // y of footer text
    private static let bodyBottom: CGFloat = 50 // text never drops below this y

    /// `selectedIds` nil or empty → the whole tree. Otherwise only those people are
    /// included (cards) and the diagram page is limited to that subset.
    static func render(tree: FamilyTree, selectedIds: Set<UUID>? = nil, showPhotos: Bool = true, attachmentsFolder: URL? = nil) -> Data? {
        let scopeIds = (selectedIds?.isEmpty == false) ? selectedIds : nil
        let scoped = scopeIds.map { ids in tree.people.filter { ids.contains($0.id) } } ?? tree.people
        let people = scoped.sorted {
            $0.sortName(language: .current) < $1.sortName(language: .current)
        }
        guard !people.isEmpty else { return nil }

        let pdfData = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        let idx = FamilyIndex(tree: tree)
        let contentW = pageW - margin * 2

        // Page 1: the tree (or selected part) drawn as a 90°-rotated diagram.
        drawTreePoster(tree: tree, scopeIds: scopeIds, showPhotos: showPhotos, ctx: ctx, box: box)

        // Following pages: one alphabetical card per person in scope.
        drawPersonCards(people: people, idx: idx, ctx: ctx, box: box, contentW: contentW, attachmentsFolder: attachmentsFolder)

        ctx.closePDF()
        return pdfData as Data
    }

    private static func drawPersonCards(people: [Person], idx: FamilyIndex, ctx: CGContext, box: CGRect, contentW: CGFloat, attachmentsFolder: URL?) {
        for person in people {
            let body = makeBody(for: person, idx: idx)
            let framesetter = CTFramesetterCreateWithAttributedString(body)
            let total = body.length
            var location = 0
            var firstPage = true
            var stalls = 0

            repeat {
                ctx.beginPDFPage(nil)
                let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx

                drawBackground(ctx, box: box)
                drawBorder(ctx)

                let topY = firstPage
                    ? drawHeader(person, ctx: ctx, textWidth: contentW)
                    : drawContinuationHeader(person, textWidth: contentW)

                var advanced = 0
                if total > 0 && topY > bodyBottom {
                    let textRect = CGRect(x: margin, y: bodyBottom, width: contentW, height: topY - bodyBottom)
                    let path = CGMutablePath(); path.addRect(textRect)
                    ctx.textMatrix = .identity
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                    CTFrameDraw(frame, ctx)
                    advanced = CTFrameGetVisibleStringRange(frame).length
                    location += advanced
                }

                drawFooter(person)

                NSGraphicsContext.restoreGraphicsState()
                ctx.endPDFPage()
                firstPage = false

                // If a page fit nothing (e.g. a tall first-page header left no room),
                // spill onto a continuation page rather than dropping the rest. Bail only
                // if two pages in a row make no progress, to avoid an infinite loop.
                if total > 0 && advanced == 0 {
                    stalls += 1
                    if stalls >= 2 { break }
                } else {
                    stalls = 0
                }
            } while location < total

            // After the text, render any attached images full-size on their own page(s).
            renderImages(loadImages(for: person, in: attachmentsFolder),
                         ctx: ctx, box: box, person: person, contentW: contentW)
        }
    }

    // MARK: - Tree diagram (page 1)

    /// Draws the whole tree — or just `scopeIds` — as one page, rotated 90° so a wide
    /// pedigree uses the portrait page's long edge. The diagram is the real on-screen
    /// `PersonCardView` drawn through `ImageRenderer.render` straight into the PDF
    /// context, so cards/text stay **vector** (crisp at any zoom); only embedded photos
    /// rasterize. The 90° turn is baked into the SwiftUI view, not the CG matrix.
    private static func drawTreePoster(tree: FamilyTree, scopeIds: Set<UUID>?, showPhotos: Bool, ctx: CGContext, box: CGRect) {
        let layout = TreeLayoutEngine().layout(tree: tree, direction: .topDown)
        let nodes = scopeIds.map { ids in layout.nodes.filter { ids.contains($0.person.id) } } ?? layout.nodes
        guard !nodes.isEmpty else { return }
        let links: [TreeLink] = if let scopeIds {
            // A scoped export follows exact relationship routes instead of pulling
            // an unrelated section of a shared sibling bus into the poster.
            layout.highlightRoutes
                .filter { route in
                    route.connections.contains {
                        scopeIds.contains($0.firstID) && scopeIds.contains($0.secondID)
                    }
                }
                .map { TreeLink(id: $0.id, segments: $0.segments) }
        } else {
            layout.links
        }

        let cardW: CGFloat = 210, cardH: CGFloat = 90
        let minX = nodes.map(\.x).min()!
        let minY = nodes.map(\.y).min()!
        let treeW = nodes.map { $0.x + cardW }.max()! - minX
        let treeH = nodes.map { $0.y + cardH }.max()! - minY
        guard treeW > 0, treeH > 0 else { return }

        ctx.beginPDFPage(nil)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsCtx.imageInterpolation = .high

        drawBackground(ctx, box: box)
        drawBorder(ctx)

        // Title near the top (drawn in normal, un-rotated page space).
        let title = scopeIds == nil ? (tree.name.isEmpty ? L10n.tr("Дерево") : tree.name) : L10n.tr("Выделенная часть дерева")
        let titleStr = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor(SepiaTheme.ink)
        ])
        let titleH = titleStr.size().height
        let titleTopY = pageH - margin - titleH
        titleStr.draw(at: NSPoint(x: margin, y: titleTopY))

        // Content area below the title, above the bottom margin.
        let availW = pageW - margin * 2
        let availH = (titleTopY - 12) - bodyBottom
        guard availW > 0, availH > 0 else {
            NSGraphicsContext.restoreGraphicsState(); ctx.endPDFPage(); return
        }

        // The tree turned 90° in SwiftUI: its bounding box becomes treeH × treeW.
        let poster = TreePosterView(
            nodes: nodes, links: links,
            canvasSize: CGSize(width: treeW, height: treeH),
            originX: minX, originY: minY, showPhotos: showPhotos
        )
        .rotationEffect(.degrees(270))
        .frame(width: treeH, height: treeW)

        let scale = min(availW / treeH, availH / treeW)
        let drawW = treeH * scale, drawH = treeW * scale
        let ox = (pageW - drawW) / 2
        let oy = bodyBottom + (availH - drawH) / 2

        MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: poster)
            renderer.isOpaque = false
            // Vector for text/shapes; only photos rasterize — keep them crisp.
            renderer.render(rasterizationScale: 3) { _, draw in
                ctx.saveGState()
                ctx.translateBy(x: ox, y: oy)
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
                ctx.restoreGState()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }

    // MARK: - Page chrome

    private static func drawBackground(_ ctx: CGContext, box: CGRect) {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(box)
    }

    private static func drawBorder(_ ctx: CGContext) {
        ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: 24, y: 24, width: pageW - 48, height: pageH - 48))
    }

    private static func drawFooter(_ person: Person) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5),
            .foregroundColor: NSColor(SepiaTheme.inkSoft)
        ]
        NSAttributedString(string: person.displayName(language: .current), attributes: attr)
            .draw(at: NSPoint(x: margin, y: footerBaseline))
        let brand = NSAttributedString(string: L10n.tr("Swarm"), attributes: attr)
        brand.draw(at: NSPoint(x: pageW - margin - brand.size().width, y: footerBaseline))
    }

    // MARK: - Headers (return the y below which the body text may start)

    private static func drawHeader(_ person: Person, ctx: CGContext, textWidth: CGFloat) -> CGFloat {
        let topEdge = pageH - margin
        let photoH: CGFloat = 96
        let photoW: CGFloat = photoH * SepiaTheme.portraitAspect // 3:4 portrait, matches the app
        var textX = margin

        if let data = person.photoData, let img = NSImage(data: data) {
            let rect = NSRect(x: margin, y: topEdge - photoH, width: photoW, height: photoH)
            let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            drawImageAspectFill(img, in: rect)
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor); ctx.setLineWidth(1); ctx.strokePath()
            textX = margin + photoW + 16
        }

        let textW = pageW - margin - textX
        var cursorY = topEdge

        let nameStr = NSAttributedString(string: person.displayName(language: .current), attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor(SepiaTheme.ink)
        ])
        let nameH = textHeight(nameStr, width: textW)
        nameStr.draw(in: NSRect(x: textX, y: cursorY - nameH, width: textW, height: nameH))
        cursorY -= nameH + 3

        if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
            let s = NSAttributedString(string: L10n.tr("урожд. \(maiden)"), attributes: [
                .font: NSFont.systemFont(ofSize: 12).withItalic(),
                .foregroundColor: NSColor(SepiaTheme.inkSoft)
            ])
            let h = textHeight(s, width: textW)
            s.draw(in: NSRect(x: textX, y: cursorY - h, width: textW, height: h))
            cursorY -= h + 2
        }

        if !person.lifespan.isEmpty {
            let s = NSAttributedString(string: person.lifespan, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(SepiaTheme.inkSoft)
            ])
            let h = textHeight(s, width: textW)
            s.draw(in: NSRect(x: textX, y: cursorY - h, width: textW, height: h))
            cursorY -= h
        }

        // Rule under whichever is taller — the photo or the text block.
        let blockBottom = min(cursorY, person.photoData != nil ? topEdge - photoH : cursorY)
        let ruleY = blockBottom - 12
        ctx.setStrokeColor(NSColor(SepiaTheme.accent2).withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: ruleY)); ctx.addLine(to: CGPoint(x: pageW - margin, y: ruleY)); ctx.strokePath()
        return ruleY - 14
    }

    private static func drawContinuationHeader(_ person: Person, suffix: String = L10n.tr("продолжение"), textWidth: CGFloat) -> CGFloat {
        let topEdge = pageH - margin
        let s = NSAttributedString(
            string: "\(person.displayName(language: .current)) — \(suffix)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11).withItalic(),
                .foregroundColor: NSColor(SepiaTheme.inkSoft)
            ]
        )
        let h = textHeight(s, width: textWidth)
        s.draw(in: NSRect(x: margin, y: topEdge - h, width: textWidth, height: h))
        let ruleY = topEdge - h - 8
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor); ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: ruleY)); ctx.addLine(to: CGPoint(x: pageW - margin, y: ruleY)); ctx.strokePath()
        }
        return ruleY - 12
    }

    // MARK: - Body content

    private static func makeBody(for p: Person, idx: FamilyIndex) -> NSAttributedString {
        let ink = NSColor(SepiaTheme.ink)
        let soft = NSColor(SepiaTheme.inkSoft)
        let accent = NSColor(SepiaTheme.accent2)

        let sectionPara = NSMutableParagraphStyle(); sectionPara.paragraphSpacingBefore = 15; sectionPara.paragraphSpacing = 5
        let labelPara = NSMutableParagraphStyle(); labelPara.paragraphSpacingBefore = 7; labelPara.paragraphSpacing = 1
        let valuePara = NSMutableParagraphStyle(); valuePara.paragraphSpacing = 2; valuePara.lineSpacing = 1

        let result = NSMutableAttributedString()

        func section(_ title: String) {
            result.append(NSAttributedString(string: title.uppercased() + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: accent,
                .kern: 1.5, .paragraphStyle: sectionPara
            ]))
        }
        func field(_ label: String, _ value: String?) {
            guard let v = value, !v.isEmpty else { return }
            result.append(NSAttributedString(string: label.uppercased() + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 9), .foregroundColor: soft, .kern: 1.0, .paragraphStyle: labelPara
            ]))
            result.append(NSAttributedString(string: v + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: ink, .paragraphStyle: valuePara
            ]))
        }
        func bullet(_ text: String) {
            result.append(NSAttributedString(string: "•  " + text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink, .paragraphStyle: valuePara
            ]))
        }
        func date(_ kind: GenealogyEvent.Kind, fallback: String?) -> String? {
            if let value = p.event(ofKind: kind)?.date {
                return value.displayValue(language: .current)
            }
            guard let fallback, !fallback.isEmpty else { return nil }
            return FamilyDate.parse(fallback).displayString(language: .current)
        }
        func place(_ kind: GenealogyEvent.Kind, fallback: String?) -> String? {
            if let reference = p.event(ofKind: kind)?.place {
                return PlacesDatabase.shared.presentationName(for: reference, language: .current)
            }
            return fallback
        }

        section(L10n.tr("Личность"))
        field(L10n.tr("Имя"), p.givenNames)
        field(L10n.tr("Отчество"), p.patronymic)
        field(L10n.tr("Фамилия"), p.surname)
        field(L10n.tr("Девичья фамилия"), p.maidenName)
        field(L10n.tr("Пол"), p.sex.displayName)

        if p.birthDate?.isEmpty == false || p.birthPlace?.isEmpty == false {
            section(L10n.tr("Рождение"))
            field(L10n.tr("Дата"), date(.birth, fallback: p.birthDate))
            field(L10n.tr("Место"), place(.birth, fallback: p.birthPlace))
        }

        let hasBurial = (p.burialPlace?.isEmpty == false) || (p.burialLat != nil && p.burialLon != nil)
        if !p.isLiving || hasBurial {
            section(L10n.tr("Смерть и погребение"))
            if !p.isLiving {
                field(L10n.tr("Дата смерти"), date(.death, fallback: p.deathDate))
                field(L10n.tr("Место смерти"), place(.death, fallback: p.deathPlace))
            }
            field(L10n.tr("Место захоронения"), place(.burial, fallback: p.burialPlace))
            if let lat = p.burialLat, let lon = p.burialLon {
                field(L10n.tr("Координаты могилы"), String(format: "%.5f, %.5f", lat, lon))
            }
        }

        if p.occupation?.isEmpty == false || p.education?.isEmpty == false || p.notes?.isEmpty == false {
            section(L10n.tr("Жизнь"))
            field(L10n.tr("Профессия"), p.occupation)
            field(L10n.tr("Образование"), p.education)
            field(L10n.tr("Заметки"), p.notes)
        }

        if !p.attachments.isEmpty {
            section(L10n.tr("Файлы"))
            for a in p.attachments {
                let fmt = a.format.isEmpty ? "" : " (\(a.format))"
                bullet(a.originalName + fmt)
            }
        }

        let parents = idx.parentsOf(p)
        let spouses = idx.spousesOf(p)
        let children = idx.childrenOf(p)
        let siblings = idx.siblingsOf(p)
        if parents.father != nil || parents.mother != nil || !spouses.isEmpty || !children.isEmpty || !siblings.isEmpty {
            section(L10n.tr("Родственные связи"))
            field(L10n.tr("Отец"), parents.father?.displayName(language: .current))
            field(L10n.tr("Мать"), parents.mother?.displayName(language: .current))
            if !spouses.isEmpty {
                field(
                    L10n.tr("Супруг(и)"),
                    spouses.map { $0.displayName(language: .current) }.joined(separator: ", ")
                )
            }
            if !children.isEmpty {
                field(
                    L10n.tr("Дети"),
                    children.map { $0.displayName(language: .current) }.joined(separator: ", ")
                )
            }
            if !siblings.isEmpty {
                field(
                    L10n.tr("Братья/сёстры"),
                    siblings.map { $0.displayName(language: .current) }.joined(separator: ", ")
                )
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func textHeight(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    /// Load the person's image attachments (full resolution) from the tree's folder.
    private static func loadImages(for person: Person, in folder: URL?) -> [(img: NSImage, name: String)] {
        guard let folder else { return [] }
        var result: [(NSImage, String)] = []
        for a in person.attachments where a.isImage {
            if let img = NSImage(contentsOf: folder.appendingPathComponent(a.storedName)) {
                result.append((img, a.originalName))
            }
        }
        return result
    }

    /// Draw each image attachment full-size (aspect-fit to the page, no cropping or
    /// downsampling) with its filename, flowing onto continuation pages as needed.
    private static func renderImages(_ images: [(img: NSImage, name: String)],
                                     ctx: CGContext, box: CGRect, person: Person, contentW: CGFloat) {
        guard !images.isEmpty else { return }
        let topStart = pageH - margin
        let captionH: CGFloat = 14
        let gap: CGFloat = 14
        let freshAvail = topStart - 36 - bodyBottom // usable height on a continuation page
        var cursorY: CGFloat = 0
        var pageOpen = false
        var placedOnPage = false

        func startPage() {
            ctx.beginPDFPage(nil)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            nsCtx.imageInterpolation = .high
            drawBackground(ctx, box: box)
            drawBorder(ctx)
            cursorY = drawContinuationHeader(person, suffix: L10n.tr("изображения"), textWidth: contentW)
            pageOpen = true
            placedOnPage = false
        }
        func endPage() {
            drawFooter(person)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
            pageOpen = false
        }

        startPage()
        for (img, name) in images {
            let sz = img.size
            guard sz.width > 0, sz.height > 0 else { continue }
            // Aspect-fit to the content width, capped so a block always fits one page.
            var dw = contentW
            var dh = contentW * sz.height / sz.width
            let maxImgH = freshAvail - captionH - gap
            if dh > maxImgH { dw *= maxImgH / dh; dh = maxImgH }
            let blockH = dh + captionH + gap

            if placedOnPage && blockH > (cursorY - bodyBottom) {
                endPage(); startPage()
            }

            let imgRect = NSRect(x: margin + (contentW - dw) / 2, y: cursorY - dh, width: dw, height: dh)
            img.draw(in: imgRect, from: .zero, operation: .copy, fraction: 1.0)

            let caption = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor(SepiaTheme.inkSoft)
            ])
            caption.draw(at: NSPoint(x: margin + (contentW - caption.size().width) / 2, y: cursorY - dh - captionH + 2))

            cursorY -= blockH
            placedOnPage = true
        }
        if pageOpen { endPage() }
    }

    private static func drawImageAspectFill(_ img: NSImage, in rect: NSRect) {
        let size = img.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        let dest = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        img.draw(in: dest, from: .zero, operation: .copy, fraction: 1.0)
    }

    static func export(tree: FamilyTree, to url: URL) {
        if let data = render(tree: tree) { try? data.write(to: url, options: .atomic) }
    }
}

private extension NSFont {
    /// Returns an italic variant of this font (falls back to self if unavailable).
    func withItalic() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}

/// The tree exactly as it appears on the canvas (cards + connectors, photos optional),
/// laid out at base scale for `ImageRenderer`. Coordinates are translated by
/// `originX/originY` so the scoped subtree starts at the view's origin.
private struct TreePosterView: View {
    let nodes: [TreeNode]
    let links: [TreeLink]
    let canvasSize: CGSize
    let originX: CGFloat
    let originY: CGFloat
    let showPhotos: Bool
    private let cardW: CGFloat = 210
    private let cardH: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                for link in links {
                    for seg in link.segments {
                        p.move(to: CGPoint(x: seg.from.x - originX, y: seg.from.y - originY))
                        p.addLine(to: CGPoint(x: seg.to.x - originX, y: seg.to.y - originY))
                    }
                }
            }
            .stroke(SepiaTheme.line, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

            ForEach(nodes, id: \.person.id) { node in
                PersonCardView(person: node.person, showPhoto: showPhotos, scale: 1)
                    .position(x: node.x - originX + cardW / 2, y: node.y - originY + cardH / 2)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}
