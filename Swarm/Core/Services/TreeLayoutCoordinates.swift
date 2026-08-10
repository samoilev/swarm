import CoreGraphics
import Foundation

/// Brandes–Köpf horizontal coordinate assignment.
///
/// Replaces the earlier priority/median relaxation, which only nudged vertices toward
/// their neighbours and gave up whenever separation blocked the move — so a couple with an
/// only child could sit permanently off to one side and its descent gained a kink for no
/// reason.
///
/// Brandes–Köpf works the other way round: it first *decides* which connectors to make
/// perfectly straight, chaining each vertex to the median neighbour it should line up with,
/// and only then compacts, moving whole chains rather than single vertices. A chain is
/// either placed as a unit or not at all, so an alignment it chose is never bent by a later
/// squeeze.
///
/// Two departures from the paper, both needed here:
///
///   - Vertices have different widths — a spouse chain is far wider than a lone card — so
///     the minimum distance between neighbours is a function of the pair, not a constant.
///   - Connectors do not meet vertices at their centres. A union's line leaves from the
///     midpoint of *its* two partners, which sits somewhere inside a block that may hold
///     six people, and arrives at one particular child inside the block below. Each edge
///     therefore carries a port offset, and alignment straightens `x + port`, not `x`.
///     Without this an only child would be centred under its parents' whole chain instead
///     of under the couple that had it.
///
/// Reference: Brandes & Köpf, *Fast and Simple Horizontal Coordinate Assignment*, GD 2001.
struct CoordinateAssignment {
    struct Edge: Hashable {
        let upper: Int
        let lower: Int
    }

    /// One vertex of the layered graph: a spouse block, or a dummy standing in for a
    /// connector passing through a row.
    struct Vertex {
        var layer: Int
        var position: Int
        var width: CGFloat
        var isDummy: Bool
    }

    private let vertices: [Vertex]
    private let layers: [[Int]]
    /// Neighbours one layer up, ordered by position. `delta` is what makes the connector
    /// straight: `x[v] = x[u] + delta`.
    private let upper: [[(id: Int, delta: CGFloat)]]
    private let lower: [[(id: Int, delta: CGFloat)]]
    /// Minimum centre-to-centre distance for two vertices standing side by side.
    private let stride: (Int, Int) -> CGFloat
    private let marked: Set<Edge>

    init(
        vertices: [Vertex],
        layers: [[Int]],
        edges: [(upper: Int, lower: Int, delta: CGFloat)],
        stride: @escaping (Int, Int) -> CGFloat
    ) {
        self.vertices = vertices
        self.layers = layers
        self.stride = stride

        var up = Array(repeating: [(id: Int, delta: CGFloat)](), count: vertices.count)
        var down = Array(repeating: [(id: Int, delta: CGFloat)](), count: vertices.count)
        for edge in edges {
            up[edge.lower].append((edge.upper, edge.delta))
            down[edge.upper].append((edge.lower, edge.delta))
        }
        for index in up.indices {
            up[index].sort { vertices[$0.id].position < vertices[$1.id].position }
            down[index].sort { vertices[$0.id].position < vertices[$1.id].position }
        }
        upper = up
        lower = down
        marked = Self.type1Conflicts(vertices: vertices, layers: layers, upper: up)
    }

    /// The final coordinate of every vertex.
    func coordinates() -> [CGFloat] {
        guard !vertices.isEmpty else { return [] }
        // Compact to the left and to the right off the *same* alignment, then average.
        //
        // The paper runs four passes — aligning upwards as well as downwards — and takes
        // the median. That cannot be used here: the up and down passes straighten
        // different sets of connectors, and a per-vertex median of layouts that disagree
        // keeps neither, so every descent picked up a kink and rows even overlapped
        // (a median is not affine, so it does not inherit the separation constraints).
        //
        // Two candidates sharing one alignment behave: within a chain every vertex moves
        // together, so their relative offsets are identical in both and survive averaging
        // exactly, while averaging is affine and so keeps every card apart. Left and right
        // compaction still cancel each other's bias, which is what the four passes were
        // really for.
        // One alignment, one compaction.
        //
        // The paper runs four passes — up and down, left and right — and takes the median.
        // That cannot be used here. Each pass straightens a *different* set of connectors,
        // and a per-vertex median of layouts that disagree keeps none of them, so every
        // descent picked up a kink; worse, a median is not affine, so it does not inherit
        // the separation constraints and rows overlapped outright. Sharing one alignment
        // between a left and a right compaction does not rescue it either: the algorithm's
        // correctness argument ties the block structure to the direction it is packed in,
        // and packing right against a left-built alignment overlaps cards too.
        //
        // So: one self-consistent pass, and a repair afterwards to make the separation
        // guarantee structural rather than argued.
        return repair(compact(alignment()))
    }

    // MARK: - Type-1 conflicts

