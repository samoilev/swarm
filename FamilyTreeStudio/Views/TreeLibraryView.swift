import SwiftUI

struct TreeLibraryView: View {
    let trees: [FamilyTree]
    let onSelect: (FamilyTree) -> Void
    let onCreate: () -> Void
    var onImport: (() -> Void)? = nil
    var onRevealInFinder: ((FamilyTree) -> Void)? = nil
    
    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()
            
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Родословная")
                        .font(SepiaTheme.display(size: 32))
                        .foregroundColor(SepiaTheme.ink)
                    Text("СЕМЕЙНЫЙ АРХИВ")
                        .font(SepiaTheme.ui(size: 10))
                        .tracking(3)
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                .padding(.top, 48)
                .padding(.bottom, 32)
                
                Divider().overlay(SepiaTheme.line)
                
                if trees.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "tree")
                            .font(.system(size: 48))
                            .foregroundColor(SepiaTheme.inkSoft)
                        Text("Деревьев пока нет")
                            .font(SepiaTheme.body(size: 18))
                            .foregroundColor(SepiaTheme.ink)
                        Text("Создайте первое родословное дерево")
                            .font(SepiaTheme.body(size: 14))
                            .foregroundColor(SepiaTheme.inkSoft)
                        Button(action: onCreate) {
                            Label("Создать дерево", systemImage: "plus")
                        }
                        .buttonStyle(SepiaButtonStyle(isActive: true))
                        .padding(.top, 8)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 20)
                        ], spacing: 20) {
                            Button(action: onCreate) {
                                VStack(spacing: 12) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 32))
                                        .foregroundColor(SepiaTheme.accent)
                                    Text("Новое дерево")
                                        .font(SepiaTheme.ui(size: 14))
                                        .foregroundColor(SepiaTheme.ink)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .background(SepiaTheme.cardBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(SepiaTheme.cardLine, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { onImport?() }) {
                                VStack(spacing: 12) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 32))
                                        .foregroundColor(SepiaTheme.accent2)
                                    Text("Импорт GEDCOM")
                                        .font(SepiaTheme.ui(size: 14))
                                        .foregroundColor(SepiaTheme.ink)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .background(SepiaTheme.cardBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(SepiaTheme.cardLine, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(trees, id: \.id) { tree in
                                TreeCardView(tree: tree, onSelect: { onSelect(tree) }, onReveal: { onRevealInFinder?(tree) })
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct TreeCardView: View {
    let tree: FamilyTree
    let onSelect: () -> Void
    var onReveal: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Image(systemName: "tree")
                        .font(.system(size: 28))
                        .foregroundColor(SepiaTheme.accent2)
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(tree.name)
                        .font(SepiaTheme.display(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(SepiaTheme.ink)
                        .lineLimit(1)
                    if let subtitle = tree.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(SepiaTheme.body(size: 12))
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("\(tree.people.count) чел.")
                            .font(SepiaTheme.ui(size: 11))
                            .foregroundColor(SepiaTheme.inkSoft)
                        Spacer()
                        Button(action: { onReveal?() }) {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(SepiaTheme.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .help("Открыть в Finder")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160)
            .background(SepiaTheme.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(SepiaTheme.cardLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
