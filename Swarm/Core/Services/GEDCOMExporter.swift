import Foundation

/// Serializes a FamilyTree to GEDCOM — 5.5.1 or 7.0.
/// This is the primary persistence format — each tree is stored as a .ged file.
public struct GEDCOMSerializer {

    /// What to emit. The default is 5.5.1 because that is what every tree already on
    /// a user's disk is written in; a plain save must not rewrite a file into another
    /// specification behind their back. Export is where the version is chosen.
    public struct Options: Equatable {
        public var version: GEDCOMVersion
        public init(version: GEDCOMVersion = .v551) {
            self.version = version
        }
    }

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
    public static func serialize(tree: FamilyTree, options: Options = Options()) -> Result {
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
        let attachmentByID = Dictionary(
            tree.people.flatMap(\.attachments).map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Grouped once: filtering every link per person per family made each save
        // quadratic in the size of the tree. Grouping keeps each group in link order.
        struct LinkKey: Hashable { let child: UUID; let union: UUID? }
        let linksByChildAndUnion = Dictionary(grouping: tree.parentLinks) { LinkKey(child: $0.childID, union: $0.unionID) }

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
        // Outside the HEAD if/else above on purpose: an imported HEAD is re-emitted
        // verbatim, so a stamp written up there would freeze at the first save.
        lines.append("1 _CREATED \(GEDCOMParser.timestampFormatter.string(from: tree.createdAt))")
        lines.append("1 _UPDATED \(GEDCOMParser.timestampFormatter.string(from: tree.updatedAt))")
        lines.append("1 _NAME \(singleLineValue(tree.name))")
        if let sub = tree.subtitle, !sub.isEmpty {
            lines.append("1 _SUBTITLE \(singleLineValue(sub))")
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
                appendValue(1, "NOTE", value: n, to: &lines)
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
                lines.append("2 TITL \(singleLineValue(att.originalName))")
                if let notes = att.notes, !notes.isEmpty { appendValue(2, "NOTE", value: notes, to: &lines) }
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
                let links = linksByChildAndUnion[LinkKey(child: p.id, union: pu.id)] ?? []
                let kinds = Set(links.map(\.kind))
                let kind = kinds.count == 1 ? kinds.first! : (kinds.isEmpty ? .biological : .uncertain)
                switch kind {
                case .biological, .adoptive, .foster:
                    lines.append("2 PEDI \(kind.gedcomValue)")
                case .step, .uncertain, .unspecified:
                    lines.append("2 _PEDI \(kind.gedcomValue)")
                }
                for link in links {
                    guard let parentXref = indiXref[link.parentID] else { continue }
                    lines.append("2 _PLINK @\(parentXref)@")
                    lines.append("3 _FTSID \(link.id.uuidString)")
                    lines.append("3 PEDI \(link.kind.gedcomValue)")
                    if link.isUncertain == true { lines.append("3 _UNCERTAIN Y") }
                    if let notes = link.notes, !notes.isEmpty {
                        appendValue(3, "NOTE", value: notes, to: &lines)
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
        let emitted = options.version == .v70 ? convertedToV7(lines, tree: tree) : lines
        return Result(gedcom: emitted.joined(separator: "\n"), photos: photos)
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
        if let note = event?.notes, !note.isEmpty { appendValue(2, "NOTE", value: note, to: &lines) }
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
        if let note = event.notes, !note.isEmpty { appendValue(2, "NOTE", value: note, to: &lines) }
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
        if let note = event.notes, !note.isEmpty { appendValue(2, "NOTE", value: note, to: &lines) }
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
                appendValue(level + 2, "TEXT", value: text, to: &lines)
            }
            if let notes = citation.notes, !notes.isEmpty {
                appendValue(level + 1, "NOTE", value: notes, to: &lines)
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
            case "PAGE", "EVEN", "DATA", "TEXT":
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
        if let publication = source.publication, !publication.isEmpty { appendValue(1, "PUBL", value: publication, to: &lines) }
        if let repository = source.repository, !repository.isEmpty {
            appendValue(1, "REPO", value: repository, to: &lines)
        }
        if let callNumber = source.callNumber, !callNumber.isEmpty { appendValue(1, "CALN", value: callNumber, to: &lines) }
        if let url = source.url, !url.isEmpty { appendValue(1, "_URL", value: url, to: &lines) }
        if let notes = source.notes, !notes.isEmpty { appendValue(1, "NOTE", value: notes, to: &lines) }
        for branch in source.rawGEDCOMBranches { lines.append(contentsOf: branch) }
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

    // MARK: - GEDCOM 7.0 emission

    /// Swarm extension tags that 7.0 has a real structure for. Everything else keeps
    /// its underscore and earns a `SCHMA` declaration instead — the two are exclusive,
    /// and both are driven from here so they cannot drift apart.
    private static let v7TagEquivalents: [String: String] = [
        "_URL": "WWW",
        "_FTSID": "UID",
    ]

    /// 7.0 requires every extension tag a file uses to be declared against a URI.
    private static let v7ExtensionNamespace = "https://swarm.app/gedcom/v1/"

    /// Rewrite 5.5.1 output into 7.0.
    ///
    /// ponytail: a post-pass over the emitted lines rather than a version flag threaded
    /// through all 34 `appendValue` call sites. It is exact because every difference
    /// that reaches this layer is line-local: `CONC` is pure concatenation and so
    /// merges back losslessly, and the rest is tag and payload substitution. If 7.0
    /// output ever needs to differ in *structure* — emitting `ASSO`/`ROLE`, say — that
    /// is the point to give the serializer a real version parameter instead.
    private static func convertedToV7(_ lines: [String], tree: FamilyTree) -> [String] {
        // 1. CONC does not exist in 7.0, and 7.0 has no line-length limit: fold every
        // continuation back into the line it was split from.
        var merged: [String] = []
        for raw in lines {
            if gedcomTag(of: raw) == "CONC", !merged.isEmpty {
                merged[merged.count - 1] += gedcomValue(of: raw)
                continue
            }
            merged.append(raw)
        }

        // 2. Line-local substitutions.
        var out: [String] = []
        var tagAtLevel: [Int: String] = [:]
        var extensionTags: Set<String> = []
        var headInsertionPoint: Int?
        for raw in merged {
            guard var node = GEDCOMNode(rawLine: raw) else { out.append(raw); continue }
            let parent = tagAtLevel[node.level - 1] ?? ""
            tagAtLevel[node.level] = node.tag

            // The HEAD record ends where the next level-0 record begins; SCHMA has to
            // land inside it, after everything else HEAD declares.
            if node.level == 0, headInsertionPoint == nil, !out.isEmpty { headInsertionPoint = out.count }

            // 7.0 is UTF-8 only, so CHAR is gone, and LINEAGE-LINKED is not a 7.0 form.
            if node.level == 1, node.tag == "CHAR" { continue }
            if node.level == 2, parent == "GEDC" {
                if node.tag == "FORM" { continue }
                if node.tag == "VERS" { node.value = GEDCOMVersion.v70.headerValue }
            }
            // 5.5.1 named a format by convention; 7.0 requires an IANA media type.
            if node.level == 2, parent == "OBJE", node.tag == "FORM" {
                node.value = v7MediaType(node.value)
            }
            if let standard = v7TagEquivalents[node.tag] { node.tag = standard }
            if node.tag.hasPrefix("_") { extensionTags.insert(node.tag) }

            out.append(renderV7(node))
        }

        // 3. Declare every extension tag that survived, plus any a foreign 7.0 file
        // arrived with, so the file is self-describing.
        guard let insertionPoint = headInsertionPoint else { return out }
        var schema: [String] = []
        for tag in extensionTags.sorted() {
            let uri = tree.foreignSchemaTags[tag] ?? v7ExtensionNamespace + tag.dropFirst()
            schema.append("2 TAG \(tag) \(uri)")
        }
        guard !schema.isEmpty else { return out }
        out.insert(contentsOf: ["1 SCHMA"] + schema, at: insertionPoint)
        return out
    }

    /// Re-emit a tokenized line with 7.0's escaping rule: only a leading "@" is
    /// doubled, where 5.5.1 doubled the trailing one too.
    private static func renderV7(_ node: GEDCOMNode) -> String {
        var tokens = [String(node.level)]
        if let xref = node.xref { tokens.append("@\(xref)@") }
        tokens.append(node.tag)
        if let pointer = node.pointer {
            tokens.append("@\(pointer)@")
        } else if !node.value.isEmpty {
            tokens.append(node.value.hasPrefix("@") ? "@" + node.value : node.value)
        }
        return tokens.joined(separator: " ")
    }

    /// The media type 7.0 wants where 5.5.1 carried a bare format name.
    private static func v7MediaType(_ form: String) -> String {
        if form.contains("/") { return form }
        switch form.lowercased() {
        case "jpeg", "jpg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "tiff", "tif": return "image/tiff"
        case "bmp": return "image/bmp"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Line emission (GEDCOM 5.5.1 length limits)

    /// Collapse every character a reader would treat as a physical line break into a
    /// space, for the handful of values that are interpolated straight into a line
    /// instead of going through `appendValue`.
    ///
    /// These fields (a place, a tree name, an attachment title, the NAME structure) are
    /// single-line by nature, and the alternative — emitting `CONT` for them — would lose
    /// the continuation on the way back in, because the parser only recognises `_PLACID`
    /// and `WWW`/`TITL` continuations at that level. Collapsing keeps every character the
    /// user typed while making the pasted separator harmless.
    private static func singleLineValue(_ s: String) -> String {
        String(s.unicodeScalars.map { CharacterSet.newlines.contains($0) ? " " : Character($0) })
    }

    /// Strip slashes from a NAME part so they can't corrupt the `/surname/` structure.
    private static func sanitizeNamePart(_ s: String) -> String {
        singleLineValue(s).replacingOccurrences(of: "/", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Doubles the delimiting "@" of a value that would otherwise read back as a
    /// pointer. Only this exact shape is ambiguous: any inner "@" already disqualifies
    /// the token, so ordinary text containing an address is left alone.
    private static func escapingPointerShape(_ value: String) -> String {
        guard value.count >= 2, value.first == "@", value.last == "@",
              !value.dropFirst().dropLast().contains("@") else { return value }
        return "@" + value + "@"
    }

    /// Append a value that may contain line breaks: the first segment carries the tag and
    /// every later one becomes a `CONT`, with long segments split further across `CONC`.
    ///
    /// The split uses `CharacterSet.newlines` — deliberately the same set the two readers
    /// split physical lines on (`GEDCOMDocument.parse`, `GEDCOMParser.parse`). Splitting on
    /// "\n" alone used to let U+2028/U+2029/U+0085/VT/FF and a lone CR — all of which arrive
    /// routinely in text pasted from Word, a PDF or a web page — through into a physical
    /// line. On the way back in that line tore in half, and the half without a `level tag`
    /// prefix either failed the whole document (an imported tree, whose save re-parses its
    /// own output) or was silently skipped (the tree parser). Keeping the two sets identical
    /// is what makes that impossible rather than merely unlikely.
    private static func appendValue(_ level: Int, _ tag: String, value rawValue: String, to lines: inout [String]) {
        // CRLF first: `.newlines` would treat it as two separators and emit a blank CONT.
        let normalized = rawValue.replacingOccurrences(of: "\r\n", with: "\n")
        let segments = normalized.components(separatedBy: .newlines)
        appendSingleLine(level, tag, value: segments[0], to: &lines)
        for segment in segments.dropFirst() {
            appendSingleLine(level + 1, "CONT", value: segment, to: &lines)
        }
    }

    /// Append one `level tag value` line, splitting a long value across `CONC`
    /// continuation lines so no physical line exceeds the GEDCOM 5.5.1 limit
    /// (255 bytes incl. the level/tag prefix). Chunking is by UTF-8 byte budget so
    /// multi-byte Cyrillic text stays within bounds. The value must not contain a line
    /// break — `appendValue` is the caller that guarantees it.
    private static func appendSingleLine(_ level: Int, _ tag: String, value rawValue: String, to lines: inout [String]) {
        guard !rawValue.isEmpty else { lines.append("\(level) \(tag)"); return }
        // Text shaped exactly like "@X@" would tokenize as a pointer on re-import, so a
        // value the user typed into a field could leave the file naming a record that
        // does not exist. GEDCOM escapes a literal "@" by doubling it, which breaks the
        // pointer shape; `GEDCOMNode` undoes this on the way back in.
        let value = escapingPointerShape(rawValue)
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
            lines.append("2 PLAC \(singleLineValue(place))")
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
