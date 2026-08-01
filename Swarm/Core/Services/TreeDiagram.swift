import CoreGraphics
import Foundation

/// A miniature of a whole family tree. Every library card draws one in place of an
/// arbitrary person's photograph, so a record is recognisable by its own shape.
///
/// It is the *entire* record, scaled to fit — the same thing the workspace's own minimap
/// does, and for the same reason. Two narrower ideas were tried first and both misled:
/// cropping the top three generations out of the full layout produced rows from unrelated
/// branches, and pruning to one couple's immediate family drew a single wing of a
/// forty-nine-person archive and captioned it with the whole record's depth. A miniature
/// that shows less than the tree is worse than no miniature, because it claims to be the
/// tree.
///
/// The layout pass is the expensive part, so `TreeStore.diagram(for:)` caches the result
/// per tree and only recomputes when the tree has been written again.
public struct TreeDiagram: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public let personId: UUID
        public let sex: Person.Sex
        public let isHome: Bool
        /// Centre of the card, 0…1 within the cropped region. The view maps it to pixels,
        /// so the same geometry serves a 260pt card plate and a 2.9× watermark.
        public let x: CGFloat
        public let y: CGFloat

        public init(personId: UUID, sex: Person.Sex, isHome: Bool, x: CGFloat, y: CGFloat) {
            self.personId = personId
            self.sex = sex
            self.isHome = isHome
            self.x = x
            self.y = y
        }
    }

    public let nodes: [Node]
    /// The real connectors, as normalised polylines. Drawing these rather than re-deriving
    /// "spouse link, drop, bus, drop" is what makes the miniature match the canvas.
    public let links: [[CGPoint]]
    /// Width ÷ height of the cropped region, so the view can fit it without distortion.
    public let aspect: CGFloat
    /// A person card's size as a fraction of the region. Drawing nodes at a fixed size
    /// while scaling their positions made the two disagree: on a two-person record the
    /// spouse link is the whole drawing, and it floated between its nodes instead of
    /// joining them.
    public let nodeSize: CGSize
    /// How many generations the drawing contains — which is the whole record, so the
    /// card's "9 generations" caption and its picture can never disagree.
    public let generationCount: Int

    public init(
        nodes: [Node],
        links: [[CGPoint]],
        aspect: CGFloat,
        generationCount: Int,
        nodeSize: CGSize = CGSize(width: 0.12, height: 0.16)
    ) {
        self.nodes = nodes
        self.links = links
        self.aspect = aspect
        self.generationCount = generationCount
        self.nodeSize = nodeSize
    }

    public var isEmpty: Bool { nodes.isEmpty }

    // MARK: - Building from a tree

    /// Lay the record out with the same engine the canvas uses, then normalise the result
    /// into a unit box. Nothing is cropped and nothing is re-derived, so the card's picture
    /// is the tree it opens, at a smaller size.
    public init(tree: FamilyTree) {
        let config = LayoutConfig()
        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        guard !layout.nodes.isEmpty else {
            self = TreeDiagram(nodes: [], links: [], aspect: 1, generationCount: 0)
            return
        }

        // Generations are rows of equal `y`; rounding absorbs floating-point drift.
        let generations = Set(layout.nodes.map { ($0.y * 100).rounded() }).count

        let minX = layout.nodes.map(\.x).min()!
        let maxX = layout.nodes.map { $0.x + config.cardW }.max()!
        let minY = layout.nodes.map(\.y).min()!
        let maxY = layout.nodes.map { $0.y + config.cardH }.max()!
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)

        func normalise(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - minX) / width, y: (point.y - minY) / height)
        }

        let homeId = tree.homePersonId
        nodes = layout.nodes.map { node in
            let centre = normalise(CGPoint(x: node.x + config.cardW / 2, y: node.y + config.cardH / 2))
            return Node(
                personId: node.person.id,
                sex: node.person.sex,
                isHome: node.person.id == homeId,
                x: centre.x,
                y: centre.y
            )
        }
        links = layout.links.flatMap { link in
            link.segments.map { [normalise($0.from), normalise($0.to)] }
        }
        aspect = width / height
        nodeSize = CGSize(width: config.cardW / width, height: config.cardH / height)
        generationCount = generations
    }


    /// The shape of a record that does not exist yet: a couple, three children, and three
    /// grandchildren under the middle one. The empty library draws it as a dashed ghost and
    /// the language chooser as a watermark, so both screens speak the same visual language
    /// as a library full of real cards.
    public static let placeholder: TreeDiagram = {
        func node(_ x: CGFloat, _ y: CGFloat, _ sex: Person.Sex = .unknown) -> Node {
            Node(personId: UUID(), sex: sex, isHome: false, x: x, y: y)
        }
        return TreeDiagram(
            nodes: [
                node(0.42, 0.07, .male), node(0.58, 0.07, .female),
                node(0.05, 0.5, .male), node(0.5, 0.5, .female), node(0.95, 0.5, .male),
                node(0.28, 0.93), node(0.5, 0.93), node(0.72, 0.93),
            ],
            links: [
                [CGPoint(x: 0.46, y: 0.07), CGPoint(x: 0.54, y: 0.07)],
                [CGPoint(x: 0.5, y: 0.07), CGPoint(x: 0.5, y: 0.28)],
                [CGPoint(x: 0.05, y: 0.28), CGPoint(x: 0.95, y: 0.28)],
                [CGPoint(x: 0.05, y: 0.28), CGPoint(x: 0.05, y: 0.5)],
                [CGPoint(x: 0.5, y: 0.28), CGPoint(x: 0.5, y: 0.5)],
                [CGPoint(x: 0.95, y: 0.28), CGPoint(x: 0.95, y: 0.5)],
                [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.71)],
                [CGPoint(x: 0.28, y: 0.71), CGPoint(x: 0.72, y: 0.71)],
                [CGPoint(x: 0.28, y: 0.71), CGPoint(x: 0.28, y: 0.93)],
                [CGPoint(x: 0.5, y: 0.71), CGPoint(x: 0.5, y: 0.93)],
                [CGPoint(x: 0.72, y: 0.71), CGPoint(x: 0.72, y: 0.93)],
            ],
            aspect: 260.0 / 76.0,
            generationCount: 3
        )
    }()
}
