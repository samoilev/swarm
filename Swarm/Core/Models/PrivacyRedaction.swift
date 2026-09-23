import Foundation

// Sharing a tree means sharing everyone in it, and the people who never consented to
// that are the living ones. These build a redacted *copy* for an export to render;
// nothing here touches the tree the app has open, and the save path never calls it.

public extension Person {
    /// A stand-in for this person carrying no personal data: same identity and same
    /// place in the tree, but no name, dates, places, documents or free text.
    ///
    /// The surname stays. A tree of identical "Living" boxes is unreadable, and a
    /// surname shared with relatives who are already public reveals nothing they don't.
    func redactedForPrivacy(language: AppLanguage = .current) -> Person {
        let copy = Person(sex: sex, isLiving: isLiving)
        // The id is what unions, parent links and the home-person reference point at,
        // and the xref is what FAMC/FAMS in the exported GEDCOM resolve against.
        copy.id = id
        copy.gedcomXref = gedcomXref
        copy.names = [PersonName(
            givenNames: L10n.tr("Живой человек", language: language),
            surname: surname
        )]
        // Events, citations, notes, sources, photo, attachments and links are left at
        // their empty defaults. So are `unknownBranches`/`eventExtras`: an imported
        // branch the app doesn't model can hold anything, including the very fields
        // this method exists to remove.
        copy.createdAt = createdAt
        copy.updatedAt = updatedAt
        return copy
    }
}

public extension Union {
    /// This union with the couple's own data removed, keeping who is in it. Used when
    /// a partner is living — a marriage date and place are their personal data too.
    func redactedForPrivacy() -> Union {
        let copy = Union(partner1Id: partner1Id, partner2Id: partner2Id, childrenIds: childrenIds)
        copy.id = id
        copy.gedcomXref = gedcomXref
        copy.createdAt = createdAt
        // events/citations stay empty: marriage, divorce and separation records all
        // describe living partners. `marriageExtras` and `unknownBranches` go for the
        // same reason Person's do.
        return copy
    }
}

public extension FamilyTree {
    /// A copy of this tree with every living person's personal data removed.
    ///
    /// Structure survives intact — ids, xrefs, unions, parent links and the home person
    /// all still resolve — so the exported tree keeps its shape and a reader can still
    /// see how the public part of the family connects. Deceased people are carried over
    /// by reference: an export only reads them, so copying would buy nothing.
    func redactingLivingPeople(language: AppLanguage = .current) -> FamilyTree {
        let copy = FamilyTree(name: name, subtitle: subtitle)
        copy.id = id
        copy.schemaVersion = schemaVersion
        copy.homePersonId = homePersonId
        copy.rootUnionId = rootUnionId
        copy.createdAt = createdAt
        copy.updatedAt = updatedAt
        copy.sourceVersion = sourceVersion
        copy.foreignSchemaTags = foreignSchemaTags
        copy.layoutVersion = layoutVersion

        copy.people = people.map { $0.isLiving ? $0.redactedForPrivacy(language: language) : $0 }

        let livingIds = Set(people.filter(\.isLiving).map(\.id))
        copy.unions = unions.map { union in
            union.partnerIds.contains(where: livingIds.contains) ? union.redactedForPrivacy() : union
        }
        // A link to a living parent or child keeps its shape; its evidence — a birth
        // certificate cited, an adoption note — describes the living person.
        copy.parentLinks = parentLinks.map { link in
            guard livingIds.contains(link.parentID) || livingIds.contains(link.childID) else { return link }
            var redacted = link
            redacted.citations = []
            redacted.notes = nil
            return redacted
        }
        // A source travels only while someone still in the export cites it. Copying them
        // all shipped the title, URL and notes of a source only a living person cited.
        let cited = Set(copy.allCitations().map(\.sourceID))
        copy.sourceRecords = sourceRecords.filter { cited.contains($0.id) }

        // Everything preserved verbatim from an import is dropped rather than filtered.
        // `gedcomDocument` re-emits foreign records untouched on serialization, the raw
        // record lists are foreign records themselves, and an import report quotes the
        // names it had trouble with. None of them can be redacted line by line.
        copy.gedcomDocument = nil
        copy.headUnknownBranches = []
        copy.unknownRecords = []
        copy.importReport = nil
        copy.acceptedBaselineIssueIDs = acceptedBaselineIssueIDs
        return copy
    }

    /// How many people an export would redact. Drives the export sheet's toggle and
    /// its summary line.
    var livingPeopleCount: Int {
        people.reduce(into: 0) { $0 += $1.isLiving ? 1 : 0 }
    }
}
