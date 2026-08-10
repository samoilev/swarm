import CoreGraphics
import Foundation
@testable import SwarmCore
import Testing

/// Structural guarantees the layout engine must hold for *any* tree, checked by both the
/// hand-built fixtures and the real-world corpus.
///
/// These exist because the previous engine's only overlap assertion ran on a five-person
/// family, which could not reach the code paths that actually failed — lines crossing
/// cards, spouses stranded in separate bands, buses cutting through a generation.
enum LayoutInvariants {

    struct Violation: CustomStringConvertible {
        let rule: String
        let detail: String
        var description: String { "\(rule): \(detail)" }
    }

    static func check(
        tree: FamilyTree,
        direction: LayoutDirection,
        config: LayoutConfig = LayoutConfig()
    ) -> [Violation] {
        let engine = TreeLayoutEngine(config: config)
        let layout = engine.layout(tree: tree, direction: direction)
        var violations: [Violation] = []

        /// Cards keep their on-screen size in every direction; only their placement changes.
        func rect(_ node: TreeNode) -> CGRect {
            CGRect(x: node.x, y: node.y, width: config.cardW, height: config.cardH)
        }
        let names = Dictionary(
            layout.nodes.map { ($0.person.id, $0.person.fullName) },
            uniquingKeysWith: { first, _ in first }
        )

        // 1 — cards never overlap.
        let nodes = layout.nodes
        for i in 0 ..< nodes.count {
            for j in (i + 1) ..< nodes.count {
                let a = rect(nodes[i]).insetBy(dx: 0.5, dy: 0.5)
                if a.intersects(rect(nodes[j])) {
                    violations.append(Violation(
                        rule: "cards overlap",
                        detail: "\(nodes[i].person.fullName) ↔ \(nodes[j].person.fullName)"
                    ))
                }
            }
        }

        // 2 — no connector crosses a card. A segment may touch the card it starts or ends
        // at, so the card rects are shrunk by a hair and endpoints sitting exactly on an
        // edge are allowed.
        let cards = nodes.map { (id: $0.person.id, rect: rect($0)) }
        for link in layout.links {
            for segment in link.segments {
                for card in cards {
                    let probe = card.rect.insetBy(dx: 1, dy: 1)
                    guard segmentIntersects(segment, probe) else { continue }
                    violations.append(Violation(
                        rule: "connector crosses a card",
                        detail: "\(link.id) crosses \(names[card.id] ?? "?")"
                    ))
                }
            }
        }

        // 3 — determinism.
        if engine.layout(tree: tree, direction: direction) != layout {
            violations.append(Violation(rule: "layout is not deterministic", detail: ""))
        }

        // 4 — everybody is placed exactly once.
        if layout.nodes.count != tree.people.count {
            violations.append(Violation(
                rule: "not every person is placed",
                detail: "\(layout.nodes.count) of \(tree.people.count)"
            ))
        }

        // 5 — every union that actually shows a relationship gets an anchor, so no
        // marriage and no parentage is routed from nowhere. A one-partner childless record
        // shows nothing and is exempt.
        let markerIds = Set(layout.unionAnchors.map(\.id))
        let placedIds = Set(layout.nodes.map(\.person.id))
        for union in tree.unions {
            let placed = union.partnerIds.filter(placedIds.contains)
            let children = union.childrenIds.filter(placedIds.contains)
            guard placed.count == 2 || (!placed.isEmpty && !children.isEmpty) else { continue }
            if !markerIds.contains(union.id) {
                violations.append(Violation(rule: "union has no anchor", detail: union.id.uuidString))
            }
        }

        // 6 — the drawing actually joins the people it claims to. Segments that stop in
        // mid-air are the visible symptom; this walks the ink itself, so a connector that
        // is emitted but never reaches its endpoints is caught rather than assumed.
        for union in tree.unions {
            let placed = union.partnerIds.filter(placedIds.contains)
            guard placed.count == 2, let a = cards.first(where: { $0.id == placed[0] }),
                  let b = cards.first(where: { $0.id == placed[1] }) else { continue }
            if !inkConnects(a.rect, b.rect, via: layout.links.flatMap(\.segments)) {
                violations.append(Violation(
                    rule: "partners are not joined by any line",
                    detail: "\(names[placed[0]] ?? "?") ↔ \(names[placed[1]] ?? "?")"
                ))
            }
            for child in union.childrenIds where placedIds.contains(child) {
                guard let c = cards.first(where: { $0.id == child }) else { continue }
                if !inkConnects(a.rect, c.rect, via: layout.links.flatMap(\.segments)) {
                    violations.append(Violation(
                        rule: "child is not joined to its parent by any line",
                        detail: "\(names[placed[0]] ?? "?") → \(names[child] ?? "?")"
                    ))
                }
            }
        }

        // 7 — no two families' lanes meet end to end. Two buses that touch on the same
        // horizontal read as a single line, which makes somebody's sibling look like the
        // neighbouring couple's child.
        //
        // Checked top-down only: the guarantee lives in lane space, which the left-right
        // mapping merely transposes, and the mirror shares its geometry. Segments of one
        // union are exempt (they are one connector), as are two records of the same couple,
        // which a GEDCOM may legitimately hold twice.
        if direction == .topDown {
            let partnersOf = Dictionary(
                tree.unions.map { ($0.id, Set($0.partnerIds)) },
                uniquingKeysWith: { first, _ in first }
            )
            let horizontals = layout.links
                .compactMap { link -> (union: UUID, segment: LinkSegment)? in
                    guard let union = unionID(inLink: link.id) else { return nil }
                    guard let bar = link.segments.first(where: {
                        $0.from.y == $0.to.y && $0.from.x != $0.to.x
                    }) else { return nil }
                    return (union, bar)
                }
            for i in 0 ..< horizontals.count {
                for j in (i + 1) ..< horizontals.count {
                    let a = horizontals[i], b = horizontals[j]
                    guard a.union != b.union, a.segment.from.y == b.segment.from.y else { continue }
                    guard partnersOf[a.union] != partnersOf[b.union] else { continue }
                    let aSpan = (min(a.segment.from.x, a.segment.to.x), max(a.segment.from.x, a.segment.to.x))
                    let bSpan = (min(b.segment.from.x, b.segment.to.x), max(b.segment.from.x, b.segment.to.x))
                    if max(aSpan.0, bSpan.0) - min(aSpan.1, bSpan.1) < 8 {
                        violations.append(Violation(
                            rule: "two lanes touch and read as one line",
                            detail: "\(a.union) / \(b.union)"
                        ))
                    }
                }
            }
        }

        // 8 — a highlight route joins the two cards it claims to. The overlay is drawn from
        // these segments alone, so a route that relies on a neutral line to bridge its two
        // halves lights up as two disconnected stubs.
        for route in layout.highlightRoutes where route.id.hasPrefix("marriage-") {
            guard let connection = route.connections.first,
                  let a = cards.first(where: { $0.id == connection.firstID }),
                  let b = cards.first(where: { $0.id == connection.secondID }) else { continue }
            if !inkConnects(a.rect, b.rect, via: route.segments) {
                violations.append(Violation(
                    rule: "marriage highlight does not join the partners",
                    detail: "\(names[connection.firstID] ?? "?") ↔ \(names[connection.secondID] ?? "?")"
                ))
            }
        }

        return violations
    }

