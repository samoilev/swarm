import SwarmCore
import SwiftUI

struct RelationshipView: View {
    let tree: FamilyTree
    @Binding var isPresented: Bool
    var preselectedPerson: Person?

    @State private var personA: Person?
    @State private var personB: Person?
    @State private var result: RelationshipCalculator.RelationshipResult?
    @State private var searchA = ""
    @State private var searchB = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.tr("СВЯЗЬ МЕЖДУ РОДСТВЕННИКАМИ"))
                    .font(SepiaTheme.ui(size: 11))
                    .tracking(1.5)
                    .foregroundColor(SepiaTheme.accent2)
                    .fontWeight(.semibold)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(SepiaTheme.inkSoft)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().overlay(SepiaTheme.toolbarLine)

            VStack(spacing: 16) {
                // Person A picker
                personPicker(
                    label: L10n.tr("ПЕРВЫЙ ЧЕЛОВЕК"),
                    search: $searchA,
                    selected: $personA,
                    placeholder: L10n.tr("Выберите первого...")
                )

                // Person B picker
                personPicker(
                    label: L10n.tr("ВТОРОЙ ЧЕЛОВЕК"),
                    search: $searchB,
                    selected: $personB,
                    placeholder: L10n.tr("Выберите второго...")
                )

                // Calculate button
                Button {
                    calculateRelationship()
                } label: {
                    Label(L10n.tr("Определить связь"), systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(SepiaButtonStyle(isActive: true))
                .disabled(personA == nil || personB == nil)

                // Result
                if let result {
                    resultView(result)
                }
            }
            .padding(20)

            Spacer()
        }
        .frame(width: 440, height: 520)
        .background(SepiaTheme.paper)
        .onAppear {
            if let p = preselectedPerson {
                personA = p
                searchA = p.displayName(language: .current)
            }
        }
    }

    private func personPicker(label: String, search: Binding<String>, selected: Binding<Person?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SepiaTheme.ui(size: 9.5))
                .tracking(1.5)
                .foregroundColor(SepiaTheme.inkSoft)

            if let person = selected.wrappedValue {
                HStack {
                    Text(person.displayName(language: .current))
                        .font(SepiaTheme.body(size: 14))
                        .foregroundColor(SepiaTheme.ink)
                    Spacer()
                    Button {
                        selected.wrappedValue = nil
                        search.wrappedValue = ""
                        result = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SepiaTheme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TextField(placeholder, text: search)
                        .textFieldStyle(.roundedBorder)
                        .font(SepiaTheme.body(size: 14))
                        .colorMultiply(SepiaTheme.cardBg)

                    let filtered = filteredPeople(query: search.wrappedValue, excluding: personA?.id == selected.wrappedValue?.id ? personB : personA)
                    if !filtered.isEmpty && !search.wrappedValue.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(filtered.prefix(8), id: \.id) { person in
                                    Button {
                                        selected.wrappedValue = person
                                        search.wrappedValue = person.displayName(language: .current)
                                        result = nil
                                    } label: {
                                        HStack {
                                            Text(person.displayName(language: .current))
                                                .font(SepiaTheme.body(size: 13))
                                                .foregroundColor(SepiaTheme.ink)
                                            Spacer()
                                            if let dates = person.lifespan as String?, !dates.isEmpty {
                                                Text(dates)
                                                    .font(SepiaTheme.ui(size: 11))
                                                    .foregroundColor(SepiaTheme.inkSoft)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Divider().overlay(SepiaTheme.fieldLine)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        .background(SepiaTheme.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(SepiaTheme.cardLine, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func filteredPeople(query: String, excluding: Person?) -> [Person] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return tree.people.filter { person in
            person.id != excluding?.id && person.id != personA?.id && person.id != personB?.id
        }.filter { person in
            person.fullName.lowercased().contains(q) ||
                person.surname.lowercased().contains(q) ||
                person.givenNames.lowercased().contains(q)
        }.sorted { $0.sortName(language: .current) < $1.sortName(language: .current) }
    }

    private func resultView(_ result: RelationshipCalculator.RelationshipResult) -> some View {
        VStack(spacing: 10) {
            Divider().overlay(SepiaTheme.toolbarLine)

            Text(result.name)
                .font(SepiaTheme.display(size: 22))
                .fontWeight(.semibold)
                .foregroundColor(SepiaTheme.accent2)
                .multilineTextAlignment(.center)

            if !result.description.isEmpty {
                Text(result.description)
                    .font(SepiaTheme.body(size: 12.5))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            if result.path.count > 1 {
                Text(L10n.tr("В дереве: \(L10n.count(result.path.count - 1, .step))"))
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundColor(SepiaTheme.inkSoft)
            }
        }
        .padding(.top, 8)
    }

    private func calculateRelationship() {
        guard let a = personA, let b = personB else { return }
        let calc = RelationshipCalculator(tree: tree)
        result = calc.relationship(from: a, to: b)
    }
}
