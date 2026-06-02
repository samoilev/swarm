import AppKit
import CoreGraphics
import CoreText

struct PDFExporter {
    /// Renders the poster to PDF data in memory (used by the native .fileExporter).
    static func render(tree: FamilyTree, title: String, subtitle: String) -> Data? {
        let pageW: CGFloat = 842
        let pageH: CGFloat = 595
        let margin: CGFloat = 40

        let pdfData = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor(SepiaTheme.posterBg).cgColor)
        ctx.fill(box)
        
        // Frame
        ctx.setStrokeColor(NSColor(SepiaTheme.accent2).cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: 14, y: 14, width: pageW - 28, height: pageH - 28))
        ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: 19, y: 19, width: pageW - 38, height: pageH - 38))
        
        // Title
        let titleFont = NSFont.systemFont(ofSize: 28, weight: .semibold)
        let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor(SepiaTheme.ink)]
        let titleStr = NSAttributedString(string: title, attributes: titleAttr)
        let titleSz = titleStr.size()
        let titleY = pageH - margin - 50
        
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        titleStr.draw(at: NSPoint(x: (pageW - titleSz.width) / 2, y: titleY))
        
        let subFont = NSFont.systemFont(ofSize: 14)
        let subAttr: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: NSColor(SepiaTheme.inkSoft)]
        let subStr = NSAttributedString(string: subtitle, attributes: subAttr)
        let subSz = subStr.size()
        subStr.draw(at: NSPoint(x: (pageW - subSz.width) / 2, y: titleY - 24))
        
        // People cards
        let people = tree.people
        let cols = min(people.count, 6)
        let rows = max(1, (people.count + cols - 1) / cols)
        let cellW = (pageW - margin * 2) / CGFloat(max(cols, 1))
        let cellH = min(60, (titleY - 90 - margin) / CGFloat(rows))
        let startY = titleY - 70
        
        let nameFont2 = NSFont.systemFont(ofSize: 10)
        let nameAttr2: [NSAttributedString.Key: Any] = [.font: nameFont2, .foregroundColor: NSColor(SepiaTheme.ink)]
        let dateAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor(SepiaTheme.inkSoft)]
        
        for (i, p) in people.enumerated() {
            let col = i % cols
            let row = i / cols
            let x = margin + CGFloat(col) * cellW + cellW / 2
            let y = startY - CGFloat(row) * cellH
            
            let cardRect = CGRect(x: x - 60, y: y - 20, width: 120, height: 40)
            ctx.setFillColor(NSColor(SepiaTheme.cardBg).cgColor)
            ctx.fill(cardRect)
            ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(cardRect)
            
            let name = NSAttributedString(string: p.listName, attributes: nameAttr2)
            let ns = name.size()
            name.draw(at: NSPoint(x: x - ns.width / 2, y: y - 4))
            
            if !p.lifespan.isEmpty {
                let dates = NSAttributedString(string: p.lifespan, attributes: dateAttr)
                let ds = dates.size()
                dates.draw(at: NSPoint(x: x - ds.width / 2, y: y - 16))
            }
        }
        
        // Footer
        let footAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor(SepiaTheme.inkSoft)]
        let df = DateFormatter(); df.dateFormat = "d MMMM yyyy"
        let footStr = NSAttributedString(string: "\(people.count) чел. · подготовлено \(df.string(from: Date()))", attributes: footAttr)
        footStr.draw(at: NSPoint(x: margin + 10, y: margin - 10))
        let brand = NSAttributedString(string: "Родословная Студия", attributes: footAttr)
        let bs = brand.size()
        brand.draw(at: NSPoint(x: pageW - margin - bs.width, y: margin - 10))
        
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return pdfData as Data
    }

    static func export(tree: FamilyTree, title: String, subtitle: String, to url: URL) {
        if let data = render(tree: tree, title: title, subtitle: subtitle) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

struct PNGExporter {
    /// Renders the tree to PNG data in memory (used by the native .fileExporter).
    static func render(tree: FamilyTree, title: String, subtitle: String) -> Data? {
        let w = 1600, h = 1000
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        
        ctx.setFillColor(NSColor(SepiaTheme.posterBg).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        
        let titleFont = NSFont.systemFont(ofSize: 36, weight: .semibold)
        let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor(SepiaTheme.ink)]
        let ts = NSAttributedString(string: title, attributes: titleAttr)
        let tsz = ts.size()
        ts.draw(at: NSPoint(x: (CGFloat(w) - tsz.width) / 2, y: CGFloat(h) - 70))
        
        let nameFont = NSFont.systemFont(ofSize: 14)
        let nameAttr: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor(SepiaTheme.ink)]
        
        let people = tree.people
        let cols = min(people.count, 8)
        let cellW = CGFloat(w - 100) / CGFloat(max(cols, 1))
        let startY = CGFloat(h) - 140
        
        for (i, p) in people.enumerated() {
            let col = i % cols
            let row = i / cols
            let x = 50 + CGFloat(col) * cellW + cellW / 2
            let y = startY - CGFloat(row) * 70
            
            let cardRect = CGRect(x: x - 70, y: y - 15, width: 140, height: 50)
            ctx.setFillColor(NSColor(SepiaTheme.cardBg).cgColor)
            ctx.fill(cardRect)
            ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(cardRect)
            
            let name = NSAttributedString(string: p.listName, attributes: nameAttr)
            let ns = name.size()
            name.draw(at: NSPoint(x: x - ns.width / 2, y: y))
        }
        
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    static func export(tree: FamilyTree, title: String, subtitle: String, to url: URL) {
        if let data = render(tree: tree, title: title, subtitle: subtitle) {
            try? data.write(to: url)
        }
    }
}

/// Renders every person as their own card, sorted alphabetically by name, one card
/// per page (A4 portrait). A card whose content overflows continues onto further
/// pages; the next person always begins on a fresh page.
struct PersonCardsPDFExporter {
    private static let pageW: CGFloat = 595   // A4 portrait @ 72 dpi
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 48
    private static let footerBaseline: CGFloat = 30   // y of footer text
    private static let bodyBottom: CGFloat = 50       // text never drops below this y

    static func render(tree: FamilyTree) -> Data? {
        let people = tree.people.sorted {
            $0.listName.localizedCaseInsensitiveCompare($1.listName) == .orderedAscending
        }
        guard !people.isEmpty else { return nil }

        let pdfData = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        let idx = FamilyIndex(tree: tree)
        let contentW = pageW - margin * 2

        for person in people {
            let body = makeBody(for: person, idx: idx)
            let framesetter = CTFramesetterCreateWithAttributedString(body)
            let total = body.length
            var location = 0
            var firstPage = true

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

                if total > 0 && topY > bodyBottom {
                    let textRect = CGRect(x: margin, y: bodyBottom, width: contentW, height: topY - bodyBottom)
                    let path = CGMutablePath(); path.addRect(textRect)
                    ctx.textMatrix = .identity
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                    CTFrameDraw(frame, ctx)
                    let visible = CTFrameGetVisibleStringRange(frame)
                    location += visible.length > 0 ? visible.length : (total - location) // guard: avoid stall
                } else {
                    location = total
                }

                drawFooter(person)

                NSGraphicsContext.restoreGraphicsState()
                ctx.endPDFPage()
                firstPage = false
            } while location < total
        }

        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Page chrome

    private static func drawBackground(_ ctx: CGContext, box: CGRect) {
        ctx.setFillColor(NSColor(SepiaTheme.paper).cgColor)
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
        NSAttributedString(string: person.listName, attributes: attr)
            .draw(at: NSPoint(x: margin, y: footerBaseline))
        let brand = NSAttributedString(string: "Родословная Студия", attributes: attr)
        brand.draw(at: NSPoint(x: pageW - margin - brand.size().width, y: footerBaseline))
    }

    // MARK: - Headers (return the y below which the body text may start)

    private static func drawHeader(_ person: Person, ctx: CGContext, textWidth: CGFloat) -> CGFloat {
        let topEdge = pageH - margin
        let photoSize: CGFloat = 84
        var textX = margin

        if let data = person.photoData, let img = NSImage(data: data) {
            let rect = NSRect(x: margin, y: topEdge - photoSize, width: photoSize, height: photoSize)
            let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            drawImageAspectFill(img, in: rect)
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor(SepiaTheme.cardLine).cgColor); ctx.setLineWidth(1); ctx.strokePath()
            textX = margin + photoSize + 16
        }

        let textW = pageW - margin - textX
        var cursorY = topEdge

        let nameStr = NSAttributedString(string: person.listName, attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor(SepiaTheme.ink)
        ])
        let nameH = textHeight(nameStr, width: textW)
        nameStr.draw(in: NSRect(x: textX, y: cursorY - nameH, width: textW, height: nameH))
        cursorY -= nameH + 3

        if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
            let s = NSAttributedString(string: "урожд. \(maiden)", attributes: [
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
        let blockBottom = min(cursorY, person.photoData != nil ? topEdge - photoSize : cursorY)
        let ruleY = blockBottom - 12
        ctx.setStrokeColor(NSColor(SepiaTheme.accent2).withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: ruleY)); ctx.addLine(to: CGPoint(x: pageW - margin, y: ruleY)); ctx.strokePath()
        return ruleY - 14
    }

    private static func drawContinuationHeader(_ person: Person, textWidth: CGFloat) -> CGFloat {
        let topEdge = pageH - margin
        let s = NSAttributedString(string: "\(person.listName) — продолжение", attributes: [
            .font: NSFont.systemFont(ofSize: 11).withItalic(),
            .foregroundColor: NSColor(SepiaTheme.inkSoft)
        ])
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

        section("Личность")
        field("Имя", p.givenNames)
        field("Отчество", p.patronymic)
        field("Фамилия", p.surname)
        field("Девичья фамилия", p.maidenName)
        field("Пол", p.sex.displayName)

        if p.birthDate?.isEmpty == false || p.birthPlace?.isEmpty == false {
            section("Рождение")
            field("Дата", p.birthDate)
            field("Место", p.birthPlace)
        }

        let hasBurial = (p.burialPlace?.isEmpty == false) || (p.burialLat != nil && p.burialLon != nil)
        if !p.isLiving || hasBurial {
            section("Смерть и погребение")
            if !p.isLiving {
                field("Дата смерти", p.deathDate)
                field("Место смерти", p.deathPlace)
            }
            field("Место захоронения", p.burialPlace)
            if let lat = p.burialLat, let lon = p.burialLon {
                field("Координаты могилы", String(format: "%.5f, %.5f", lat, lon))
            }
        }

        if p.occupation?.isEmpty == false || p.education?.isEmpty == false || p.notes?.isEmpty == false {
            section("Жизнь")
            field("Профессия", p.occupation)
            field("Образование", p.education)
            field("Заметки", p.notes)
        }

        if !p.attachments.isEmpty {
            section("Файлы")
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
            section("Родственные связи")
            field("Отец", parents.father?.listName)
            field("Мать", parents.mother?.listName)
            if !spouses.isEmpty { field("Супруг(и)", spouses.map(\.listName).joined(separator: ", ")) }
            if !children.isEmpty { field("Дети", children.map(\.listName).joined(separator: ", ")) }
            if !siblings.isEmpty { field("Братья/сёстры", siblings.map(\.listName).joined(separator: ", ")) }
        }

        return result
    }

    // MARK: - Helpers

    private static func textHeight(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
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
