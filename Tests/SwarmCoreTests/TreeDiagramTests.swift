import Foundation
@testable import SwarmCore
import Testing

/// The library card no longer shows a photograph, so this diagram is the only thing that
/// distinguishes one record from another at a glance — and it is only worth anything if it
/// is a faithful small copy of the tree the card opens. These cover the crop, the
/// normalisation, and the shapes real archives come in.
struct TreeDiagramTests {
    /// Couple → two children → one grandchild, plus a line of descendants below the crop.
    private func sampleTree(extraGenerations: Int = 0) -> FamilyTree {
        let tree = FamilyTree(name: "Соколовы")
        let father = Person(givenNames: "Иван", surname: "Соколов", sex: .male)
        let mother = Person(givenNames: "Мария", surname: "Соколова", sex: .female)
        let son = Person(givenNames: "Пётр", surname: "Соколов", sex: .male)
        let daughter = Person(givenNames: "Анна", surname: "Соколова", sex: .female)
        let grandson = Person(givenNames: "Лев", surname: "Соколов", sex: .male)
        tree.people = [father, mother, son, daughter, grandson]
        tree.homePersonId = father.id

        let root = Union(partner1Id: father.id, partner2Id: mother.id, childrenIds: [son.id, daughter.id])
        tree.unions = [root, Union(partner1Id: son.id, childrenIds: [grandson.id])]
        tree.rootUnionId = root.id

        var previous = grandson
        for index in 0 ..< extraGenerations {
            let person = Person(givenNames: "Потомок \(index)", surname: "Соколов")
            tree.people.append(person)
            tree.unions.append(Union(partner1Id: previous.id, childrenIds: [person.id]))
            previous = person
        }
        return tree
    }

    /// The card shows the whole record. Anything less is a lie told with a picture.
    @Test func drawsEveryPersonInTheRecord() {
        let tree = sampleTree()
        let diagram = TreeDiagram(tree: tree)

        #expect(diagram.nodes.count == tree.people.count)
        #expect(Set(diagram.nodes.map(\.personId)) == Set(tree.people.map(\.id)))
        #expect(!diagram.isEmpty)
        #expect(diagram.generationCount == 3)
    }

    /// The caption counts what the drawing contains, so the two can never disagree — the
    /// bug that had a four-generation caption over a picture of three.
    @Test func captionMatchesTheDrawing() {
        for extra in [0, 3, 5] {
            let diagram = TreeDiagram(tree: sampleTree(extraGenerations: extra))
            let drawnRows = Set(diagram.nodes.map { ($0.y * 100).rounded() }).count
            #expect(diagram.generationCount == drawnRows)
            #expect(diagram.generationCount == 3 + extra)
        }
    }

    /// A deep line has to be present in full, not cropped to the top of the record.
    @Test func deepRecordIsDrawnWhole() {
        let tree = sampleTree(extraGenerations: 5)
        let diagram = TreeDiagram(tree: tree)

        #expect(diagram.nodes.count == tree.people.count)
        #expect(diagram.generationCount == 8)
    }

    @Test func everyPositionLandsInsideTheUnitBox() {
        for tree in [sampleTree(), sampleTree(extraGenerations: 4)] {
            let diagram = TreeDiagram(tree: tree)
            for node in diagram.nodes {
                #expect(node.x >= 0 && node.x <= 1)
                #expect(node.y >= 0 && node.y <= 1)
            }
        }
    }

    /// Generations must stay generations: everyone in a row shares a y.
    @Test func rowsShareOneVerticalPosition() {
        let diagram = TreeDiagram(tree: sampleTree())
        let rows = Set(diagram.nodes.map { ($0.y * 1000).rounded() })
        #expect(rows.count == 3)
    }

    @Test func marksTheHomePersonAndCarriesSex() {
        let diagram = TreeDiagram(tree: sampleTree())

        #expect(diagram.nodes.filter(\.isHome).count == 1)
        #expect(diagram.nodes.first(where: \.isHome)?.sex == .male)
        #expect(diagram.nodes.contains { $0.sex == .female })
    }

