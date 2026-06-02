import AppKit
import CoreGraphics

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
