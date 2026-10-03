import SwarmCore
import SwiftUI

/// A tree too big for one view per card, drawn as a single canvas the size of the window
/// and culled to the part of the tree the window shows.
///
/// It used to be a canvas the size of the whole layout, scaled down. 50,000 unrelated
/// people lay out in one row 17 million points wide, and a canvas that wide kept the
/// window busy for minutes and grew the app by gigabytes before anything appeared.
/// Drawing only what is visible costs the same at any tree size.
struct LargeTreeCanvas: View {
    /// Above this many cards the canvas replaces the per-card views.
    static let threshold = 1200

    let layout: TreeLayout
    let zoom: CGFloat
    let panOffset: CGSize
    let cardW: CGFloat
    let cardH: CGFloat
    let selectedId: UUID?
    let secondaryId: UUID?
    let homeId: UUID?
    let highlightedIds: Set<UUID>
    let highlightedConnections: Set<FamilyConnection>
    let onSelect: (Person, Bool) -> Void
    /// The canvas covers the whole window, so a tap between cards lands here rather
    /// than on the background that clears the selection.
    let onTapEmpty: () -> Void

    var body: some View {
        Canvas { context, size in
            // screen = tree · zoom + pan, so the visible part of the tree is this rect.
            let visible = CGRect(
                x: -panOffset.width / zoom,
                y: -panOffset.height / zoom,
                width: size.width / zoom,
                height: size.height / zoom
            )
            context.translateBy(x: panOffset.width, y: panOffset.height)
            context.scaleBy(x: zoom, y: zoom)

            func path(_ segments: [LinkSegment]) -> Path {
                var path = Path()
                for segment in segments {
                    let bounds = CGRect(
                        x: min(segment.from.x, segment.to.x), y: min(segment.from.y, segment.to.y),
                        width: abs(segment.to.x - segment.from.x), height: abs(segment.to.y - segment.from.y)
                    ).insetBy(dx: -2, dy: -2)
                    guard visible.intersects(bounds) else { continue }
                    path.move(to: segment.from)
                    path.addLine(to: segment.to)
                }
                return path
            }
            context.stroke(
                path(layout.links.flatMap(\.segments)),
                with: .color(SepiaTheme.line),
                style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)
            )
            if !highlightedConnections.isEmpty {
                let active = layout.highlightRoutes
                    .filter { !$0.connections.isDisjoint(with: highlightedConnections) }
                    .flatMap(\.segments)
                context.stroke(path(active), with: .color(SepiaTheme.accent), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }

            for node in layout.nodes {
                let rect = CGRect(x: node.x, y: node.y, width: cardW, height: cardH)
                guard visible.intersects(rect) else { continue }
                let id = node.person.id
                let selected = id == selectedId || id == secondaryId
                let emphasized = selected || id == homeId || highlightedIds.contains(id)
                let fill = selected ? SepiaTheme.fanSel : (emphasized ? SepiaTheme.cardBgHover : SepiaTheme.cardBg)
                let card = Path(roundedRect: rect, cornerRadius: 10)
                context.fill(card, with: .color(fill))
                context.stroke(card, with: .color(selected ? SepiaTheme.accent : SepiaTheme.cardLine), lineWidth: selected ? 2 : 1)
                if emphasized {
                    let name = node.person.displayName(language: .current)
                    context.draw(
                        Text(name.isEmpty ? L10n.tr("Без имени") : name)
                            .font(SepiaTheme.ui(size: 12, scaled: false))
                            .foregroundStyle(SepiaTheme.ink),
                        at: CGPoint(x: rect.midX, y: rect.midY),
                        anchor: .center
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            let point = CGPoint(x: (location.x - panOffset.width) / zoom, y: (location.y - panOffset.height) / zoom)
            guard let node = layout.nodes.first(where: {
                CGRect(x: $0.x, y: $0.y, width: cardW, height: cardH).contains(point)
            }) else { return onTapEmpty() }
            onSelect(node.person, NSEvent.modifierFlags.contains(.command))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Дерево: \(L10n.count(layout.nodes.count, .person))"))
    }
}