    /// The connectors are the engine's own, so a tree with relationships must draw some.
    @Test func drawsTheRealConnectors() {
        let diagram = TreeDiagram(tree: sampleTree())
        #expect(!diagram.links.isEmpty)
        for polyline in diagram.links {
            #expect(polyline.count >= 2)
            for point in polyline {
                // Connectors may run a little outside the card box (a bus sits between
                // rows), but never off into space.
                #expect(point.x > -1 && point.x < 2)
                #expect(point.y > -1 && point.y < 2)
            }
        }
    }

    /// A couple is adjacent on the same row — the thing the hand-rolled layout got wrong.
    @Test func partnersSitTogetherOnOneRow() {
        let diagram = TreeDiagram(tree: sampleTree())
        let topRow = diagram.nodes.filter { $0.y == diagram.nodes.map(\.y).min()! }
        #expect(topRow.count == 2)
        #expect(abs(topRow[0].y - topRow[1].y) < 0.001)
    }

    @Test func onePersonDrawsOneNode() {
        let tree = FamilyTree(name: "Одиночка")
        let only = Person(givenNames: "Иван", surname: "Иванов")
        tree.people = [only]
        tree.homePersonId = only.id

        let diagram = TreeDiagram(tree: tree)
        #expect(diagram.nodes.count == 1)
        #expect(diagram.nodes[0].isHome)
        #expect(diagram.generationCount == 1)
        #expect(!diagram.isEmpty)
    }

    /// The onboarding preview draws exactly this: two people and no children yet.
    @Test func coupleAloneDrawsOneRow() {
        let tree = FamilyTree(name: "Пара")
        let husband = Person(givenNames: "Иван", sex: .male)
        let wife = Person(givenNames: "Мария", sex: .female)
        tree.people = [husband, wife]
        let union = Union(partner1Id: husband.id, partner2Id: wife.id)
        tree.unions = [union]
        tree.rootUnionId = union.id

        let diagram = TreeDiagram(tree: tree)
        #expect(diagram.nodes.count == 2)
        #expect(diagram.generationCount == 1)
    }

    @Test func emptyTreeDrawsNothing() {
        let diagram = TreeDiagram(tree: FamilyTree(name: "Пусто"))
        #expect(diagram.isEmpty)
        #expect(diagram.links.isEmpty)
    }

    /// A big sibling group is cropped, not shrunk — otherwise the nodes stop reading as
    /// A big sibling group is drawn in full and simply gets smaller, the way the
    /// workspace's own minimap handles a wide record.
    @Test func wideSiblingGroupIsDrawnInFull() {
        let tree = FamilyTree(name: "Большая семья")
        let father = Person(givenNames: "Иван", sex: .male)
        let mother = Person(givenNames: "Мария", sex: .female)
        var children: [Person] = []
        for index in 0 ..< 14 {
            children.append(Person(givenNames: "Ребёнок \(index)"))
        }
        tree.people = [father, mother] + children
        let root = Union(
            partner1Id: father.id,
            partner2Id: mother.id,
            childrenIds: children.map(\.id)
        )
        tree.unions = [root]
        tree.rootUnionId = root.id
        tree.homePersonId = children[10].id

        let diagram = TreeDiagram(tree: tree)
        let rows = Dictionary(grouping: diagram.nodes) { ($0.y * 1000).rounded() }
        // All fourteen siblings are drawn — a card that quietly dropped eleven of them
        // would misrepresent the size of the family at a glance.
        #expect(rows.count == 2)
        #expect(diagram.nodes.count == 16)
        // They stay side by side on one row rather than being stacked to save width.
        #expect(rows.values.contains { $0.count == 14 })
    }

    /// A merged archive holds several unrelated families. All of them belong on the card —
    /// that is what the record *is*, and a card showing one of them misstates its size.
    @Test func unrelatedFamiliesAreAllDrawn() {
        let tree = FamilyTree(name: "Две ветви")
        // Two unrelated families in one record — a merged archive looks like this.
        var people: [Person] = []
        for index in 0 ..< 8 { people.append(Person(givenNames: "Ч\(index)")) }
        tree.people = people
        let first = Union(partner1Id: people[0].id, partner2Id: people[1].id,
                          childrenIds: [people[2].id, people[3].id])
        let second = Union(partner1Id: people[4].id, partner2Id: people[5].id,
                           childrenIds: [people[6].id, people[7].id])
        tree.unions = [first, second]
        tree.rootUnionId = first.id
        tree.homePersonId = people[0].id

        let diagram = TreeDiagram(tree: tree)
        let drawn = Set(diagram.nodes.map(\.personId))
        #expect(drawn == Set(people.map(\.id)))
    }