    /// An edge between two dummies is a stretch of a connector passing through a row, and
    /// the layout is much easier to read if those stay vertical. Where an ordinary edge
    /// crosses one, the ordinary edge is marked and alignment leaves it alone.
    private static func type1Conflicts(
        vertices: [Vertex],
        layers: [[Int]],
        upper: [[(id: Int, delta: CGFloat)]]
    ) -> Set<Edge> {
        var marked = Set<Edge>()
        guard layers.count > 2 else { return marked }

        for index in 1 ..< (layers.count - 1) {
            let layer = layers[index + 1]
            var previous = 0
            var scanned = 0
            for (position, vertex) in layer.enumerated() {
                // The dummy that ends an inner segment, if this vertex is one.
                let innerUpper = vertices[vertex].isDummy
                    ? upper[vertex].first(where: { vertices[$0.id].isDummy })?.id
                    : nil
                guard innerUpper != nil || position == layer.count - 1 else { continue }
                let boundary = innerUpper.map { vertices[$0].position } ?? (layers[index].count - 1)

                while scanned <= position {
                    let scanning = layer[scanned]
                    for neighbour in upper[scanning] {
                        let neighbourPosition = vertices[neighbour.id].position
                        if neighbourPosition < previous || neighbourPosition > boundary {
                            marked.insert(Edge(upper: neighbour.id, lower: scanning))
                        }
                    }
                    scanned += 1
                }
                previous = boundary
            }
        }
        return marked
    }

    // MARK: - One of the four passes

    /// Chain each couple to the median child it should sit over, working bottom-up.
    ///
    /// Direction matters, and not symmetrically. Aligning downwards — each child to its
    /// parents — lets only the first of several siblings claim the couple, so parents end
    /// up over their eldest rather than over the middle of the family. Aligning upwards
    /// puts every couple over its median child, which is both the property a reader expects
    /// and, for an only child, a dead straight descent.
    private func alignment() -> Chains {
        var root = Array(vertices.indices)
        var align = Array(vertices.indices)
        var offset = Array(repeating: CGFloat(0), count: vertices.count)

        for layer in layers.dropLast().reversed() {
            var lastPlaced = -1
            for vertex in layer {
                let neighbours = lower[vertex]
                guard !neighbours.isEmpty else { continue }
                // Median neighbours: one for an odd count, the middle two for an even one.
                let middle = (neighbours.count - 1) / 2
                for index in neighbours.count % 2 == 1 ? [middle] : [middle, middle + 1] {
                    guard align[vertex] == vertex else { break }
                    let neighbour = neighbours[index]
                    guard !marked.contains(Edge(upper: vertex, lower: neighbour.id)),
                          lastPlaced < vertices[neighbour.id].position else { continue }
                    align[neighbour.id] = vertex
                    root[vertex] = root[neighbour.id]
                    align[vertex] = root[vertex]
                    // The edge's delta straightens x[lower] = x[upper] + delta, so going
                    // the other way it subtracts.
                    offset[vertex] = offset[neighbour.id] - neighbour.delta
                    lastPlaced = vertices[neighbour.id].position
                }
            }
        }
        return Chains(root: root, align: align, offset: offset)
    }

    struct Chains {
        let root: [Int]
        let align: [Int]
        let offset: [CGFloat]
    }

    /// Place each chain as a unit, packing them as tightly as the separation rules allow.
    private func compact(_ chains: Chains) -> [CGFloat] {
        let working = layers
        let root = chains.root
        let align = chains.align
        let offset = chains.offset
        var positionIn = Array(repeating: 0, count: vertices.count)
        var layerOf = Array(repeating: 0, count: vertices.count)
        for (index, layer) in working.enumerated() {
            for (position, vertex) in layer.enumerated() {
                positionIn[vertex] = position
                layerOf[vertex] = index
            }
        }
        var sink = Array(vertices.indices)
        var shift = Array(repeating: CGFloat.greatestFiniteMagnitude, count: vertices.count)
        var blockX = Array(repeating: CGFloat?.none, count: vertices.count)

        func predecessor(of vertex: Int) -> Int? {
            let layer = working[layerOf[vertex]]
            let position = positionIn[vertex]
            return position > 0 ? layer[position - 1] : nil
        }

        func place(_ block: Int) {
            guard blockX[block] == nil else { return }
            blockX[block] = 0
            var walker = block
            repeat {
                if let previous = predecessor(of: walker) {
                    let other = root[previous]
                    place(other)
                    if sink[block] == block { sink[block] = sink[other] }
                    // Minimum gap, corrected for where each vertex sits inside its chain.
                    let gap = stride(previous, walker) + offset[previous] - offset[walker]
                    if sink[block] != sink[other] {
                        shift[sink[other]] = min(shift[sink[other]], blockX[block]! - blockX[other]! - gap)
                    } else {
                        blockX[block] = max(blockX[block]!, blockX[other]! + gap)
                    }
                }
                walker = align[walker]
            } while walker != block
        }

        for vertex in vertices.indices where root[vertex] == vertex { place(vertex) }

        var x = Array(repeating: CGFloat(0), count: vertices.count)
        for vertex in vertices.indices {
            let block = root[vertex]
            x[vertex] = blockX[block]! + offset[vertex]
            let sunk = shift[sink[block]]
            if sunk < .greatestFiniteMagnitude { x[vertex] += sunk }
        }
        return x
    }

    // MARK: - Repair

    /// Walk each layer once and push anything that ended up too close. Nothing should be:
    /// this is the cheap proof that no card can overlap another, whatever the compaction
    /// did.
    private func repair(_ x: [CGFloat]) -> [CGFloat] {
        var x = x
        for layer in layers {
            for position in layer.indices.dropFirst() {
                let left = layer[position - 1], right = layer[position]
                x[right] = max(x[right], x[left] + stride(left, right))
            }
        }
        return x
    }
}
