import CoreGraphics
import Foundation

/// Orientation for a tidy tree drawing.
public enum LayoutDirection: Equatable {
    case topDown
    case leftRight
    /// Ancestors at the bottom, descendants climbing — the shape most printed
    /// genealogies use. Geometrically a top-down layout flipped about its own centre.
    case bottomUp
}

/// A laid-out person card position (top-left origin).
public struct TreeNode: Equatable {
    public let person: Person
    public let x: CGFloat
    public let y: CGFloat
    public init(person: Person, x: CGFloat, y: CGFloat) {
        self.person = person; self.x = x; self.y = y
    }

    public static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs.person.id == rhs.person.id && lhs.x == rhs.x && lhs.y == rhs.y
    }
}

public struct LinkSegment: Equatable {
    public let from: CGPoint
    public let to: CGPoint
    public init(from: CGPoint, to: CGPoint) {
        self.from = from; self.to = to
    }
}

public struct TreeLink: Identifiable, Equatable {
    public let id: String
    public let segments: [LinkSegment]
    public init(id: String, segments: [LinkSegment]) {
        self.id = id; self.segments = segments
    }
}

/// Geometry used only for the accent overlay. Unlike the neutral sibling bus, each
/// route follows one logical relationship branch and can be activated independently.
public struct TreeHighlightRoute: Identifiable, Equatable {
    public let id: String
    public let segments: [LinkSegment]
    public let connections: Set<FamilyConnection>

    public init(
        id: String,
        segments: [LinkSegment],
        connections: Set<FamilyConnection>
    ) {
        self.id = id
        self.segments = segments
        self.connections = connections
    }
}

public struct TreeLayout: Equatable {
    /// The point where a union's connectors meet — on the row between neighbouring
    /// partners, or on the lane that carries a routed marriage. Nothing is drawn here; it
    /// is the layout's statement of where each partnership lives, which is what lets a
    /// caller (or a test) tell two marriages of the same person apart.
    public struct UnionAnchor: Identifiable, Equatable {
        public let id: UUID
        public let point: CGPoint

        public init(id: UUID, point: CGPoint) {
            self.id = id; self.point = point
        }
    }

    public let nodes: [TreeNode]
    public let links: [TreeLink]
    public let highlightRoutes: [TreeHighlightRoute]
    public let unionAnchors: [UnionAnchor]
    public let totalWidth: CGFloat
    public let totalHeight: CGFloat
    public init(
        nodes: [TreeNode],
        links: [TreeLink],
        highlightRoutes: [TreeHighlightRoute],
        unionAnchors: [UnionAnchor] = [],
        totalWidth: CGFloat,
        totalHeight: CGFloat
    ) {
        self.nodes = nodes; self.links = links
        self.highlightRoutes = highlightRoutes
        self.unionAnchors = unionAnchors
        self.totalWidth = totalWidth; self.totalHeight = totalHeight
    }
}

/// Card sizes and gaps the layout is built from. Defaults match the on-screen card
/// (210×90) so the engine and the view agree.
public struct LayoutConfig {
    public var cardW: CGFloat = 210
    public var cardH: CGFloat = 90
    /// Gap between adjacent cards inside a spouse chain. Wide enough to seat the union
    /// glyph between two partners.
    public var spouseGap: CGFloat = 40
    public var siblingGap: CGFloat = 110 // gap between separate couples / branches
    public var familyGap: CGFloat = 140 // gap between unrelated families / roots
    public var vGapTB: CGFloat = 110
    public var vGapLR: CGFloat = 150
    public var pad: CGFloat = 60
    public init() {}
}

/// Layered layout for genealogical graphs.
///
/// A genealogy is a DAG, not a tree — everybody has two parents and a couple can appear in
/// several unions — so a tidy-tree algorithm cannot lay one out without either dropping
/// edges or letting subtrees collide. This engine instead follows the standard layered
/// (Sugiyama) pipeline, specialised for genealogy the way yFiles' family-tree layouter and
/// the genealogical graph-drawing literature describe it:
///
///   1. `LayoutGraph` — model unions as nodes, assign generations by longest path.
///   2. `LayoutOrdering` — spouse blocks, dummy corridors, crossing minimisation, coordinates.
///   3. `LayoutRouting` — union glyphs and lane-routed connectors.
///
/// Pure and side-effect-free: same tree + direction always yields the same layout, which is
/// what makes it unit-testable independently of SwiftUI.
public struct TreeLayoutEngine {
    private let config: LayoutConfig

    public init(config: LayoutConfig = LayoutConfig()) {
        self.config = config
    }

