import CoreGraphics
import Foundation
@testable import SwarmCore
import Testing

struct LayoutEngineTests {

    private let config = LayoutConfig()

    /// dad+mom → c1, c2, c3, with c1 as the home person.
    private func familyTree() -> (FamilyTree, [Person]) {
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let c1 = Person(givenNames: "Раз", sex: .male)
        let c2 = Person(givenNames: "Два", sex: .female)
        let c3 = Person(givenNames: "Три", sex: .male)
        let t = FamilyTree(name: "T")
        t.people = [dad, mom, c1, c2, c3]
        let u = Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [c1.id, c2.id, c3.id])
        t.unions = [u]
        t.homePersonId = c1.id
        t.rootUnionId = u.id
        return (t, [dad, mom, c1, c2, c3])
    }

    private func rect(_ n: TreeNode) -> CGRect {
        CGRect(x: n.x, y: n.y, width: config.cardW, height: config.cardH)
    }

    @Test func placesEveryPerson() {
        let (t, _) = familyTree()
        let layout = TreeLayoutEngine(config: config).layout(tree: t, direction: .topDown)
        #expect(layout.nodes.count == t.people.count)
        #expect(layout.totalWidth > 0 && layout.totalHeight > 0)
    }

    @Test func isDeterministic() {
        let (t, _) = familyTree()
        let engine = TreeLayoutEngine(config: config)
        #expect(engine.layout(tree: t, direction: .topDown) == engine.layout(tree: t, direction: .topDown))
    }

    @Test func cardsDoNotOverlap() {
        let (t, _) = familyTree()
        let nodes = TreeLayoutEngine(config: config).layout(tree: t, direction: .topDown).nodes
        for i in 0 ..< nodes.count {
            for j in (i + 1) ..< nodes.count {
                let a = rect(nodes[i]).insetBy(dx: 0.5, dy: 0.5) // tolerate exact edge touching
                #expect(a.intersects(rect(nodes[j])) == false,
                        "\(nodes[i].person.givenNames) overlaps \(nodes[j].person.givenNames)")
            }
        }
    }

    @Test func parentsCenteredOverChildren() {
        let (t, p) = familyTree()
        let nodes = TreeLayoutEngine(config: config).layout(tree: t, direction: .topDown).nodes
        func centerX(_ person: Person) -> CGFloat {
            let n = nodes.first { $0.person.id == person.id }!
            return n.x + config.cardW / 2
        }
        let parentMid = (centerX(p[0]) + centerX(p[1])) / 2
        let childXs = [centerX(p[2]), centerX(p[3]), centerX(p[4])]
        let childMid = childXs.reduce(0, +) / CGFloat(childXs.count)
        // The couple sits centered over their children's span.
        #expect(parentMid >= childXs.min()! && parentMid <= childXs.max()!)
        #expect(abs(parentMid - childMid) < config.cardW)
    }

    @Test func leftRightDirectionAlsoLaysOut() {
        let (t, _) = familyTree()
        let layout = TreeLayoutEngine(config: config).layout(tree: t, direction: .leftRight)
        #expect(layout.nodes.count == t.people.count)
        #expect(layout.totalWidth > 0 && layout.totalHeight > 0)
    }

    @Test(arguments: [LayoutDirection.topDown, .bottomUp, .leftRight])
    func childBranchesCarryIndependentHighlightRoutes(direction: LayoutDirection) throws {
        let (t, people) = familyTree()
        let layout = TreeLayoutEngine(config: config).layout(tree: t, direction: direction)
        let parents = Array(people.prefix(2))
        let children = Array(people.dropFirst(2))
        let childRoutes = layout.highlightRoutes.filter { $0.id.contains("-route-") }

        #expect(childRoutes.count == children.count)
        for child in children {
            let route = try #require(
                childRoutes.first { $0.id.hasSuffix(child.id.uuidString) }
            )
            #expect(route.connections == Set(parents.map {
                FamilyConnection($0.id, child.id)
            }))
            #expect(route.segments.count == 3)

            let stem = route.segments[0]
            let branch = route.segments[1]
            let drop = route.segments[2]
            #expect(stem.to == branch.from)
            #expect(branch.to == drop.from)
            if direction != .leftRight {
                #expect(branch.from.y == branch.to.y)
                #expect(drop.from.x == drop.to.x)
            } else {
                #expect(branch.from.x == branch.to.x)
                #expect(drop.from.y == drop.to.y)
            }
        }

        let marriage = try #require(
            layout.highlightRoutes.first { $0.id.hasPrefix("marriage-") }
        )
        #expect(marriage.connections == [
            FamilyConnection(parents[0].id, parents[1].id),
        ])
    }

    /// Bottom-up is the top-down drawing mirrored: same canvas, same columns, same
    /// spacing — parents below their children instead of above.
    @Test func bottomUpMirrorsTopDown() throws {
        let (t, people) = familyTree()
        let engine = TreeLayoutEngine(config: config)
        let down = engine.layout(tree: t, direction: .topDown)
        let up = engine.layout(tree: t, direction: .bottomUp)

        #expect(up.totalWidth == down.totalWidth)
        #expect(up.totalHeight == down.totalHeight)
        #expect(up.nodes.count == down.nodes.count)

        for upNode in up.nodes {
            let downNode = try #require(down.nodes.first { $0.person.id == upNode.person.id })
            #expect(upNode.x == downNode.x)
            #expect(upNode.y == down.totalHeight - downNode.y - config.cardH)
        }

        // The point of the mode: a parent sits below their child, not above.
        let dad = try #require(up.nodes.first { $0.person.id == people[0].id })
        let child = try #require(up.nodes.first { $0.person.id == people[2].id })
        #expect(dad.y > child.y)

        // Cards must not collide after the flip either.
        for i in 0 ..< up.nodes.count {
            for j in (i + 1) ..< up.nodes.count {
                let a = rect(up.nodes[i]).insetBy(dx: 0.5, dy: 0.5)
                #expect(a.intersects(rect(up.nodes[j])) == false)
            }
        }
    }

    @Test func disconnectedPeopleAreStillPlaced() {
        let (t, _) = familyTree()
        let loner = Person(givenNames: "Один", sex: .male)
        t.people.append(loner)
        let layout = TreeLayoutEngine(config: config).layout(tree: t, direction: .topDown)
        #expect(layout.nodes.contains { $0.person.id == loner.id })
    }
}
