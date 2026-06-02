import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportView: View {
    let tree: FamilyTree
    let viewMode: MainWorkspace.ViewMode
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var posterStyle: PosterStyle = .cartouche

    // Native file export (PNG / PDF)
    @State private var exportDoc: RenderedFileDocument?
    @State private var exportName = ""
    @State private var showExporter = false
    @State private var exportError: String?
    
    enum PosterStyle: String, CaseIterable {
        case cartouche = "Картуш"
        case botanical = "Ботаника"
        case plate = "Гравюра"
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            HStack(spacing: 18) {
                posterPreview
                controlsPanel
            }
            .padding(24)
        }
        .frame(width: 960, height: 620)
        .onAppear {
            title = tree.name
            subtitle = tree.subtitle ?? ""
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: exportDoc?.type ?? .data,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Не удалось сохранить файл", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var fileSlug: String {
        tree.name.replacingOccurrences(of: " ", with: "-").lowercased()
    }
    
    private var posterPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(SepiaTheme.posterBg)
            
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(viewMode == .fan ? "ВЕЕР ПРЕДКОВ" : "РОДОСЛОВНОЕ ДЕРЕВО")
                        .font(SepiaTheme.ui(size: 10.5)).tracking(4).foregroundColor(SepiaTheme.accent2)
                    Text(title)
                        .font(SepiaTheme.display(size: 28)).fontWeight(.semibold).foregroundColor(SepiaTheme.ink)
                    Text(subtitle)
                        .font(SepiaTheme.body(size: 13)).italic().foregroundColor(SepiaTheme.inkSoft)
                    Rectangle().fill(SepiaTheme.accent2.opacity(0.6)).frame(width: 60, height: 1).padding(.top, 4)
                }
                .padding(.top, 28)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(SepiaTheme.paper.opacity(0.5))
                    Image(systemName: viewMode == .fan ? "chart.pie" : "rectangle.connected.to.line.below")
                        .font(.system(size: 48)).foregroundColor(SepiaTheme.inkSoft.opacity(0.4))
                    Text("\(tree.people.count) чел.")
                        .font(SepiaTheme.ui(size: 11)).foregroundColor(SepiaTheme.inkSoft).offset(y: 40)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                HStack {
                    Text("\(tree.people.count) чел. · подготовлено \(formattedDate)")
                        .font(SepiaTheme.body(size: 10)).foregroundColor(SepiaTheme.inkSoft)
                    Spacer()
                    Text("Родословная")
                        .font(SepiaTheme.ui(size: 10)).italic().foregroundColor(SepiaTheme.inkSoft)
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
            
            if posterStyle == .cartouche {
                RoundedRectangle(cornerRadius: 4).strokeBorder(SepiaTheme.accent2, lineWidth: 2).padding(14)
                RoundedRectangle(cornerRadius: 4).strokeBorder(SepiaTheme.cardLine, lineWidth: 1).padding(19)
            }
            if posterStyle == .botanical {
                RoundedRectangle(cornerRadius: 4).strokeBorder(SepiaTheme.cardLine, lineWidth: 1).padding(16)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }
    
    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Экспорт").font(SepiaTheme.display(size: 22)).foregroundColor(SepiaTheme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").foregroundColor(SepiaTheme.inkSoft)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("НАЗВАНИЕ ПОСТЕРА").font(SepiaTheme.ui(size: 9.5)).tracking(1.5).foregroundColor(SepiaTheme.inkSoft)
                TextField("Название", text: $title).textFieldStyle(.plain).font(SepiaTheme.body(size: 15))
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.fieldLine).frame(height: 1) }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("ПОДЗАГОЛОВОК").font(SepiaTheme.ui(size: 9.5)).tracking(1.5).foregroundColor(SepiaTheme.inkSoft)
                TextField("Подзаголовок", text: $subtitle).textFieldStyle(.plain).font(SepiaTheme.body(size: 15))
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.fieldLine).frame(height: 1) }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("СТИЛЬ ПОСТЕРА").font(SepiaTheme.ui(size: 9.5)).tracking(1.5).foregroundColor(SepiaTheme.inkSoft)
                HStack(spacing: 8) {
                    ForEach(PosterStyle.allCases, id: \.rawValue) { style in
                        Button(style.rawValue) { posterStyle = style }
                            .buttonStyle(SepiaButtonStyle(isActive: posterStyle == style))
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 10) {
                Button { exportPDF() } label: { Label("Сохранить PDF-постер", systemImage: "arrow.down.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(SepiaButtonStyle(isActive: true)).controlSize(.large)
                Button { exportPNG() } label: { Label("Скачать PNG", systemImage: "photo").frame(maxWidth: .infinity) }
                    .buttonStyle(SepiaButtonStyle()).controlSize(.large)
                Button { exportGEDCOM() } label: { Label("Экспорт GEDCOM (.ged)", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(SepiaButtonStyle()).controlSize(.large)
            }
            
            Text("PDF печатает оформленный постер. GEDCOM — стандартный файл, который можно открыть в Ancestry, Gramps или MacFamilyTree.")
                .font(SepiaTheme.body(size: 11.5)).foregroundColor(SepiaTheme.inkSoft).lineSpacing(2)
        }
        .padding(20)
        .frame(width: 280)
        .background(SepiaTheme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // GEDCOM export stays on NSSavePanel: it writes a sibling `Media/` folder next
    // to the chosen .ged file, which doesn't fit the single-file FileWrapper model
    // used by .fileExporter (the app is effectively non-sandboxed, so this is fine).
    private func exportGEDCOM() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ged") ?? .plainText]
        panel.nameFieldStringValue = "\(fileSlug).ged"
        panel.begin { r in
            if r == .OK, let url = panel.url {
                let mediaFolder = url.deletingLastPathComponent().appendingPathComponent("Media", isDirectory: true)
                let gedcom = GEDCOMSerializer.serialize(tree: tree, mediaFolder: mediaFolder)
                try? gedcom.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func exportPDF() {
        guard let data = PDFExporter.render(tree: tree, title: title, subtitle: subtitle) else { return }
        exportDoc = RenderedFileDocument(data: data, type: .pdf)
        exportName = "\(fileSlug)-poster.pdf"
        showExporter = true
    }

    private func exportPNG() {
        guard let data = PNGExporter.render(tree: tree, title: title, subtitle: subtitle) else { return }
        exportDoc = RenderedFileDocument(data: data, type: .png)
        exportName = "\(fileSlug)-tree.png"
        showExporter = true
    }
    
    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"; return f.string(from: Date())
    }
}
