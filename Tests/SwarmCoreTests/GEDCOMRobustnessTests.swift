import Foundation
@testable import SwarmCore
import Testing

/// Malformed files from other programs. Each case used to trap in a keyed dictionary
/// (`Dictionary(uniqueKeysWithValues:)`), killing the app mid-import: a file may be
/// refused, but it must never crash the reader.
struct GEDCOMRobustnessTests {
    private static let uid = "6F1C2B3A-1111-4222-8333-944455566677"

    /// Two records sharing one xref, or two xrefs sharing one UID: every shape that
    /// handed two records the same id.
    @Test(arguments: [
        ("INDI xref", """
        0 HEAD
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        0 @I1@ INDI
        1 NAME Борис /Иванов/
        0 @F1@ FAM
        1 HUSB @I1@
        0 TRLR
        """),
        ("FAM xref", """
        0 HEAD
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        0 @I2@ INDI
        1 NAME Борис /Иванов/
        0 @F1@ FAM
        1 WIFE @I1@
        1 CHIL @I2@
        0 @F1@ FAM
        1 HUSB @I2@
        0 TRLR
        """),
        ("INDI UID", """
        0 HEAD
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        1 UID \(uid)
        0 @I2@ INDI
        1 NAME Борис /Иванов/
        1 UID \(uid)
        0 TRLR
        """),
        ("FAM UID", """
        0 HEAD
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        0 @I2@ INDI
        1 NAME Борис /Иванов/
        0 @F1@ FAM
        1 WIFE @I1@
        1 UID \(uid)
        0 @F2@ FAM
        1 HUSB @I2@
        1 UID \(uid)
        0 TRLR
        """),
    ])
    func repeatedIdentityImportsEveryRecordWithAWarning(_ shape: String, _ gedcom: String) throws {
        let imported = try GEDCOMCodec.parse(gedcom)
        let tree = imported.tree

        #expect(tree.people.count == 2, "\(shape)")
        #expect(Set(tree.people.map(\.id)).count == tree.people.count, "\(shape)")
        #expect(Set(tree.unions.map(\.id)).count == tree.unions.count, "\(shape)")
        #expect(imported.report.warnings.contains { $0.id.hasPrefix("gedcom.reassigned-id.") }, "\(shape)")
        #expect(!TreeValidator.validate(tree).contains { $0.code == "identity.duplicate" }, "\(shape)")
    }

    /// A pointer to a repeated xref resolves to the first record carrying it.
    @Test func pointersToARepeatedXrefResolveToTheFirstRecord() throws {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        0 @I1@ INDI
        1 NAME Борис /Иванов/
        0 @F1@ FAM
        1 HUSB @I1@
        0 TRLR
        """
        let tree = try GEDCOMCodec.parse(gedcom).tree
        let anna = try #require(tree.people.first { $0.givenNames == "Анна" })
        #expect(tree.unions.first?.partner1Id == anna.id)
    }

    /// Saving such a file keeps both people exactly once. Patching the imported
    /// document emitted the first record for both copies of its xref, so every
    /// save-and-reload grew the tree by one phantom person.
    @Test func repeatedXrefSurvivesSaveAndReloadWithoutGrowing() throws {
        let gedcom = """
        0 HEAD
        1 GEDC
        2 VERS 5.5.1
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        0 @I1@ INDI
        1 NAME Борис /Иванов/
        0 TRLR
        """
        let first = try GEDCOMCodec.parse(gedcom)
        let saved = try GEDCOMCodec.serialize(tree: first.tree, document: first.document).gedcom
        let second = try GEDCOMCodec.parse(saved)

        #expect(second.tree.people.map(\.givenNames).sorted() == ["Анна", "Борис"])
        #expect(Set(second.tree.people.map(\.id)) == Set(first.tree.people.map(\.id)))
        #expect(!second.report.warnings.contains { $0.id.hasPrefix("gedcom.reassigned-id.") })
    }
}
