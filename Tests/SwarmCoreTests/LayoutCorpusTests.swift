import CoreGraphics
import Foundation
@testable import SwarmCore
import Testing

/// The layout engine run against the six real example trees rather than a toy family.
///
/// Between them they cover the structures that broke the previous engine: serial
/// remarriage (Roosevelt, Tudors), children by several partners (Henry VIII, Alexander II),
/// large half-sibling sets (Романовы), cousin marriage (Darwin–Wedgwood), very wide sibling
/// sets (Kennedy) and nine generations of depth (Roosevelt).
struct LayoutCorpusTests {

    static let corpus = [
        "corpus-curie",
        "corpus-darwin",
        "corpus-kennedy",
        "corpus-roosevelt",
        "corpus-tudors",
        "corpus-romanov",
    ]

    static func load(_ name: String) throws -> FamilyTree {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "ged",
            subdirectory: "Fixtures"
        ))
        return try GEDCOMCodec.parse(url).tree
    }

    @Test(arguments: corpus, [LayoutDirection.topDown, .bottomUp, .leftRight])
    func layoutHoldsItsInvariants(name: String, direction: LayoutDirection) throws {
        let tree = try Self.load(name)
        let violations = LayoutInvariants.check(tree: tree, direction: direction)
        #expect(violations.isEmpty, "\(name) [\(direction)]: \(violations.map(\.description).joined(separator: "; "))")
    }

    /// Partners of a union belong on the same row. The only exception the engine allows is
    /// a union whose partners cannot share a generation without making the generation graph
    /// cyclic — which none of these six trees contains.
    @Test(arguments: corpus)
    func partnersShareAGeneration(name: String) throws {
        let tree = try Self.load(name)
        let generations = LayoutInvariants.generations(of: tree)
        let index = FamilyIndex(tree: tree)
        for union in tree.unions {
            let rows = union.partnerIds
                .filter { index.byId[$0] != nil }
                .compactMap { generations[$0] }
            guard rows.count == 2 else { continue }
            #expect(rows[0] == rows[1], "\(name): union \(union.gedcomXref ?? "?") spans rows \(rows)")
        }
    }

    /// Children always sit below their parents, never beside or above them.
    @Test(arguments: corpus)
    func childrenSitBelowTheirParents(name: String) throws {
        let tree = try Self.load(name)
        let generations = LayoutInvariants.generations(of: tree)
        let index = FamilyIndex(tree: tree)
        for union in tree.unions {
            let parentRows = union.partnerIds.filter { index.byId[$0] != nil }.compactMap { generations[$0] }
            guard let deepestParent = parentRows.max() else { continue }
            for child in union.childrenIds where index.byId[child] != nil {
                guard let childRow = generations[child] else { continue }
                #expect(childRow > deepestParent,
                        "\(name): child row \(childRow) is not below parent row \(deepestParent)")
            }
        }
    }

    /// Crossings are the routing's quality score, and minimising them is NP-hard, so this
    /// is a ratchet rather than an absolute bound: the numbers are what the current lane
    /// allocation achieves, and they may fall but must never climb. The corpus totalled 23
    /// before runs were merged onto one lane per union and the lane assignment was
    /// hill-climbed against this same count.
    ///
    /// What remains is a child's drop passing under another union's trunk in a band that
    /// has no free lane left. Removing those needs vertical channels reserved through the
    /// band, a much larger change than the lane search buys.
    @Test(arguments: zip(corpus, [0, 0, 0, 0, 1, 0]))
    func connectorCrossingsDoNotRegress(name: String, budget: Int) throws {
        let tree = try Self.load(name)
        let crossings = LayoutInvariants.connectorCrossings(tree: tree)
        #expect(crossings <= budget, "\(name): \(crossings) crossings, budget \(budget)")
    }

    /// The drawing has to stay finite. A runaway relaxation pass would show up here long
    /// before anyone opened the app.
    @Test(arguments: corpus)
    func canvasStaysProportionate(name: String) throws {
        let tree = try Self.load(name)
        let layout = TreeLayoutEngine().layout(tree: tree, direction: .topDown)
        let budget = CGFloat(tree.people.count) * 900
        #expect(layout.totalWidth < budget, "\(name): \(layout.totalWidth)pt wide for \(tree.people.count) people")
        #expect(layout.totalHeight < 6000, "\(name): \(layout.totalHeight)pt tall")
    }
}
