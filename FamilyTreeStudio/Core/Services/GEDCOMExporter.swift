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
        
        // Stable xref assignment: sort by creation date for deterministic output
        var indiXref: [UUID: String] = [:]
        var famXref: [UUID: String] = [:]
        
        for (i, p) in tree.people.enumerated() { indiXref[p.id] = "I\(i + 1)" }
        for (i, u) in tree.unions.enumerated() { famXref[u.id] = "F\(i + 1)" }

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
            
            // NAME — use maiden name as birth surname if available
            let birthSurname = p.maidenName ?? p.surname
            lines.append("1 NAME \(p.givenNames) /\(birthSurname)/")
            
            // Married name (if maiden differs from current surname)
            if let maiden = p.maidenName, !maiden.isEmpty, maiden != p.surname {
                lines.append("2 _MARNM \(p.givenNames) /\(p.surname)/")
            }
            
            // Patronymic (custom tag)
            if let patr = p.patronymic, !patr.isEmpty {
                lines.append("1 _PATR \(patr)")
            }
            
            if p.sex != .unknown { lines.append("1 SEX \(p.sex.rawValue)") }
            
            // Birth
            let hasBirthCoord = p.birthLat != nil && p.birthLon != nil
            if p.birthDate != nil || (p.birthPlace?.isEmpty == false) || hasBirthCoord {
                lines.append("1 BIRT")
                if let d = p.birthDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                appendPlace(p.birthPlace, lat: p.birthLat, lon: p.birthLon, to: &lines)
            }

            // Death
            if !p.isLiving {
                lines.append("1 DEAT")
                if let d = p.deathDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                appendPlace(p.deathPlace, lat: p.deathLat, lon: p.deathLon, to: &lines)
            }

            // Burial (place and/or precise grave coordinates)
            let hasBurialCoord = p.burialLat != nil && p.burialLon != nil
            if (p.burialPlace?.isEmpty == false) || hasBurialCoord {
                lines.append("1 BURI")
                appendPlace(p.burialPlace, lat: p.burialLat, lon: p.burialLon, to: &lines)
            }
            
            // Occupation & Education
            if let o = p.occupation, !o.isEmpty { lines.append("1 OCCU \(o)") }
            if let e = p.education, !e.isEmpty { lines.append("1 EDUC \(e)") }
            
            // Notes (multi-line via CONT)
            if let n = p.notes, !n.isEmpty {
                let noteLines = n.components(separatedBy: "\n")
                lines.append("1 NOTE \(noteLines[0])")
                for noteLine in noteLines.dropFirst() {
                    lines.append("2 CONT \(noteLine)")
                }
            }
            
            // Sources
            for s in p.sources { lines.append("1 SOUR \(s)") }
            
            // Photo — referenced by filename here; the bytes are returned in
            // `Result.photos` for the caller to persist into the media folder.
            if let photoData = p.photoData {
                let filename = "\(xref).jpg"
                photos.append(Photo(filename: filename, data: photoData))
                lines.append("1 OBJE")
                lines.append("2 FILE \(filename)")
                lines.append("2 FORM JPEG")
            }

            // Attachments — referenced by relative path; the bytes live on disk in
            // the tree's Attachments/ folder (written when the file is attached).
            for att in p.attachments {
                lines.append("1 _ATTC")
                lines.append("2 FILE Attachments/\(att.storedName)")
                lines.append("2 TITL \(att.originalName)")
            }

            // Family links
            for union in (idx.unionsOf[p.id] ?? []) {
                if let fx = famXref[union.id] { lines.append("1 FAMS @\(fx)@") }
            }
            if let pu = idx.childOf[p.id], let fx = famXref[pu.id] {
                lines.append("1 FAMC @\(fx)@")
            }
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
            if u.marriageDate != nil || u.marriagePlace != nil {
                lines.append("1 MARR")
                if let d = u.marriageDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                if let pl = u.marriagePlace { lines.append("2 PLAC \(pl)") }
            }
            
            // Divorce / status
            if let st = u.status, !st.isEmpty {
                if st == "divorced" {
                    lines.append("1 DIV")
                } else {
                    lines.append("1 _STAT \(st)")
                }
            }
        }
        
        lines.append("0 TRLR")
        return Result(gedcom: lines.joined(separator: "\n"), photos: photos)
    }

    // MARK: - Coordinate / place emission

    /// Emit a `2 PLAC` line and, when coordinates are present, the standard
    /// `3 MAP / 4 LATI / 4 LONG` triple so other genealogy software reads them.
    /// If coordinates exist but there is no place to host a MAP, fall back to the
    /// private `2 _COORD lat lon` so the app's own data still round-trips.
    private static func appendPlace(_ place: String?, lat: Double?, lon: Double?, to lines: inout [String]) {
        if let place = place, !place.isEmpty {
            lines.append("2 PLAC \(place)")
            if let lat = lat, let lon = lon {
                lines.append("3 MAP")
                lines.append("4 LATI \(gedLat(lat))")
                lines.append("4 LONG \(gedLong(lon))")
            }
        } else if let lat = lat, let lon = lon {
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

