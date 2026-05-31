import Foundation

struct SampleData {
    static func createHawthorneFamily() -> FamilyTree {
        let tree = FamilyTree(name: "The Hawthorne Family", subtitle: "Descendants of Edmund & Eleanor Hawthorne")
        
        let edmund = Person(givenNames: "Edmund", surname: "Hawthorne", sex: .male,
            birthDate: "4 Feb 1841", birthPlace: "Ludlow, Shropshire, England",
            deathDate: "19 Nov 1903", deathPlace: "Ludlow, Shropshire, England", isLiving: false,
            burialPlace: "St Laurence churchyard, Ludlow",
            occupation: "Master clockmaker", education: "Apprenticed, Worshipful Co. of Clockmakers",
            notes: "Founded the Hawthorne workshop on Broad Street in 1866.",
            sources: ["1851 England Census — Ludlow", "Parish register, St Laurence (baptism)"])
        
        let eleanor = Person(givenNames: "Eleanor", surname: "Hawthorne", maidenName: "Whitcombe", sex: .female,
            birthDate: "22 Aug 1846", birthPlace: "Hereford, England",
            deathDate: "7 Mar 1921", deathPlace: "Ludlow, Shropshire, England", isLiving: false,
            burialPlace: "St Laurence churchyard, Ludlow",
            occupation: "Kept the workshop ledgers",
            sources: ["Marriage register, Hereford 1866"])
        
        let arthur = Person(givenNames: "Arthur", surname: "Hawthorne", sex: .male,
            birthDate: "11 Jan 1868", birthPlace: "Ludlow, Shropshire, England",
            deathDate: "3 Jun 1939", deathPlace: "Shrewsbury, England", isLiving: false,
            burialPlace: "Shrewsbury General Cemetery",
            occupation: "Clockmaker & ironmonger", education: "Ludlow Grammar School",
            sources: ["1881 England Census", "Trade directory, Shrewsbury 1901"])
        
        let margaret = Person(givenNames: "Margaret", surname: "Hawthorne", maidenName: "Ellsworth", sex: .female,
            birthDate: "30 Sep 1872", birthPlace: "Shrewsbury, England",
            deathDate: "15 Feb 1944", deathPlace: "Shrewsbury, England", isLiving: false,
            occupation: "Schoolmistress")
        
        let beatrice = Person(givenNames: "Beatrice", surname: "Pembrook", maidenName: "Hawthorne", sex: .female,
            birthDate: "5 May 1871", birthPlace: "Ludlow, Shropshire, England",
            deathDate: "2 Dec 1952", deathPlace: "Bath, England", isLiving: false,
            occupation: "Watercolourist",
            sources: ["Passenger list, SS Lake Champlain 1898"])
        
        let charles = Person(givenNames: "Charles", surname: "Pembrook", sex: .male,
            birthDate: "17 Jul 1869", birthPlace: "Bristol, England",
            deathDate: "28 Apr 1930", deathPlace: "Bath, England", isLiving: false,
            occupation: "Solicitor")
        
        let frederick = Person(givenNames: "Frederick", surname: "Hawthorne", sex: .male,
            birthDate: "9 Oct 1875", birthPlace: "Ludlow, Shropshire, England",
            deathDate: "31 Jul 1917", deathPlace: "Passchendaele, Belgium", isLiving: false,
            burialPlace: "Tyne Cot Memorial, Belgium",
            occupation: "Lieutenant, King's Shropshire Light Infantry",
            notes: "Killed in action at the Third Battle of Ypres.",
            sources: ["CWGC casualty record", "Regimental war diary, 1917"])
        
        let henry = Person(givenNames: "Henry", surname: "Hawthorne", sex: .male,
            birthDate: "18 Mar 1899", birthPlace: "Shrewsbury, England",
            deathDate: "6 Jan 1981", deathPlace: "Oxford, England", isLiving: false,
            burialPlace: "Wolvercote Cemetery, Oxford",
            occupation: "Horologist & lecturer", education: "Jesus College, Oxford (1921)",
            notes: "Twice married. Wrote a standard text on escapement design (1948).",
            sources: ["Oxford University matriculation register"])
        
        let rose = Person(givenNames: "Rose", surname: "Hawthorne", maidenName: "Calder", sex: .female,
            birthDate: "24 Jun 1902", birthPlace: "Edinburgh, Scotland",
            deathDate: "12 Sep 1934", deathPlace: "Oxford, England", isLiving: false,
            burialPlace: "Wolvercote Cemetery, Oxford",
            occupation: "Botanical illustrator",
            sources: ["Scotland statutory birth record 1902"])
        
        let vivian = Person(givenNames: "Vivian", surname: "Hawthorne", maidenName: "Marsh", sex: .female,
            birthDate: "2 Feb 1908", birthPlace: "Oxford, England",
            deathDate: "19 Oct 1990", deathPlace: "Oxford, England", isLiving: false,
            occupation: "Librarian, Bodleian")
        
        let thomas = Person(givenNames: "Thomas", surname: "Hawthorne", sex: .male,
            birthDate: "7 May 1928", birthPlace: "Oxford, England",
            deathDate: "23 Mar 2010", deathPlace: "Cambridge, England", isLiving: false,
            burialPlace: "Ascension Parish Burial Ground, Cambridge",
            occupation: "Physicist", education: "Trinity College, Cambridge (1950)",
            sources: ["NPL staff records"])
        
        let dorothy = Person(givenNames: "Dorothy", surname: "Hawthorne", maidenName: "Kerr", sex: .female,
            birthDate: "16 Nov 1931", birthPlace: "Glasgow, Scotland",
            deathDate: "2 Jan 2018", deathPlace: "Cambridge, England", isLiving: false,
            occupation: "Translator (French & German)")
        
        let grace = Person(givenNames: "Grace", surname: "Hawthorne", sex: .female,
            birthDate: "11 Apr 1939", birthPlace: "Oxford, England",
            deathDate: "27 May 2021", deathPlace: "Bristol, England", isLiving: false,
            occupation: "Archivist", notes: "Half-sister to Thomas. Never married.")
        
        let nell = Person(givenNames: "Eleanor", surname: "Hawthorne", sex: .female,
            birthDate: "3 Sep 1955", birthPlace: "Cambridge, England", isLiving: true,
            occupation: "Documentary filmmaker", education: "University of Bristol (1977)",
            notes: "Known to all as \"Nell.\" Began this family record in 2019.")
        
        let james = Person(givenNames: "James", surname: "Hawthorne", sex: .male,
            birthDate: "28 Jan 1958", birthPlace: "Cambridge, England", isLiving: true,
            occupation: "Cellist", education: "Royal College of Music")
        
        let allPeople = [edmund, eleanor, arthur, margaret, beatrice, charles, frederick,
                         henry, rose, vivian, thomas, dorothy, grace, nell, james]
        tree.people = allPeople
        
        // Unions
        let u1 = Union(partner1Id: edmund.id, partner2Id: eleanor.id,
            marriageDate: "14 Apr 1866", marriagePlace: "Hereford",
            childrenIds: [arthur.id, beatrice.id, frederick.id])
        let u2 = Union(partner1Id: arthur.id, partner2Id: margaret.id,
            marriageDate: "2 Jun 1897", marriagePlace: "Shrewsbury",
            childrenIds: [henry.id])
        let u3 = Union(partner1Id: charles.id, partner2Id: beatrice.id,
            marriageDate: "1896", marriagePlace: "Bath")
        let u4 = Union(partner1Id: henry.id, partner2Id: rose.id,
            marriageDate: "21 Sep 1926", marriagePlace: "Edinburgh",
            status: "until 1934 (her death)", childrenIds: [thomas.id])
        let u5 = Union(partner1Id: henry.id, partner2Id: vivian.id,
            marriageDate: "4 Aug 1937", marriagePlace: "Oxford",
            childrenIds: [grace.id])
        let u6 = Union(partner1Id: thomas.id, partner2Id: dorothy.id,
            marriageDate: "8 Jul 1954", marriagePlace: "Cambridge",
            childrenIds: [nell.id, james.id])
        
        tree.unions = [u1, u2, u3, u4, u5, u6]
        tree.rootUnionId = u1.id
        tree.homePersonId = nell.id
        
        return tree
    }
}
