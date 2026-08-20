import Foundation

/// Serializes a FamilyTree to GEDCOM 5.5.1 format.
/// This is the primary persistence format — each tree is stored as a .ged file.
public struct GEDCOMSerializer {

    /// A person portrait the GEDCOM references, paired with the filename used in its
    /// `OBJE`/`FILE` line. The caller persists the bytes — serialization stays pure.
    public struct Photo: Equatable {
        public let personID: UUID
        public let filename: String
        public let data: Data
    }

    /// Result of serialization: the GEDCOM text plus the photos it references.
    public struct Result: Equatable {
        public let gedcom: String
        public let photos: [Photo]
    }

    /// Serialize a tree to GEDCOM. This is a pure, side-effect-free transform:
    /// photo bytes are returned in `Result.photos` (referenced by relative filename),
    /// and writing them to a media folder is the caller's responsibility (see
    /// `TreeStore.writePhotos`). Kept pure so it is trivially testable.
    public static func serialize(tree: FamilyTree) -> Result {
        let idx = FamilyIndex(tree: tree)

        // Xref assignment: reuse the xref an imported record already had (so any
        // cross-references living inside preserved unknown structures still resolve),
        // and hand out fresh, collision-free ids to app-created records.
        let indiXref = assignXrefs(ids: tree.people.map(\.id), existing: tree.people.map(\.gedcomXref), prefix: "I")
        let famXref = assignXrefs(ids: tree.unions.map(\.id), existing: tree.unions.map(\.gedcomXref), prefix: "F")
        let sourceXref = assignXrefs(
            ids: tree.sourceRecords.map(\.id),
            existing: tree.sourceRecords.map(\.gedcomXref),
            prefix: "S"
        )
        let attachmentByID = Dictionary(uniqueKeysWithValues: tree.people.flatMap(\.attachments).map { ($0.id.uuidString, $0) })

        var lines: [String] = []
        var photos: [Photo] = []

        // HEAD
        lines.append("0 HEAD")
        if tree.headUnknownBranches.isEmpty {
            lines.append("1 SOUR Swarm")
            lines.append("2 NAME \(L10n.tr("Swarm"))")
            lines.append("2 VERS 2.0")
            lines.append("1 GEDC")
            lines.append("2 VERS 5.5.1")
            lines.append("2 FORM LINEAGE-LINKED")
            lines.append("1 CHAR UTF-8")
            let df = DateFormatter()
            df.dateFormat = "d MMM yyyy"
            df.locale = Locale(identifier: "en_US_POSIX")
            lines.append("1 DATE \(df.string(from: Date()).uppercased())")
        } else {
            // Imported HEAD provenance and metadata stay byte-for-byte intact. Add
            // required declarations only when the source omitted them.
            for branch in tree.headUnknownBranches { lines.append(contentsOf: branch) }
            let tags = Set(tree.headUnknownBranches.compactMap { branch -> String? in
                guard let first = branch.first else { return nil }
                return first.split(separator: " ").dropFirst().first.map(String.init)
            })
            if !tags.contains("GEDC") {
                lines.append("1 GEDC")
                lines.append("2 VERS 5.5.1")
                lines.append("2 FORM LINEAGE-LINKED")
            }
            if !tags.contains("CHAR") { lines.append("1 CHAR UTF-8") }
        }
        // Custom metadata
        lines.append("1 _TREEID \(tree.id.uuidString)")
        lines.append("1 _FTSVER 2")
        lines.append("1 _NAME \(tree.name)")
        if let sub = tree.subtitle, !sub.isEmpty {
            lines.append("1 _SUBTITLE \(sub)")
        }
        if let homeId = tree.homePersonId, let xref = indiXref[homeId] {
            lines.append("1 _HOME @\(xref)@")
        }
        if let rootId = tree.rootUnionId, let xref = famXref[rootId] {
            lines.append("1 _ROOT @\(xref)@")
        }

        // INDI records
        for p in tree.people {
            guard let xref = indiXref[p.id] else { continue }
            lines.append("0 @\(xref)@ INDI")
            lines.append("1 _FTSID \(p.id.uuidString)")

            // Structured names. The first/primary name remains compatible with the
            // historical _PATR/_MARNM extensions used by this app.
            let names = p.names.isEmpty ? [PersonName(
                givenNames: p.givenNames,
                patronymic: p.patronymic,
                surname: p.surname,
                maidenName: p.maidenName
            )] : p.names
            for (index, name) in names.enumerated() {
                appendName(name, primary: index == 0 || name.isPrimary, sourceXref: sourceXref, to: &lines)
            }

            if p.sex != .unknown { lines.append("1 SEX \(p.sex.rawValue)") }

            appendPersonEvent(
                p.event(ofKind: .birth),
                kind: .birth,
                fallbackDate: p.birthDate,
                fallbackPlace: p.birthPlace,
                fallbackLat: p.birthLat,
                fallbackLon: p.birthLon,
                extras: p.eventExtras["BIRT"] ?? [],
                placeExtras: p.eventExtras[GEDCOMParser.placeExtrasKey("BIRT")] ?? [],
                force: false,
                sourceXref: sourceXref,
                to: &lines
            )
            appendPersonEvent(
                p.isLiving ? nil : p.event(ofKind: .death),
                kind: .death,
                fallbackDate: p.isLiving ? nil : p.deathDate,
                fallbackPlace: p.isLiving ? nil : p.deathPlace,
                fallbackLat: p.isLiving ? nil : p.deathLat,
                fallbackLon: p.isLiving ? nil : p.deathLon,
                extras: p.isLiving ? [] : (p.eventExtras["DEAT"] ?? []),
                placeExtras: p.isLiving ? [] : (p.eventExtras[GEDCOMParser.placeExtrasKey("DEAT")] ?? []),
                force: !p.isLiving,
                sourceXref: sourceXref,
                to: &lines
            )
            appendPersonEvent(
                p.isLiving ? nil : p.event(ofKind: .burial),
                kind: .burial,
                fallbackDate: nil,
                fallbackPlace: p.isLiving ? nil : p.burialPlace,
                fallbackLat: p.isLiving ? nil : p.burialLat,
                fallbackLon: p.isLiving ? nil : p.burialLon,
                extras: p.isLiving ? [] : (p.eventExtras["BURI"] ?? []),
                placeExtras: p.isLiving ? [] : (p.eventExtras[GEDCOMParser.placeExtrasKey("BURI")] ?? []),
                force: false,
                sourceXref: sourceXref,
                to: &lines
            )

            // Repeatable occupation/education and other structured person events.
            let scalarKinds: Set<GenealogyEvent.Kind> = [.occupation, .education, .residence, .immigration, .military, .custom]
            for event in p.events where scalarKinds.contains(event.kind) {
                appendGeneralEvent(event, sourceXref: sourceXref, to: &lines)
            }
            if !p.events.contains(where: { $0.kind == .occupation }), let o = p.occupation, !o.isEmpty {
                appendValue(1, "OCCU", value: o, to: &lines)
            }
            if !p.events.contains(where: { $0.kind == .education }), let e = p.education, !e.isEmpty {
                appendValue(1, "EDUC", value: e, to: &lines)
            }

            // Notes (multi-line via CONT; long lines split further via CONC)
            if let n = p.notes, !n.isEmpty {
                let noteLines = n.components(separatedBy: "\n")
                appendValue(1, "NOTE", value: noteLines[0], to: &lines)
                for noteLine in noteLines.dropFirst() {
                    appendValue(2, "CONT", value: noteLine, to: &lines)
                }
            }

            appendCitations(p.citations, level: 1, sourceXref: sourceXref, to: &lines)
            let linkedTitles = Set(p.citations.compactMap { citation in
                tree.sourceRecords.first(where: { $0.id == citation.sourceID })?.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            })
            for source in p.sources where !linkedTitles.contains(source.trimmingCharacters(in: .whitespacesAndNewlines)) {
                appendValue(1, "SOUR", value: source, to: &lines)
            }

            // Photo — referenced by filename here. The bytes are returned in
            // `Result.photos` (for the caller to persist) only when they changed this
            // session, so an unchanged portrait is never force-loaded from
            // disk solely to rewrite an identical file.
            if p.hasPhoto {
                let filename = p.photoFilename ?? "\(xref).jpg"
                lines.append("1 OBJE")
                lines.append("2 FILE \(filename)")
                lines.append("2 FORM \(filename.lowercased().hasSuffix(".png") ? "PNG" : "JPEG")")
                if p.photoIsDirty, let bytes = p.photoData {
                    photos.append(Photo(personID: p.id, filename: filename, data: bytes))
                }
            }

            // Attachments — referenced by relative path; the bytes live on disk in
            // the tree's Attachments/ folder (written when the file is attached).
            for att in p.attachments {
                lines.append("1 _ATTC")
                lines.append("2 FILE Attachments/\(att.storedName)")
                lines.append("2 TITL \(att.originalName)")
                if let notes = att.notes, !notes.isEmpty { appendMultiline(level: 2, tag: "NOTE", value: notes, to: &lines) }
                appendCitations(att.citations, level: 2, sourceXref: sourceXref, to: &lines)
            }

            // Web links — WWW is the standard tag; the label rides along as a sub-TITL.
            for link in p.links where !link.url.isEmpty {
                appendValue(1, "WWW", value: link.url, to: &lines)
                if !link.title.isEmpty { appendValue(2, "TITL", value: link.title, to: &lines) }
            }

            // Family links
            for union in idx.unionsOf[p.id] ?? [] {
                if let fx = famXref[union.id] { lines.append("1 FAMS @\(fx)@") }
            }
            for pu in idx.childOfAll[p.id] ?? [] {
                guard let fx = famXref[pu.id] else { continue }
                lines.append("1 FAMC @\(fx)@")
                let links = tree.parentLinks.filter { $0.childID == p.id && $0.unionID == pu.id }
                let kinds = Set(links.map(\.kind))
                let kind = kinds.count == 1 ? kinds.first! : (kinds.isEmpty ? .biological : .uncertain)
                switch kind {
                case .biological, .adoptive, .foster:
                    lines.append("2 PEDI \(kind.gedcomValue)")
                case .step, .uncertain:
                    lines.append("2 _PEDI \(kind.gedcomValue)")
                }
                for link in links {
                    guard let parentXref = indiXref[link.parentID] else { continue }
                    lines.append("2 _PLINK @\(parentXref)@")
                    lines.append("3 _FTSID \(link.id.uuidString)")
                    lines.append("3 PEDI \(link.kind.gedcomValue)")
                    if let notes = link.notes, !notes.isEmpty {
                        appendMultiline(level: 3, tag: "NOTE", value: notes, to: &lines)
                    }
                    appendCitations(link.citations, level: 3, sourceXref: sourceXref, to: &lines)
                }
            }

            // Preserved unmodeled level-1 branches from an imported file, verbatim.
            for branch in p.unknownBranches { lines.append(contentsOf: branch) }
        }

        // FAM records
        for u in tree.unions {
            guard let fx = famXref[u.id] else { continue }
            lines.append("0 @\(fx)@ FAM")
            lines.append("1 _FTSID \(u.id.uuidString)")

            // Determine HUSB/WIFE by sex
            var husb: UUID? = nil, wife: UUID? = nil
            for pid in u.partnerIds {
                if let p = idx.byId[pid] {
                    if p.sex == .male { husb = pid }
                    else if p.sex == .female { wife = pid }
                }
            }
            // Fallback if both same sex or unknown
            if husb == nil && wife == nil {
                husb = u.partner1Id
                wife = u.partner2Id
            } else if husb == nil {
                husb = u.partnerIds.first(where: { $0 != wife })
            } else if wife == nil {
                wife = u.partnerIds.first(where: { $0 != husb })
            }

            if let h = husb, let x = indiXref[h] { lines.append("1 HUSB @\(x)@") }
            if let w = wife, let x = indiXref[w] { lines.append("1 WIFE @\(x)@") }

            // Children
            for cid in u.childrenIds {
                if let x = indiXref[cid] { lines.append("1 CHIL @\(x)@") }
            }

            if let marriage = u.event(ofKind: .marriage) {
                appendUnionEvent(marriage, extras: u.marriageExtras, sourceXref: sourceXref, attachments: attachmentByID, to: &lines)
            } else if u.marriageDate != nil || u.marriagePlace != nil || !u.marriageExtras.isEmpty {
                appendUnionEvent(GenealogyEvent(
                    kind: .marriage,
                    date: u.marriageDate.map { GenealogyDate(userInput: $0) },
                    place: u.marriagePlace.map { PlaceReference(displayName: $0, isCustom: true) }
                ), extras: u.marriageExtras, sourceXref: sourceXref, attachments: attachmentByID, to: &lines)
            }
            if let divorce = u.event(ofKind: .divorce) {
                appendUnionEvent(divorce, extras: [], sourceXref: sourceXref, attachments: attachmentByID, to: &lines)
            } else if u.status == "divorced" {
                lines.append("1 DIV")
            }
            if let separation = u.event(ofKind: .separation) {
                appendUnionEvent(separation, extras: [], sourceXref: sourceXref, attachments: attachmentByID, to: &lines)
            }
            if let partnership = u.event(ofKind: .partnership) {
                appendUnionEvent(partnership, extras: [], sourceXref: sourceXref, attachments: attachmentByID, to: &lines)
            } else if let status = u.status, !status.isEmpty, status != "divorced", status != "separated" {
                lines.append("1 _STAT \(status)")
            }
            appendCitations(u.citations, level: 1, sourceXref: sourceXref, to: &lines)

            // Preserved unmodeled level-1 branches from an imported file, verbatim.
            for branch in u.unknownBranches { lines.append(contentsOf: branch) }
        }

        // Structured top-level sources.
        for source in tree.sourceRecords {
            guard let xref = sourceXref[source.id] else { continue }
            appendSourceRecord(source, xref: xref, to: &lines)
        }

        // Whole top-level records the app doesn't model (SUBM, REPO, NOTE, …), re-emitted
        // verbatim so a foreign file survives import → re-export.
        let modeledSourceXrefs = Set(tree.sourceRecords.compactMap(\.gedcomXref))
        for record in tree.unknownRecords {
            let first = record.first ?? ""
            let isModeledSource = modeledSourceXrefs.contains { first.contains("@\($0)@ SOUR") }
            if !isModeledSource { lines.append(contentsOf: record) }
        }

        lines.append("0 TRLR")
        return Result(gedcom: lines.joined(separator: "\n"), photos: photos)
    }

