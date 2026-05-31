import Foundation

/// Serializes a FamilyTree to GEDCOM 5.5.1 format.
/// This is the primary persistence format — each tree is stored as a .ged file.
struct GEDCOMSerializer {
    
    /// Serialize tree to GEDCOM string.
    /// Photos are saved to the mediaFolder; paths are relative in the GEDCOM.
    static func serialize(tree: FamilyTree, mediaFolder: URL? = nil) -> String {
        let idx = FamilyIndex(tree: tree)
        
        // Stable xref assignment: sort by creation date for deterministic output
        var indiXref: [UUID: String] = [:]
        var famXref: [UUID: String] = [:]
        
        for (i, p) in tree.people.enumerated() { indiXref[p.id] = "I\(i + 1)" }
        for (i, u) in tree.unions.enumerated() { famXref[u.id] = "F\(i + 1)" }
        
        var lines: [String] = []
        
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
            if p.birthDate != nil || p.birthPlace != nil {
                lines.append("1 BIRT")
                if let d = p.birthDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                if let pl = p.birthPlace { lines.append("2 PLAC \(pl)") }
            }
            
            // Death
            if !p.isLiving {
                lines.append("1 DEAT")
                if let d = p.deathDate { lines.append("2 DATE \(FamilyDate.toGEDCOM(d))") }
                if let pl = p.deathPlace { lines.append("2 PLAC \(pl)") }
            }
            
            // Burial
            if let b = p.burialPlace, !b.isEmpty {
                lines.append("1 BURI")
                lines.append("2 PLAC \(b)")
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
            
            // Photo (save to media folder, reference by filename)
            if let photoData = p.photoData, let mediaFolder = mediaFolder {
                let filename = "\(xref).jpg"
                let photoURL = mediaFolder.appendingPathComponent(filename)
                try? FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
                try? photoData.write(to: photoURL)
                lines.append("1 OBJE")
                lines.append("2 FILE \(filename)")
                lines.append("2 FORM JPEG")
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
        return lines.joined(separator: "\n")
    }
}