    /// The union a link belongs to. Ids look like `marriage-<uuid>` or
    /// `children-<uuid>-trunk`, so the first UUID in the string is the one.
    private static func unionID(inLink id: String) -> UUID? {
        guard let start = id.firstIndex(of: "-") else { return nil }
        let rest = id[id.index(after: start)...]
        return UUID(uuidString: String(rest.prefix(36)))
    }

    /// Flood-fill the drawn segments and check the two cards end up in the same component.
    /// Segments join where they share an endpoint or where one ends on another's interior —
    /// a T-junction, which is how every bus meets its stems.
    private static func inkConnects(_ from: CGRect, _ to: CGRect, via segments: [LinkSegment]) -> Bool {
        let live = segments.filter { $0.from != $0.to }
        var adjacency = Array(repeating: Set<Int>(), count: live.count)
        for i in 0 ..< live.count {
            for j in (i + 1) ..< live.count where touches(live[i], live[j]) {
                adjacency[i].insert(j)
                adjacency[j].insert(i)
            }
        }

        func meets(_ rect: CGRect, _ segment: LinkSegment) -> Bool {
            let probe = rect.insetBy(dx: -1.5, dy: -1.5)
            return probe.contains(segment.from) || probe.contains(segment.to)
        }
        let starts = live.indices.filter { meets(from, live[$0]) }
        let goals = Set(live.indices.filter { meets(to, live[$0]) })
        guard !starts.isEmpty, !goals.isEmpty else { return false }

        var seen = Set(starts)
        var stack = starts
        while let next = stack.popLast() {
            if goals.contains(next) { return true }
            for neighbour in adjacency[next] where seen.insert(neighbour).inserted {
                stack.append(neighbour)
            }
        }
        return false
    }

