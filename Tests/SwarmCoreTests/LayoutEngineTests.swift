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

    @Test func disconnectedPeopleAreStillPlaced() {
        let (t, _) = familyTree()
        let loner = Person(givenNames: "Один", sex: .male)
        t.people.append(loner)
        let layout = TreeLayoutEngine(config: config).layout(tree: t, direction: .topDown)
        #expect(layout.nodes.contains { $0.person.id == loner.id })
    }
}
