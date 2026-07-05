import Foundation

/// Serializes a FamilyTree to GEDCOM 5.5.1 format.
/// This is the primary persistence format — each tree is stored as a .ged file.
public struct GEDCOMSerializer {

    /// A person portrait the GEDCOM references, paired with the filename used in its
    /// `OBJE`/`FILE` line. The caller persists the bytes — serialization stays pure.
    public struct Photo: Equatable {
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

        var lines: [String] = []
        var photos: [Photo] = []

        // HEAD
        lines.append("0 HEAD")
        lines.append("1 SOUR FamilyTreeStudio")
        lines.append("2 NAME Родословная Студия")
        lines.append("2 VERS 1.0")
        lines.append("1 GEDC")
        lines.append("2 VERS 5.5.1")
        lines.append("2 FORM LINEAGE-LINKED")
        lines.append("1 CHAR UTF-8")
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy"
        df.locale = Locale(identifier: "en_US_POSIX")
        lines.append("1 DATE \(df.string(from: Date()).uppercased())")
        // Custom metadata
        lines.append("1 _TREEID \(tree.id.uuidString)")
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

            // NAME — use maiden name as birth surname if available. Strip any slash from
            // the parts: a "/" in a given name would corrupt the NAME line's structure.
            let given = sanitizeNamePart(p.givenNames)
            let birthSurname = sanitizeNamePart(p.maidenName ?? p.surname)
            lines.append("1 NAME \(given) /\(birthSurname)/")

            // Married name (if maiden differs from current surname)
            if let maiden = p.maidenName, !maiden.isEmpty, maiden != p.surname {
                lines.append("2 _MARNM \(given) /\(sanitizeNamePart(p.surname))/")
            }

            // Patronymic (custom tag)
            if let patr = p.patronymic, !patr.isEmpty {
                lines.append("1 _PATR \(patr)")
            }

            if p.sex != .unknown { lines.append("1 SEX \(p.sex.rawValue)") }

            // Birth
            let hasBirthCoord = p.birthLat != nil && p.birthLon != nil
            let birthExtras = p.eventExtras["BIRT"] ?? []
            if p.birthDate != nil || (p.birthPlace?.isEmpty == false) || hasBirthCoord || !birthExtras.isEmpty {
                lines.append("1 BIRT")
                if let d = p.birthDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                appendPlace(p.birthPlace, lat: p.birthLat, lon: p.birthLon, to: &lines)
                lines.append(contentsOf: birthExtras)
            }

            // Death
            let deathExtras = p.eventExtras["DEAT"] ?? []
            if !p.isLiving || !deathExtras.isEmpty {
                lines.append("1 DEAT")
                if let d = p.deathDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                appendPlace(p.deathPlace, lat: p.deathLat, lon: p.deathLon, to: &lines)
                lines.append(contentsOf: deathExtras)
            }

            // Burial (place and/or precise grave coordinates)
            let hasBurialCoord = p.burialLat != nil && p.burialLon != nil
            let burialExtras = p.eventExtras["BURI"] ?? []
            if (p.burialPlace?.isEmpty == false) || hasBurialCoord || !burialExtras.isEmpty {
                lines.append("1 BURI")
                appendPlace(p.burialPlace, lat: p.burialLat, lon: p.burialLon, to: &lines)
                lines.append(contentsOf: burialExtras)
            }

            // Occupation & Education
            if let o = p.occupation, !o.isEmpty { appendValue(1, "OCCU", value: o, to: &lines) }
            if let e = p.education, !e.isEmpty { appendValue(1, "EDUC", value: e, to: &lines) }

            // Notes (multi-line via CONT; long lines split further via CONC)
            if let n = p.notes, !n.isEmpty {
                let noteLines = n.components(separatedBy: "\n")
                appendValue(1, "NOTE", value: noteLines[0], to: &lines)
                for noteLine in noteLines.dropFirst() {
                    appendValue(2, "CONT", value: noteLine, to: &lines)
                }
            }

            // Sources (kept as single lines: citation text is short in practice)
            for s in p.sources {
                lines.append("1 SOUR \(s)")
            }

            // Photo — referenced by filename here. The bytes are returned in
            // `Result.photos` (for the caller to persist) ONLY when they actually
            // changed this session, so an unchanged portrait is never force-loaded from
            // disk just to rewrite an identical file.
            if p.hasPhoto {
                let filename = p.photoFilename ?? "\(xref).jpg"
                lines.append("1 OBJE")
                lines.append("2 FILE \(filename)")
                lines.append("2 FORM \(filename.lowercased().hasSuffix(".png") ? "PNG" : "JPEG")")
                if p.photoIsDirty, let bytes = p.photoData {
                    photos.append(Photo(filename: filename, data: bytes))
                }
            }

            // Attachments — referenced by relative path; the bytes live on disk in
            // the tree's Attachments/ folder (written when the file is attached).
            for att in p.attachments {
                lines.append("1 _ATTC")
                lines.append("2 FILE Attachments/\(att.storedName)")
                lines.append("2 TITL \(att.originalName)")
            }

            // Family links
            for union in idx.unionsOf[p.id] ?? [] {
                if let fx = famXref[union.id] { lines.append("1 FAMS @\(fx)@") }
            }
            if let pu = idx.childOf[p.id], let fx = famXref[pu.id] {
                lines.append("1 FAMC @\(fx)@")
            }

            // Preserved unmodeled level-1 branches from an imported file, verbatim.
            for branch in p.unknownBranches { lines.append(contentsOf: branch) }
        }

        // FAM records
        for u in tree.unions {
            guard let fx = famXref[u.id] else { continue }
            lines.append("0 @\(fx)@ FAM")

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

            // Marriage
            if u.marriageDate != nil || u.marriagePlace != nil || !u.marriageExtras.isEmpty {
                lines.append("1 MARR")
                if let d = u.marriageDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                if let pl = u.marriagePlace { lines.append("2 PLAC \(pl)") }
                lines.append(contentsOf: u.marriageExtras)
            }

            // Divorce / status
            if let st = u.status, !st.isEmpty {
                if st == "divorced" {
                    lines.append("1 DIV")
                } else {
                    lines.append("1 _STAT \(st)")
                }
            }

            // Preserved unmodeled level-1 branches from an imported file, verbatim.
            for branch in u.unknownBranches { lines.append(contentsOf: branch) }
        }

        // Whole top-level records the app doesn't model (SOUR, SUBM, …), re-emitted
        // verbatim so a foreign file survives import → re-export.
        for record in tree.unknownRecords { lines.append(contentsOf: record) }

        lines.append("0 TRLR")
        return Result(gedcom: lines.joined(separator: "\n"), photos: photos)
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
    private static func appendPlace(_ place: String?, lat: Double?, lon: Double?, to lines: inout [String]) {
        if let place, !place.isEmpty {
            lines.append("2 PLAC \(place)")
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