    // MARK: - Structured records

    private static func appendName(
        _ name: PersonName,
        primary: Bool,
        sourceXref: [UUID: String],
        to lines: inout [String]
    ) {
        let given = sanitizeNamePart(name.givenNames)
        let surname = sanitizeNamePart(name.maidenName ?? name.surname)
        lines.append("1 NAME \(given) /\(surname)/")
        if !primary || name.kind != .birth { lines.append("2 TYPE \(gedcomNameType(name.kind))") }
        if !name.givenNames.isEmpty { appendValue(2, "GIVN", value: name.givenNames, to: &lines) }
        if !name.surname.isEmpty { appendValue(2, "SURN", value: name.surname, to: &lines) }
        if let prefix = name.prefix, !prefix.isEmpty { appendValue(2, "NPFX", value: prefix, to: &lines) }
        if let suffix = name.suffix, !suffix.isEmpty { appendValue(2, "NSFX", value: suffix, to: &lines) }
        if let nickname = name.nickname, !nickname.isEmpty { appendValue(2, "NICK", value: nickname, to: &lines) }
        if let patronymic = name.patronymic, !patronymic.isEmpty {
            appendValue(2, "_PATR", value: patronymic, to: &lines)
        }
        if primary, let maiden = name.maidenName, !maiden.isEmpty, maiden != name.surname {
            lines.append("2 _MARNM \(given) /\(sanitizeNamePart(name.surname))/")
        }
        appendCitations(name.citations, level: 2, sourceXref: sourceXref, to: &lines)
        for branch in name.rawGEDCOMBranches { lines.append(contentsOf: branch) }
    }

