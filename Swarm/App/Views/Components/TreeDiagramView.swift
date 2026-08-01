import SwarmCore
import SwiftUI

/// Draws a `TreeDiagram` — the miniature of a record's top generations that replaced the
/// arbitrary portrait on a library card.
///
/// The diagram arrives as a unit box of card centres and real connector polylines, so this
/// view only has to fit that box into the plate without distorting it and draw the nodes at
/// the tokens' size. Node fills and borders come from the same tokens `PersonCardView` uses
/// on the canvas, so a card is legibly a small picture of the tree it opens.
struct TreeDiagramView: View {
    let diagram: TreeDiagram
    var style: Style = .plate
    var scale: CGFloat = 1
    /// Set only on the card whose tree is opening, so twelve idle cards in a grid do not
    /// each register geometry for a morph that is not happening.
    var morphNamespace: Namespace.ID?
    /// People the reader has not written down yet — drawn as a dashed outline. The
    /// onboarding preview uses this for the seat the next relative will take.
    var pendingNodeIDs: Set<UUID> = []
    /// People named but not yet real. Held back to a quarter so the moment they are
    /// entered reads as the record gaining a person.
    var dimmedNodeIDs: Set<UUID> = []

    enum Style {
        /// A real record, on a card plate or an onboarding preview.
        case plate
        /// A record that does not exist yet: dashed, faded back.
        case ghost
        /// Outline only, sitting far behind the language chooser's card.
        case watermark
    }

    // MARK: - Base geometry

    static let baseSize = CGSize(width: 260, height: 76)
    private static let nodeSize = CGSize(width: 18, height: 10)
    private static let nodeRadius: CGFloat = 2

    /// Room to keep clear at the top of the canvas. The card plate prints its "N
    /// GENERATIONS" caption up there, and a tree fitted to the full height runs its
    /// eldest generation straight through the words.
    var topInset: CGFloat = 0