    /// Every node must be joined to the drawing. A miniature whose nodes float free reads
    /// as a scatter of couples rather than as a family, and that is exactly what a
    /// partner-less anchor union used to produce: the engine laid the children out as
    /// separate roots and nothing connected them.
    @Test func everyNodeIsJoinedToTheDrawing() {
        // A record whose root union records the children but names no parents — an
        // import with a headless family in it.
        let tree = FamilyTree(name: "Без родителей")
        let mother = Person(givenNames: "Мария", sex: .female)
        let father = Person(givenNames: "Иван", sex: .male)
        var children: [Person] = []
        for index in 0 ..< 3 { children.append(Person(givenNames: "Ребёнок \(index)")) }
        tree.people = [father, mother] + children
        let headless = Union(childrenIds: children.map(\.id))
        let real = Union(partner1Id: father.id, partner2Id: mother.id, childrenIds: children.map(\.id))
        tree.unions = [headless, real]
        tree.rootUnionId = headless.id
        tree.homePersonId = father.id

        let diagram = TreeDiagram(tree: tree)
        #expect(diagram.nodes.count >= 3)
        assertConnected(diagram)
    }

    @Test func realFamiliesDrawAsOneConnectedShape() {
        assertConnected(TreeDiagram(tree: sampleTree()))
        assertConnected(TreeDiagram(tree: sampleTree(extraGenerations: 4)))
    }

    /// Walks the connector polylines and checks each node's rectangle is touched by one.
    private func assertConnected(
        _ diagram: TreeDiagram,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard diagram.nodes.count > 1 else { return }
        let halfW = diagram.nodeSize.width / 2
        let halfH = diagram.nodeSize.height / 2
        // A connector meets a card at its edge, so allow the node's own half-extent plus a
        // hair for the rounding the engine does.
        let slackX = halfW + 0.02
        let slackY = halfH + 0.02

        for node in diagram.nodes {
            let touched = diagram.links.contains { polyline in
                polyline.contains { point in
                    abs(point.x - node.x) <= slackX && abs(point.y - node.y) <= slackY
                }
            }
            #expect(touched, "node at (\(node.x), \(node.y)) is not joined to anything", sourceLocation: sourceLocation)
        }
    }

    @Test func aspectDescribesTheCroppedShape() {
        let diagram = TreeDiagram(tree: sampleTree())
        // Three generations of a small family are wider than they are tall.
        #expect(diagram.aspect > 1)
        #expect(diagram.aspect.isFinite)
    }

    @Test func storeCachesUntilTheTreeIsWrittenAgain() {
        let store = TreeStore(storageFolder: FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-diagram-cache-\(UUID().uuidString)", isDirectory: true))
        let tree = sampleTree()

        let first = store.diagram(for: tree)
        #expect(store.diagram(for: tree) == first)

        // A write bumps `updatedAt`, and the new shape has to show up on the card.
        tree.people.removeLast()
        tree.unions.removeLast()
        tree.updatedAt = Date().addingTimeInterval(1)
        #expect(store.diagram(for: tree).nodes.count == 4)
    }

    /// The library paints a whole grid at once, so one diagram must stay cheap even for a
    /// record far larger than anything the card will show.
    @Test func largeRecordStaysFastEnoughForAGrid() {
        let tree = FamilyTree(name: "Большой архив")
        var previousGeneration: [Person] = []
        for generation in 0 ..< 8 {
            var current: [Person] = []
            for index in 0 ..< 25 {
                current.append(Person(givenNames: "П\(generation)-\(index)"))
            }
            tree.people.append(contentsOf: current)
            for (index, parent) in previousGeneration.enumerated() where index < current.count {
                tree.unions.append(Union(partner1Id: parent.id, childrenIds: [current[index].id]))
            }
            previousGeneration = current
        }
        tree.homePersonId = tree.people.first?.id

        let started = Date()
        let diagram = TreeDiagram(tree: tree)
        let elapsed = Date().timeIntervalSince(started)

        #expect(!diagram.isEmpty)
        // Generous: this is one uncached build of a 200-person record. It exists to catch
        // an accidental quadratic, not to police milliseconds.
        #expect(elapsed < 2.0)
    }
}