    private static func gedcomNameType(_ kind: PersonName.Kind) -> String {
        switch kind {
        case .birth: "birth"
        case .married: "married"
        case .alsoKnownAs: "aka"
        case .religious: "religious"
        case .immigration: "immigration"
        case .other: "other"
        }
    }

    private static func appendPersonEvent(
        _ event: GenealogyEvent?,
        kind: GenealogyEvent.Kind,
        fallbackDate: String?,
        fallbackPlace: String?,
        fallbackLat: Double?,
        fallbackLon: Double?,
        extras: [String],
        placeExtras: [String],
        force: Bool,
        sourceXref: [UUID: String],
        to lines: inout [String]
    ) {
        let date = event?.date
        let place = event?.place
        let eventExtras = filteredLegacyExtras(extras, replacingNotes: event?.notes != nil, replacingSources: !(event?.citations.isEmpty ?? true))
        let hasContent = force || date != nil || fallbackDate != nil || place != nil ||
            fallbackPlace?.isEmpty == false || fallbackLat != nil || fallbackLon != nil ||
            event?.notes?.isEmpty == false || !(event?.citations.isEmpty ?? true) || !eventExtras.isEmpty
        guard hasContent else { return }

        lines.append("1 \(kind.gedcomTag)")
        if let date { lines.append("2 DATE \(date.canonicalGEDCOMValue)") }
        else if let fallbackDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(fallbackDate))") }
        appendPlace(
            place?.displayName ?? fallbackPlace,
            lat: place?.latitude ?? fallbackLat,
            lon: place?.longitude ?? fallbackLon,
            datasetID: place?.datasetID,
            extras: placeExtras,
            to: &lines
        )
        if let type = event?.typeName, !type.isEmpty { appendValue(2, "TYPE", value: type, to: &lines) }
        if let note = event?.notes, !note.isEmpty { appendMultiline(level: 2, tag: "NOTE", value: note, to: &lines) }
        appendCitations(event?.citations ?? [], level: 2, sourceXref: sourceXref, to: &lines)
        lines.append(contentsOf: eventExtras)
        for branch in event?.rawGEDCOMBranches ?? [] { lines.append(contentsOf: branch) }
    }

    private static func appendGeneralEvent(
        _ event: GenealogyEvent,
        sourceXref: [UUID: String],
        to lines: inout [String]
    ) {
        let hasSubstructure = event.date != nil || event.place != nil || event.notes?.isEmpty == false ||
            !event.citations.isEmpty || !event.rawGEDCOMBranches.isEmpty || event.typeName != nil
        if !hasSubstructure, let value = event.value, !value.isEmpty {
            appendValue(1, event.kind.gedcomTag, value: value, to: &lines)
            return
        }
        if let value = event.value, !value.isEmpty { appendValue(1, event.kind.gedcomTag, value: value, to: &lines) }
        else { lines.append("1 \(event.kind.gedcomTag)") }
        if event.kind == .custom, let type = event.typeName, !type.isEmpty { appendValue(2, "TYPE", value: type, to: &lines) }
        if let date = event.date { lines.append("2 DATE \(date.canonicalGEDCOMValue)") }
        if let place = event.place {
            appendPlace(place.displayName, lat: place.latitude, lon: place.longitude, datasetID: place.datasetID, to: &lines)
        }
        if let note = event.notes, !note.isEmpty { appendMultiline(level: 2, tag: "NOTE", value: note, to: &lines) }
        appendCitations(event.citations, level: 2, sourceXref: sourceXref, to: &lines)
        for branch in event.rawGEDCOMBranches { lines.append(contentsOf: branch) }
    }

    private static func appendUnionEvent(
        _ event: GenealogyEvent,
        extras: [String],
        sourceXref: [UUID: String],
        attachments: [String: Attachment],
        to lines: inout [String]
    ) {
        lines.append("1 \(event.kind.gedcomTag)")
        if let date = event.date { lines.append("2 DATE \(date.canonicalGEDCOMValue)") }
        if let place = event.place {
            appendPlace(place.displayName, lat: place.latitude, lon: place.longitude, datasetID: place.datasetID, to: &lines)
        }
        if let note = event.notes, !note.isEmpty { appendMultiline(level: 2, tag: "NOTE", value: note, to: &lines) }
        appendCitations(event.citations, level: 2, sourceXref: sourceXref, to: &lines)
        for mediaID in event.mediaIDs {
            guard let attachment = attachments[mediaID] else { continue }
            lines.append("2 _ATTC")
            appendValue(3, "FILE", value: "Attachments/\(attachment.storedName)", to: &lines)
            appendValue(3, "TITL", value: attachment.originalName, to: &lines)
        }
        lines.append(contentsOf: filteredLegacyExtras(extras, replacingNotes: event.notes != nil, replacingSources: !event.citations.isEmpty))
        for branch in event.rawGEDCOMBranches { lines.append(contentsOf: branch) }
    }

    private static func appendCitations(
        _ citations: [Citation],
        level: Int,
        sourceXref: [UUID: String],
        to lines: inout [String]
    ) {
        for citation in citations {
            guard let xref = sourceXref[citation.sourceID] else {
                for branch in citation.rawGEDCOMBranches { lines.append(contentsOf: branch) }
                continue
            }
            lines.append("\(level) SOUR @\(xref)@")
            if let page = citation.page, !page.isEmpty { appendValue(level + 1, "PAGE", value: page, to: &lines) }
            if let detail = citation.detail, !detail.isEmpty { appendValue(level + 1, "EVEN", value: detail, to: &lines) }
            if let text = citation.transcription, !text.isEmpty {
                lines.append("\(level + 1) DATA")
                appendMultiline(level: level + 2, tag: "TEXT", value: text, to: &lines)
            }
            if let confidence = citation.confidence, !confidence.isEmpty {
                appendValue(level + 1, "QUAY", value: confidence, to: &lines)
            }
            if let notes = citation.notes, !notes.isEmpty {
                appendMultiline(level: level + 1, tag: "NOTE", value: notes, to: &lines)
            }
            lines.append(contentsOf: preservedCitationDetail(citation, level: level))
        }
    }

    /// Sub-lines of an imported SOUR that `Citation` doesn't carry: foreign tags such as
    /// another program's place id, and any NOTE past the one the model holds. The modeled
    /// fields above replace the whole imported branch, so without this they disappear the
    /// first time the record is saved.
    private static func preservedCitationDetail(_ citation: Citation, level: Int) -> [String] {
        guard let branch = citation.rawGEDCOMBranches.first,
              let head = branch.first,
              let headLevel = gedcomLevel(of: head) else { return [] }
        let shift = level - headLevel
        // The model keeps a single NOTE; the branch may hold several. Consume the one
        // that matches, so the rest are re-emitted rather than silently dropped.
        var noteToConsume = citation.notes?.components(separatedBy: "\n").first
        var openBranch: (root: Int, keep: Bool)?
        var result: [String] = []
        for raw in branch.dropFirst() {
            guard let lineLevel = gedcomLevel(of: raw) else { continue }
            if let open = openBranch, lineLevel > open.root {
                if open.keep { result.append(shiftingLevel(raw, by: shift)) }
                continue
            }
            let tag = gedcomTag(of: raw) ?? ""
            let keep: Bool
            switch tag {
            case "PAGE", "EVEN", "DATA", "TEXT", "QUAY":
                keep = false
            case "NOTE":
                let value = gedcomValue(of: raw)
                if let pending = noteToConsume, pending == value {
                    noteToConsume = nil
                    keep = false
                } else {
                    keep = true
                }
            default:
                keep = true
            }
            openBranch = (lineLevel, keep)
            if keep { result.append(shiftingLevel(raw, by: shift)) }
        }
        return result
    }

    private static func gedcomLevel(of raw: String) -> Int? {
        Int(raw.prefix(while: \.isNumber))
    }

    private static func gedcomTag(of raw: String) -> String? {
        let parts = raw.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts[1].hasPrefix("@") ? (parts.count > 2 ? parts[2] : nil) : parts[1]
    }

    private static func gedcomValue(of raw: String) -> String {
        let parts = raw.split(separator: " ", maxSplits: 2).map(String.init)
        return parts.count > 2 ? parts[2] : ""
    }

    private static func shiftingLevel(_ raw: String, by shift: Int) -> String {
        guard shift != 0, let level = gedcomLevel(of: raw) else { return raw }
        let rest = raw.drop(while: \.isNumber)
        return "\(level + shift)\(rest)"
    }

    private static func appendSourceRecord(_ source: SourceRecord, xref: String, to lines: inout [String]) {
        lines.append("0 @\(xref)@ SOUR")
        lines.append("1 _FTSID \(source.id.uuidString)")
        appendValue(1, "TITL", value: source.title, to: &lines)
        if let author = source.author, !author.isEmpty { appendValue(1, "AUTH", value: author, to: &lines) }
        if let publication = source.publication, !publication.isEmpty { appendValue(1, "PUBL", value: publication, to: &lines) }
        if let repository = source.repository, !repository.isEmpty {
            if repository.first == "@", repository.last == "@" { lines.append("1 REPO \(repository)") }
            else { appendValue(1, "REPO", value: repository, to: &lines) }
        }
        if let callNumber = source.callNumber, !callNumber.isEmpty { appendValue(1, "CALN", value: callNumber, to: &lines) }
        if let notes = source.notes, !notes.isEmpty { appendMultiline(level: 1, tag: "NOTE", value: notes, to: &lines) }
        for branch in source.rawGEDCOMBranches { lines.append(contentsOf: branch) }
    }

    private static func appendMultiline(level: Int, tag: String, value: String, to lines: inout [String]) {
        let parts = value.components(separatedBy: "\n")
        appendValue(level, tag, value: parts.first ?? "", to: &lines)
        for line in parts.dropFirst() { appendValue(level + 1, "CONT", value: line, to: &lines) }
    }

    /// Remove preserved legacy NOTE/SOUR branches only when their structured
    /// equivalents are being emitted. All other imported substructure is untouched.
    private static func filteredLegacyExtras(
        _ extras: [String],
        replacingNotes: Bool,
        replacingSources: Bool
    ) -> [String] {
        var result: [String] = []
        var skippedRootLevel: Int?
        for raw in extras {
            let tokens = raw.split(separator: " ", maxSplits: 2).map(String.init)
            guard tokens.count >= 2, let level = Int(tokens[0]) else {
                if skippedRootLevel == nil { result.append(raw) }
                continue
            }
            if let root = skippedRootLevel {
                if level > root { continue }
                skippedRootLevel = nil
            }
            let tag = tokens[1]
            if (replacingNotes && tag == "NOTE") || (replacingSources && tag == "SOUR") {
                skippedRootLevel = level
                continue
            }
            result.append(raw)
        }
        return result
    }

    // MARK: - Xref assignment

    /// Assign a GEDCOM xref to each id: reuse the `existing` one where present (kept
    /// stable so preserved cross-references resolve), then fill the rest with fresh
    /// `<prefix><n>` ids that don't collide with any reused one.
    private static func assignXrefs(ids: [UUID], existing: [String?], prefix: String) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var used = Set<String>()
        for (id, x) in zip(ids, existing) {
            if let x, !x.isEmpty, !used.contains(x) {
                result[id] = x
                used.insert(x)
            }
        }
        var counter = 1
        for id in ids where result[id] == nil {
            while used.contains("\(prefix)\(counter)") { counter += 1 }
            let x = "\(prefix)\(counter)"
            result[id] = x
            used.insert(x)
        }
        return result
    }

    // MARK: - Line emission (GEDCOM 5.5.1 length limits)

    /// Strip slashes from a NAME part so they can't corrupt the `/surname/` structure.
    private static func sanitizeNamePart(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Append a `level tag value` line, splitting a long value across `CONC`
    /// continuation lines so no physical line exceeds the GEDCOM 5.5.1 limit
    /// (255 bytes incl. the level/tag prefix). Chunking is by UTF-8 byte budget so
    /// multi-byte Cyrillic text stays within bounds.
    private static func appendValue(_ level: Int, _ tag: String, value: String, to lines: inout [String]) {
        guard !value.isEmpty else { lines.append("\(level) \(tag)"); return }
        // Break only between two non-space characters. GEDCOM readers (this one
        // included) trim leading/trailing whitespace from each CONC line, so a break
        // adjacent to a space would silently drop that space on re-import. Splitting
        // mid-word keeps concatenation exact. `soft` is the target; `hard` is the true
        // ceiling we never cross (well under the 255-byte line limit).
        let soft = 200, hard = 248
        var chunks: [String] = []
        var cur = ""
        var curBytes = 0
        for ch in value {
            let b = String(ch).utf8.count
            let atBoundarySpace = cur.last == " " || ch == " "
            let mustBreak = curBytes + b > hard
            let wantBreak = curBytes + b > soft
            if !cur.isEmpty, mustBreak || (wantBreak && !atBoundarySpace) {
                chunks.append(cur); cur = ""; curBytes = 0
            }
            cur.append(ch); curBytes += b
        }
        if !cur.isEmpty { chunks.append(cur) }
        lines.append("\(level) \(tag) \(chunks[0])")
        for chunk in chunks.dropFirst() {
            lines.append("\(level + 1) CONC \(chunk)")
        }
    }

    // MARK: - Coordinate / place emission

    /// Emit a `2 PLAC` line and, when coordinates are present, the standard
    /// `3 MAP / 4 LATI / 4 LONG` triple so other genealogy software reads them.
    /// If coordinates exist but there is no place to host a MAP, fall back to the
    /// private `2 _COORD lat lon` so the app's own data still round-trips.
    private static func appendPlace(
        _ place: String?,
        lat: Double?,
        lon: Double?,
        datasetID: String? = nil,
        extras: [String] = [],
        to lines: inout [String]
    ) {
        if let place, !place.isEmpty {
            lines.append("2 PLAC \(place)")
            if let datasetID, !datasetID.isEmpty { lines.append("3 _PLACID \(datasetID)") }
            // Foreign detail this app doesn't model (a place id from another program,
            // a note about the coordinates) goes back inside the place it came from.
            lines.append(contentsOf: extras)
            if let lat, let lon {
                lines.append("3 MAP")
                lines.append("4 LATI \(gedLat(lat))")
                lines.append("4 LONG \(gedLong(lon))")
            }
        } else if let lat, let lon {
            lines.append("2 _COORD \(lat) \(lon)")
        }
    }

    /// GEDCOM latitude: hemisphere-prefixed magnitude, e.g. 55.75 → "N55.750000".
    private static func gedLat(_ v: Double) -> String {
        String(format: "%@%.6f", v < 0 ? "S" : "N", abs(v))
    }

    /// GEDCOM longitude: hemisphere-prefixed magnitude, e.g. 37.61 → "E37.610000".
    private static func gedLong(_ v: Double) -> String {
        String(format: "%@%.6f", v < 0 ? "W" : "E", abs(v))
    }
}
