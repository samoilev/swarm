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

    /// Levels may only step down one at a time, so a file can nest as deep as it is long,
    /// and the syntax tree is built recursively. A crafted file 10,000 levels deep
    /// overflowed the stack of the background task the import preview parses on.
    @Test func nestingDeeperThanTheGrammarAllowsIsRefusedNotACrash() async throws {
        func nested(_ depth: Int) -> String {
            "0 HEAD\n" + (1 ... depth).map { "\($0) _X" }.joined(separator: "\n") + "\n0 TRLR"
        }
        let deep = nested(10000)
        let refused = await Task.detached { () -> Bool in
            do { _ = try GEDCOMCodec.parse(deep); return false } catch is GEDCOMCodecError { return true } catch { return false }
        }.value
        #expect(refused)

        let deepest = nested(GEDCOMDocument.maximumLevel)
        #expect(throws: Never.self) { _ = try GEDCOMCodec.parse(deepest) }
    }

    /// The Character-based tokenizer the byte-level one replaced, kept as the oracle:
    /// the rewrite was for speed alone, so every line must still read the same.
    private static func referenceTokens(_ raw: String) -> [String?]? {
        let trimmed = String(
            raw.drop(while: { $0 == " " || $0 == "\t" })
                .reversed().drop(while: { $0 == "\r" || $0 == "\n" }).reversed()
        )
        guard let firstSpace = trimmed.firstIndex(of: " "),
              let level = Int(trimmed[..<firstSpace]) else { return nil }
        var rest = String(trimmed[trimmed.index(after: firstSpace)...]).drop(while: { $0 == " " })
        var xref: String?
        if rest.first == "@", let closing = rest.dropFirst().firstIndex(of: "@") {
            xref = String(rest[rest.index(after: rest.startIndex) ..< closing])
            rest = rest[rest.index(after: closing)...].drop(while: { $0 == " " })
        }
        guard !rest.isEmpty else { return nil }
        let tag: String
        let tail: String
        if let space = rest.firstIndex(of: " ") {
            tag = String(rest[..<space])
            tail = String(rest[rest.index(after: space)...])
        } else {
            tag = String(rest)
            tail = ""
        }
        if tail.count >= 2, tail.first == "@", tail.last == "@", !tail.dropFirst().dropLast().contains("@") {
            return [String(level), xref, tag, String(tail.dropFirst().dropLast()), ""]
        }
        var value = tail
        if tail.hasPrefix("@@") {
            value = String(tail.dropFirst())
            if value.count >= 3, value.hasSuffix("@@") { value.removeLast() }
        }
        return [String(level), xref, tag, nil, value]
    }

    @Test func byteTokenizerReadsEveryLineLikeTheCharacterOne() throws {
        let fixtures = try #require(Bundle.module.urls(forResourcesWithExtension: "ged", subdirectory: "Fixtures"))
        var lines = [
            "0 HEAD", "  1 NAME Иван /Петров/  ", "1 NOTE \ttabbed\t", "0 @I1@ INDI", "1 FAMC @F1@",
            "1 NOTE @@not a pointer@@", "1 NOTE @@x", "1 NOTE @@@", "1 NOTE @", "1 NOTE @@", "1 NAME ",
            "1 NAME", "1", "", "x NAME", "0 @@ INDI", "0 @I1@", "0   @I2@   INDI  value", "1 _ÉTÉ été\r",
            "1 NOTE 👩‍👩‍👧 семья", "-1 BAD", "+1 SIGN",
        ]
        for url in fixtures {
            try lines += GEDCOMTextDecoder.decode(Data(contentsOf: url)).components(separatedBy: .newlines)
        }
        #expect(fixtures.count >= 6)
        for raw in lines {
            let node = GEDCOMNode(rawLine: raw)
            let actual: [String?]? = node.map { [String($0.level), $0.xref, $0.tag, $0.pointer, $0.value] }
            #expect(actual == Self.referenceTokens(raw), "\(raw)")
        }
    }
}