    public func layout(tree: FamilyTree, direction: LayoutDirection) -> TreeLayout {
        // Bottom-up is top-down seen in a mirror. Flipping the finished drawing keeps one
        // copy of the geometry instead of threading a sign through every lane and elbow.
        if direction == .bottomUp {
            return flippedVertically(layout(tree: tree, direction: .topDown))
        }

        let isLeftRight = direction == .leftRight
        // The layout works in (cross, generation) space and is mapped to the screen last,
        // so left-right is the same algorithm with the two card dimensions swapped.
        let crossExtent = isLeftRight ? config.cardH : config.cardW
        let rowExtent = isLeftRight ? config.cardW : config.cardH

        let index = FamilyIndex(tree: tree)
        let graph = LayoutGraph(tree: tree, index: index)
        let ordering = LayoutOrdering(
            graph: graph,
            index: index,
            metrics: LayoutOrdering.Metrics(
                nodeWidth: crossExtent,
                spouseGap: config.spouseGap,
                siblingGap: config.siblingGap,
                familyGap: config.familyGap
            )
        )
        let routing = LayoutRouting(
            graph: graph,
            ordering: ordering,
            metrics: LayoutRouting.Metrics(
                rowExtent: rowExtent,
                crossExtent: crossExtent,
                minimumGap: isLeftRight ? config.vGapLR : config.vGapTB,
                pad: config.pad
            )
        )

        // Normalise the cross axis so the drawing starts one padding in.
        var minCross = CGFloat.infinity
        var maxCross = -CGFloat.infinity
        for person in tree.people {
            guard let centre = ordering.centreOf[person.id] else { continue }
            minCross = min(minCross, centre - crossExtent / 2)
            maxCross = max(maxCross, centre + crossExtent / 2)
        }
        if minCross == .infinity { minCross = 0; maxCross = 200 }
        let crossShift = config.pad - minCross

        var nodes: [TreeNode] = []
        for person in tree.people {
            guard let centre = ordering.centreOf[person.id] else { continue }
            let generation = graph.generationOf[person.id] ?? 0
            let main = routing.generationOffset[min(generation, routing.generationOffset.count - 1)]
            let cross = centre + crossShift
            nodes.append(isLeftRight
                ? TreeNode(person: person, x: main, y: cross - config.cardH / 2)
                : TreeNode(person: person, x: cross - config.cardW / 2, y: main))
        }

        func place(_ point: CGPoint) -> CGPoint {
            isLeftRight
                ? CGPoint(x: point.y, y: point.x + crossShift)
                : CGPoint(x: point.x + crossShift, y: point.y)
        }
        func place(_ segment: LinkSegment) -> LinkSegment {
            LinkSegment(from: place(segment.from), to: place(segment.to))
        }

        let crossSpan = maxCross - minCross + 2 * config.pad
        let mainSpan = routing.totalExtent + config.pad

        return TreeLayout(
            nodes: nodes,
            links: routing.links.map { TreeLink(id: $0.id, segments: $0.segments.map(place)) },
            highlightRoutes: routing.highlightRoutes.map {
                TreeHighlightRoute(id: $0.id, segments: $0.segments.map(place), connections: $0.connections)
            },
            unionAnchors: routing.unionAnchors.map {
                TreeLayout.UnionAnchor(id: $0.id, point: place($0.point))
            },
            totalWidth: max(isLeftRight ? mainSpan : crossSpan, 600),
            totalHeight: max(isLeftRight ? crossSpan : mainSpan, 400)
        )
    }

    /// Mirror a finished layout about the horizontal centre line of its own canvas.
    /// Cards are placed by their top-left corner, so a node's flipped origin has to
    /// account for the card's own height; bare points do not.
    private func flippedVertically(_ layout: TreeLayout) -> TreeLayout {
        let height = layout.totalHeight
        let cardH = config.cardH
        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: height - point.y)
        }

        return TreeLayout(
            nodes: layout.nodes.map {
                TreeNode(person: $0.person, x: $0.x, y: height - $0.y - cardH)
            },
            links: layout.links.map { link in
                TreeLink(
                    id: link.id,
                    segments: link.segments.map { LinkSegment(from: flip($0.from), to: flip($0.to)) }
                )
            },
            highlightRoutes: layout.highlightRoutes.map { route in
                TreeHighlightRoute(
                    id: route.id,
                    segments: route.segments.map { LinkSegment(from: flip($0.from), to: flip($0.to)) },
                    connections: route.connections
                )
            },
            unionAnchors: layout.unionAnchors.map {
                TreeLayout.UnionAnchor(id: $0.id, point: flip($0.point))
            },
            totalWidth: layout.totalWidth,
            totalHeight: height
        )
    }
}
