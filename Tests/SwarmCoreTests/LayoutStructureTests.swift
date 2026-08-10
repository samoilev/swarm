import CoreGraphics
import Foundation
@testable import SwarmCore
import Testing

/// The specific structures that the previous engine got wrong, asserted directly rather
/// than through a general invariant.
struct LayoutStructureTests {

    private let config = LayoutConfig()

    private func nodesByRow(_ layout: TreeLayout) -> [CGFloat: [TreeNode]] {
        Dictionary(grouping: layout.nodes, by: \.y).mapValues { $0.sorted { $0.x < $1.x } }
    }

    // MARK: - Spouses

    /// The headline complaint: partners drifting apart.
    ///
    /// A couple is drawn as neighbouring cards. The one thing that can override it is
    /// serial remarriage — one card per person means somebody with six spouses can only
    /// touch two of them — so a non-adjacent union is only acceptable when one of its
    /// partners is married more than once. Anything else is the old banding bug returning.
    @Test(arguments: LayoutCorpusTests.corpus)
    func couplesAreAdjacentUnlessSomebodyRemarried(name: String) throws {
        let tree = try LayoutCorpusTests.load(name)
        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        let rows = nodesByRow(layout)
        let placed = Set(layout.nodes.map(\.person.id))
        let index = FamilyIndex(tree: tree)

        for union in tree.unions {
            let partners = union.partnerIds.filter(placed.contains)
            guard partners.count == 2 else { continue }
            guard let row = rows.values.first(where: { row in
                row.contains { $0.person.id == partners[0] }
            }) else { continue }

            guard let first = row.firstIndex(where: { $0.person.id == partners[0] }),
                  let second = row.firstIndex(where: { $0.person.id == partners[1] })
            else {
                Issue.record("\(name): partners of a union are not on the same row")
                continue
            }
            guard abs(first - second) != 1 else { continue }

            let remarried = partners.contains { (index.unionsOf[$0]?.count ?? 0) > 1 }
            #expect(remarried, """
            \(name): \(index.byId[partners[0]]?.fullName ?? "?") and \
            \(index.byId[partners[1]]?.fullName ?? "?") are \(abs(first - second)) cards apart \
            but neither of them married more than once
            """)
        }
    }

    /// The pivot of a spouse chain touches two partners.
    ///
    /// This is what the alternating fan buys: partners are placed to either side in
    /// marriage order rather than strung out on one, so the two innermost marriages need no
    /// routing at all and each further pair shares a lane. A one-sided chain would leave the
    /// pivot touching one spouse and need a lane per marriage.
    @Test(arguments: LayoutCorpusTests.corpus)
    func theHubOfASpouseChainTouchesTwoPartners(name: String) throws {
        let tree = try LayoutCorpusTests.load(name)
        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        let rows = nodesByRow(layout)
        let placed = Set(layout.nodes.map(\.person.id))
        let index = FamilyIndex(tree: tree)

        for person in tree.people {
            let partners = Set((index.unionsOf[person.id] ?? [])
                .flatMap(\.partnerIds)
                .filter { $0 != person.id && placed.contains($0) })
            // Three or more partners makes this person the hub of their chain.
            guard partners.count >= 3 else { continue }
            guard let row = rows.values.first(where: { $0.contains { $0.person.id == person.id } }),
                  let position = row.firstIndex(where: { $0.person.id == person.id }) else { continue }

            let neighbours = Set([position - 1, position + 1]
                .filter { row.indices.contains($0) }
                .map { row[$0].person.id })
            let touching = neighbours.intersection(partners).count
            #expect(touching == 2,
                    "\(name): \(person.fullName) has \(partners.count) partners but touches \(touching)")
        }
    }

    /// A person with many marriages — Henry VIII has six, and three Roosevelts have four or
    /// five. Every spouse belongs on the same row, and each union keeps its own anchor so
    /// its children hang off their own partnership rather than a shared one.
    @Test(arguments: LayoutCorpusTests.corpus)
    func serialRemarriageStaysOnOneRow(name: String) throws {
        let tree = try LayoutCorpusTests.load(name)
        let index = FamilyIndex(tree: tree)
        let generations = LayoutInvariants.generations(of: tree)
        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        let markers = Dictionary(
            layout.unionAnchors.map { ($0.id, $0.point) },
            uniquingKeysWith: { first, _ in first }
        )

        for person in tree.people {
            let unions = index.unionsOf[person.id] ?? []
            guard unions.count > 1 else { continue }
            let row = generations[person.id]

            for union in unions {
                for partner in union.partnerIds where partner != person.id && index.byId[partner] != nil {
                    #expect(generations[partner] == row,
                            "\(name): \(person.fullName)'s partner is on a different row")
                }
                #expect(markers[union.id] != nil,
                        "\(name): a union of \(person.fullName) has no anchor")
            }

            // Distinct partnerships must not share an anchor, or the drawing cannot say
            // which children belong to which marriage. Grouped by partner set, a file can
            // legitimately hold two FAM records for one couple — the Романовы tree records
            // Alexander II and Ekaterina Dolgorukova twice — and those *should* coincide.
            let points = Dictionary(
                grouping: unions.filter { markers[$0.id] != nil },
                by: { Set($0.partnerIds) }
            ).compactMapValues { markers[$0[0].id] }
            let distinct = Set(points.values.map { "\(Int($0.x.rounded()))×\(Int($0.y.rounded()))" })
            #expect(distinct.count == points.count,
                    "\(name): \(person.fullName)'s marriages share an anchor position")
        }
    }

    /// Children of different partnerships stay in their own group under their own union —
    /// the Романовы tree has thirty-two half-sibling pairs and Alexander II's two families
    /// must not comb together.
    @Test(arguments: LayoutCorpusTests.corpus)
    func halfSiblingSetsDoNotInterleave(name: String) throws {
        let tree = try LayoutCorpusTests.load(name)
        let index = FamilyIndex(tree: tree)
        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        let centre = Dictionary(
            layout.nodes.map { ($0.person.id, $0.x + config.cardW / 2) },
            uniquingKeysWith: { first, _ in first }
        )

        for person in tree.people {
            let sets = (index.unionsOf[person.id] ?? [])
                .map { union in union.childrenIds.compactMap { centre[$0] } }
                .filter { $0.count > 1 }
            guard sets.count > 1 else { continue }

            for i in 0 ..< sets.count {
                for j in (i + 1) ..< sets.count {
                    let a = try (#require(sets[i].min()), #require(sets[i].max()))
                    let b = try (#require(sets[j].min()), #require(sets[j].max()))
                    #expect(a.1 < b.0 || b.1 < a.0,
                            "\(name): two child sets of \(person.fullName) overlap: \(a) vs \(b)")
                }
            }
        }
    }

    // MARK: - Long edges

    /// Siblings share a row and so do partners, but the two rules can collide: here Diana
    /// marries her own nephew Evan, so she cannot be both level with her brother Carl and
    /// level with Carl's son. The layering keeps the sibling row and lets that one marriage
    /// span two rows — which drops their daughter two rows below her parents' union, the
    /// case the old engine drew straight through the intervening row.
    @Test func aMarriageAcrossGenerationsRoutesWithoutCuttingTheRowBetween() throws {
        let ada = Person(givenNames: "Ada", sex: .female)
        let bram = Person(givenNames: "Bram", sex: .male)
        let carl = Person(givenNames: "Carl", sex: .male)
        let diana = Person(givenNames: "Diana", sex: .female)
        let evan = Person(givenNames: "Evan", sex: .male)
        let fern = Person(givenNames: "Fern", sex: .female)

        let tree = FamilyTree(name: "Askew")
        tree.people = [ada, bram, carl, diana, evan, fern]
        let elders = Union(partner1Id: bram.id, partner2Id: ada.id, childrenIds: [carl.id, diana.id])
        let carlsChild = Union(partner1Id: carl.id, childrenIds: [evan.id])
        let acrossRows = Union(partner1Id: evan.id, partner2Id: diana.id, childrenIds: [fern.id])
        tree.unions = [elders, carlsChild, acrossRows]
        tree.homePersonId = bram.id
        tree.rootUnionId = elders.id

        let generations = LayoutInvariants.generations(of: tree)
        let carlRow = try #require(generations[carl.id])
        #expect(generations[diana.id] == carlRow, "siblings keep their row")
        #expect(generations[evan.id] == carlRow + 1)
        let fernRow = try #require(generations[fern.id])
        #expect(fernRow - carlRow > 1, "so the connector down to Fern spans more than one gap")

        // That connector must not touch anything on the row it passes through.
        let violations = LayoutInvariants.check(tree: tree, direction: .topDown)
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "; "))")
    }

    /// An unmarried sibling goes on the free side of their married sibling, not beyond the
    /// in-law. Placed the other way round, the parents' bus has to reach over the spouse to
    /// get to their own child, and the reader sees a line cutting across an unrelated
    /// couple. Both orderings are otherwise equal, so only the sibling's own side settles it.
    @Test func anUnmarriedSiblingSitsOnTheFreeSideOfTheMarriedOne() throws {
        let dad = Person(givenNames: "Дед", sex: .male)
        let mum = Person(givenNames: "Баба", sex: .female)
        let married = Person(givenNames: "Лев", sex: .male)
        let single = Person(givenNames: "Никита", sex: .male)
        let spouse = Person(givenNames: "Юлия", sex: .female)
        let inLawDad = Person(givenNames: "Тесть", sex: .male)
        let inLawMum = Person(givenNames: "Тёща", sex: .female)

        let tree = FamilyTree(name: "Side")
        tree.people = [dad, mum, married, single, spouse, inLawDad, inLawMum]
        tree.unions = [
            Union(partner1Id: dad.id, partner2Id: mum.id, childrenIds: [single.id, married.id]),
            Union(partner1Id: inLawDad.id, partner2Id: inLawMum.id, childrenIds: [spouse.id]),
            Union(partner1Id: married.id, partner2Id: spouse.id),
        ]
        tree.homePersonId = married.id

        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        func centre(_ person: Person) throws -> CGFloat {
            try #require(layout.nodes.first { $0.person.id == person.id }).x
        }
        let siblingX = try centre(single)
        let marriedX = try centre(married)
        let spouseX = try centre(spouse)

        // The spouse is on the outside: sibling, then the married child, then the in-law.
        #expect((siblingX < marriedX) == (marriedX < spouseX),
                "the in-law sits between the two siblings")
        #expect(LayoutInvariants.connectorCrossings(tree: tree) == 0)
    }

    /// Each spouse of a twice-married person sits on the side her own children are on.
    ///
    /// James Roosevelt I's first wife bore the elder son and his second the younger. Seated
    /// by marriage date the wives end up on opposite sides from their own children and the
    /// two descents have to cross each other; seated by where the children are, they do not.
    @Test func spousesSitOnTheSideTheirChildrenAreOn() throws {
        let husband = Person(givenNames: "Джеймс", sex: .male)
        let first = Person(givenNames: "Ребекка", sex: .female)
        let second = Person(givenNames: "Сара", sex: .female)
        let elder = Person(givenNames: "Старший", sex: .male)
        let younger = Person(givenNames: "Младший", sex: .male)

        let tree = FamilyTree(name: "Sides")
        tree.people = [husband, first, second, elder, younger]
        let early = Union(partner1Id: husband.id, partner2Id: first.id, childrenIds: [elder.id])
        early.marriageDate = "1853"
        let late = Union(partner1Id: husband.id, partner2Id: second.id, childrenIds: [younger.id])
        late.marriageDate = "1880"
        elder.birthDate = "1854"
        younger.birthDate = "1882"
        tree.unions = [early, late]
        tree.homePersonId = husband.id

        let layout = TreeLayoutEngine(config: config).layout(tree: tree, direction: .topDown)
        func centre(_ person: Person) throws -> CGFloat {
            try #require(layout.nodes.first { $0.person.id == person.id }).x
        }
        // Whichever way round the row ends up, each wife is on the same side of her
        // husband as her own son — so neither descent has to reach across the other.
        let husbandX = try centre(husband)
        #expect(try (centre(first) < husbandX) == (centre(elder) < husbandX))
        #expect(try (centre(second) < husbandX) == (centre(younger) < husbandX))
        #expect(LayoutInvariants.connectorCrossings(tree: tree) == 0)
    }

    /// The corpus passes the "no connector crosses a card" invariant, which is only
    /// meaningful if the detector behind it actually fires. This is the detector's own test:
    /// the crossing cases it must catch, and the touching cases it must not.
    @Test func theCrossingDetectorCatchesCrossings() {
        let card = CGRect(x: 100, y: 100, width: 210, height: 90)

        // A marriage line running straight through a card — the old engine's failure.
        #expect(LayoutInvariants.segmentIntersects(
            LinkSegment(from: CGPoint(x: 0, y: 145), to: CGPoint(x: 500, y: 145)), card
        ))
        // A bus trunk crossing a row.
        #expect(LayoutInvariants.segmentIntersects(
            LinkSegment(from: CGPoint(x: 205, y: 0), to: CGPoint(x: 205, y: 400)), card
        ))
        // Ending inside counts too.
        #expect(LayoutInvariants.segmentIntersects(
            LinkSegment(from: CGPoint(x: 0, y: 145), to: CGPoint(x: 205, y: 145)), card
        ))

        // A drop that stops on the card's top edge is how every child connector ends.
        #expect(!LayoutInvariants.segmentIntersects(
            LinkSegment(from: CGPoint(x: 205, y: 0), to: CGPoint(x: 205, y: 100)), card
        ))
        // A lane passing below the row.
        #expect(!LayoutInvariants.segmentIntersects(
            LinkSegment(from: CGPoint(x: 0, y: 240), to: CGPoint(x: 500, y: 240)), card
        ))
        // A marriage line in the gap beside the card.
        #expect(!LayoutInvariants.segmentIntersects(
            LinkSegment(from: CGPoint(x: 310, y: 145), to: CGPoint(x: 350, y: 145)), card
        ))
    }

    /// In-laws belong on one row. Longest-path layering alone strands a shallow branch at
    /// the top — a wife whose parents have no recorded ancestors would have them drawn
    /// several rows above her husband's parents — so the layering pulls every ancestor
    /// down to sit directly above their children.
    @Test(arguments: LayoutCorpusTests.corpus)
    func bothSetsOfParentsShareARow(name: String) throws {
        let tree = try LayoutCorpusTests.load(name)
        let generations = LayoutInvariants.generations(of: tree)
        let index = FamilyIndex(tree: tree)

        for union in tree.unions {
            let partners = union.partnerIds.filter { index.byId[$0] != nil }
            guard partners.count == 2 else { continue }
            let parentRows = partners.compactMap { partner -> Int? in
                let parents = index.parentEdges(of: partner).map(\.parentID)
                return parents.compactMap { generations[$0] }.max()
            }
            guard parentRows.count == 2 else { continue }
            #expect(parentRows[0] == parentRows[1],
                    "\(name): a couple's two sets of parents sit on rows \(parentRows)")
        }
    }
}