    /// Where the unit box lands inside the base canvas: fitted, centred, and inset by half
    /// a node so the outermost cards are not clipped by the plate edge.
    private var frame: CGRect {
        let canvas = CGRect(
            x: Self.nodeSize.width / 2,
            y: Self.nodeSize.height / 2 + topInset,
            width: Self.baseSize.width - Self.nodeSize.width,
            height: Self.baseSize.height - Self.nodeSize.height - topInset
        )
        guard diagram.aspect > 0 else { return canvas }
        // Contain, never stretch: a wide shallow record must stay wide and shallow.
        var height = min(canvas.width / diagram.aspect, canvas.height)
        var width = height * diagram.aspect

        // A record of two people is a tiny drawing, and filling the plate with it would
        // blow its cards up to the size of the plate. Shrink the whole fit — positions and
        // cards together — until a card is no larger than a card should be. Clamping only
        // the card size instead left the spouse link floating between its two people.
        if diagram.nodeSize.width * width > Self.maxNodeSize.width {
            let factor = Self.maxNodeSize.width / (diagram.nodeSize.width * width)
            width *= factor
            height *= factor
        }
        if diagram.nodeSize.height * height > Self.maxNodeSize.height {
            let factor = Self.maxNodeSize.height / (diagram.nodeSize.height * height)
            width *= factor
            height *= factor
        }

        return CGRect(
            x: canvas.midX - width / 2,
            y: canvas.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
    }

    /// The largest a person card may be drawn. Bigger than this and a sparse record stops
    /// looking like a tree and starts looking like two boxes.
    private static let maxNodeSize = CGSize(width: 26, height: 13)

    /// A node is drawn at exactly the scale of the positions around it, so the connectors
    /// meet its edges. The fit above guarantees this never exceeds `maxNodeSize`; the floor
    /// keeps a fifty-person record's cards from vanishing to a hairline.
    private var drawnNodeSize: CGSize {
        CGSize(
            width: max(diagram.nodeSize.width * frame.width, 3),
            height: max(diagram.nodeSize.height * frame.height, 2)
        )
    }

    /// Connectors thin out as the record gets denser. A 1.1pt line is right for a family
    /// of six and turns a family of fifty into a solid smudge.
    private var connectorWidth: CGFloat {
        max(0.5, min(1.1, drawnNodeSize.height / 9))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DiagramConnectors(links: diagram.links, frame: frame)
                .stroke(connectorColor, style: connectorStroke)

            ForEach(Array(diagram.nodes.enumerated()), id: \.offset) { index, node in
                self.node(node, index: index)
            }
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height)
        .opacity(style == .watermark ? 0.16 : 1)
        .scaleEffect(scale)
        .frame(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        // The card carries the tree's own description; a second reading of its shape adds
        // nothing a VoiceOver user can act on.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func node(_ node: TreeDiagram.Node, index: Int) -> some View {
        let centre = point(node.x, node.y)
        let treatment = pendingNodeIDs.contains(node.personId)
            ? NodeTreatment(
                fill: .clear,
                stroke: SepiaTheme.cardLine.opacity(0.6),
                strokeStyle: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
            : treatment(node, index: index)

        RoundedRectangle(cornerRadius: Self.nodeRadius, style: .continuous)
            .fill(treatment.fill)
            .overlay(
                RoundedRectangle(cornerRadius: Self.nodeRadius, style: .continuous)
                    .strokeBorder(treatment.stroke, style: treatment.strokeStyle)
            )
            .frame(width: drawnNodeSize.width, height: drawnNodeSize.height)
            .opacity(dimmedNodeIDs.contains(node.personId) ? 0.25 : 1)
            .position(centre)
            .modifier(TreeMorphGeometry(namespace: morphNamespace, personId: node.personId, isSource: true))
    }

    // MARK: - Style

    private struct NodeTreatment {
        let fill: Color
        let stroke: Color
        let strokeStyle: StrokeStyle
    }

    private func treatment(_ node: TreeDiagram.Node, index: Int) -> NodeTreatment {
        switch style {
        case .plate:
            NodeTreatment(
                fill: Self.fill(for: node.sex),
                // The home person carries the diagram's only accent, mirroring the home
                // marker a canvas card wears.
                stroke: node.isHome ? SepiaTheme.accent : Self.line(for: node.sex),
                strokeStyle: StrokeStyle(lineWidth: node.isHome ? 1.5 : 1)
            )
        case .ghost:
            // The first person is the only one who exists: solid. Everything behind them
            // fades row by row into a tree waiting to be filled in.
            index == 0
                ? NodeTreatment(
                    fill: SepiaTheme.cardBg,
                    stroke: SepiaTheme.cardLine,
                    strokeStyle: StrokeStyle(lineWidth: 1)
                )
                : NodeTreatment(
                    fill: .clear,
                    stroke: SepiaTheme.cardLine.opacity(Self.ghostOpacity(y: node.y)),
                    strokeStyle: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
        case .watermark:
            NodeTreatment(
                fill: .clear,
                stroke: SepiaTheme.inkSoft,
                strokeStyle: StrokeStyle(lineWidth: 1)
            )
        }
    }

    private static func ghostOpacity(y: CGFloat) -> Double {
        switch y {
        case ..<0.34: 0.75
        case ..<0.67: 0.55
        default: 0.35
        }
    }

    private static func fill(for sex: Person.Sex) -> Color {
        switch sex {
        case .male: SepiaTheme.cardBgMale
        case .female: SepiaTheme.cardBgFemale
        case .unknown: SepiaTheme.cardBg
        }
    }

    private static func line(for sex: Person.Sex) -> Color {
        switch sex {
        case .male: SepiaTheme.cardLineMale
        case .female: SepiaTheme.cardLineFemale
        case .unknown: SepiaTheme.cardLine
        }
    }

    private var connectorColor: Color {
        switch style {
        case .plate: SepiaTheme.line
        case .ghost: SepiaTheme.cardLine.opacity(0.6)
        case .watermark: SepiaTheme.inkSoft
        }
    }

    private var connectorStroke: StrokeStyle {
        switch style {
        case .plate: StrokeStyle(lineWidth: connectorWidth)
        case .ghost: StrokeStyle(lineWidth: 1, dash: [3, 3])
        case .watermark: StrokeStyle(lineWidth: 1)
        }
    }
}

/// Joins a node to its counterpart on the other side of the library → workspace morph.
/// `matchedGeometryEffect` has no "off" switch, so the branch has to happen at the modifier
/// — a nil namespace means this view is not taking part and registers nothing.
struct TreeMorphGeometry: ViewModifier {
    let namespace: Namespace.ID?
    let personId: UUID
    /// The library card is the source; the canvas card is where the geometry lands.
    var isSource: Bool

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: personId, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}

/// The tree's own connectors, straight from the layout engine and scaled down. Nothing is
/// re-derived here, so the miniature cannot disagree with the canvas about who is joined
/// to whom.
struct DiagramConnectors: Shape {
    let links: [[CGPoint]]
    let frame: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        for polyline in links {
            guard let first = polyline.first else { continue }
            path.move(to: place(first))
            for point in polyline.dropFirst() {
                path.addLine(to: place(point))
            }
        }
        return path
    }

    private func place(_ point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
    }
}