    /// Two axis-aligned segments touch when they share a point, endpoints included.
    private static func touches(_ a: LinkSegment, _ b: LinkSegment) -> Bool {
        let ax = (min(a.from.x, a.to.x), max(a.from.x, a.to.x))
        let ay = (min(a.from.y, a.to.y), max(a.from.y, a.to.y))
        let bx = (min(b.from.x, b.to.x), max(b.from.x, b.to.x))
        let by = (min(b.from.y, b.to.y), max(b.from.y, b.to.y))
        let slack: CGFloat = 0.5
        return ax.0 - slack <= bx.1 && bx.0 - slack <= ax.1
            && ay.0 - slack <= by.1 && by.0 - slack <= ay.1
    }

    /// Generation index of every person, read back from the engine's own graph so tests can
    /// assert on rows without duplicating the layering rules.
    static func generations(of tree: FamilyTree) -> [UUID: Int] {
        LayoutGraph(tree: tree, index: FamilyIndex(tree: tree)).generationOf
    }

    /// How many times two connector segments cross at a point that is not a shared
    /// endpoint. Collinear overlap does not count — two runs sharing a lane are meant to
    /// merge into one line. This is the number the routing is tuned against.
    static func connectorCrossings(
        tree: FamilyTree,
        direction: LayoutDirection = .topDown,
        config: LayoutConfig = LayoutConfig()
    ) -> Int {
        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: direction)
        let segments = layout.links.flatMap(\.segments).filter {
            $0.from != $0.to
        }
        var total = 0
        for i in 0 ..< segments.count {
            for j in (i + 1) ..< segments.count where properlyCross(segments[i], segments[j]) {
                total += 1
            }
        }
        return total
    }

    /// True when two axis-aligned segments meet at an interior point of at least one of
    /// them — a real visual crossing, not a T-junction where a stem meets its own bus.
    private static func properlyCross(_ a: LinkSegment, _ b: LinkSegment) -> Bool {
        let aVertical = a.from.x == a.to.x
        let bVertical = b.from.x == b.to.x
        guard aVertical != bVertical else { return false } // parallel: overlap is merging
        let (v, h) = aVertical ? (a, b) : (b, a)
        let x = v.from.x
        let y = h.from.y
        let vLo = min(v.from.y, v.to.y), vHi = max(v.from.y, v.to.y)
        let hLo = min(h.from.x, h.to.x), hHi = max(h.from.x, h.to.x)
        // Strictly inside both spans: touching an endpoint is a junction, not a crossing.
        return x > hLo && x < hHi && y > vLo && y < vHi
    }

    // MARK: - Geometry

    /// Liang–Barsky clip: true when the segment passes through the rectangle's interior.
    static func segmentIntersects(_ segment: LinkSegment, _ rect: CGRect) -> Bool {
        guard !rect.isEmpty else { return false }
        let dx = segment.to.x - segment.from.x
        let dy = segment.to.y - segment.from.y
        var t0: CGFloat = 0
        var t1: CGFloat = 1
        let checks: [(p: CGFloat, q: CGFloat)] = [
            (-dx, segment.from.x - rect.minX),
            (dx, rect.maxX - segment.from.x),
            (-dy, segment.from.y - rect.minY),
            (dy, rect.maxY - segment.from.y),
        ]
        for check in checks {
            if check.p == 0 {
                if check.q < 0 { return false }
                continue
            }
            let r = check.q / check.p
            if check.p < 0 {
                if r > t1 { return false }
                if r > t0 { t0 = r }
            } else {
                if r < t0 { return false }
                if r < t1 { t1 = r }
            }
        }
        return t0 < t1
    }
}
