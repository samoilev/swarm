import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var treeName: String = ""
    @State private var subtitle: String = ""
    @State private var step: Int = 0
    @State private var givenNames: String = ""
    @State private var patronymic: String = ""
    @State private var surname: String = ""
    @State private var sex: Person.Sex = .unknown
    @State private var birthPlace: String = ""
    @State private var deathPlace: String = ""
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable { case treeName, subtitle, givenNames, patronymic, surname }
    
    let onComplete: (FamilyTree) -> Void
    
    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()
            
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Создать родословное дерево")
                        .font(SepiaTheme.display(size: 26))
                        .foregroundColor(SepiaTheme.ink)
                    Text(step == 0 ? "Назовите вашу семейную запись" : "Добавьте первого человека")
                        .font(SepiaTheme.body(size: 14))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                .padding(.top, 32)
                .padding(.bottom, 24)
                
                HStack(spacing: 8) {
                    Circle().fill(step >= 0 ? SepiaTheme.accent : SepiaTheme.cardLine).frame(width: 8, height: 8)
                    Circle().fill(step >= 1 ? SepiaTheme.accent : SepiaTheme.cardLine).frame(width: 8, height: 8)
                }
                .padding(.bottom, 24)
                
                Divider().overlay(SepiaTheme.fieldLine)
                
                VStack(spacing: 20) {
                    if step == 0 {
                        treeNameStep
                    } else {
                        firstPersonStep
                    }
                }
                .padding(32)
                .frame(maxWidth: 400)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Отмена") { dismiss() }
                        .buttonStyle(SepiaButtonStyle())
                    if step > 0 {
                        Button("Назад") { withAnimation { step -= 1 } }
                            .buttonStyle(SepiaButtonStyle())
                    }
                    Spacer()
                    if step == 0 {
                        Button("Далее") { withAnimation { step = 1 }; focusedField = .givenNames }
                            .buttonStyle(SepiaButtonStyle(isActive: true))
                            .disabled(treeName.isEmpty)
                    } else {
                        Button("Создать") { createTree() }
                            .buttonStyle(SepiaButtonStyle(isActive: true))
                            .disabled(givenNames.isEmpty && surname.isEmpty)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 460)
    }
    
    private var treeNameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SepiaTextField(label: "НАЗВАНИЕ СЕМЬИ", text: $treeName, placeholder: "напр. Семья Ивановых")
                .focused($focusedField, equals: .treeName)
            SepiaTextField(label: "ПОДЗАГОЛОВОК (необяз.)", text: $subtitle, placeholder: "напр. Потомки Ивана и Марии")
                .focused($focusedField, equals: .subtitle)
        }
        .onAppear { focusedField = .treeName }
    }
    
    private var firstPersonStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SepiaTextField(label: "ИМЯ", text: $givenNames, placeholder: "напр. Иван")
                    .focused($focusedField, equals: .givenNames)
                SepiaTextField(label: "ОТЧЕСТВО", text: $patronymic, placeholder: "напр. Петрович")
                    .focused($focusedField, equals: .patronymic)
                SepiaTextField(label: "ФАМИЛИЯ", text: $surname, placeholder: "напр. Иванов")
                    .focused($focusedField, equals: .surname)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ПОЛ")
                    .font(SepiaTheme.ui(size: 9.5))
                    .tracking(1.5)
                    .foregroundColor(SepiaTheme.inkSoft)
                HStack(spacing: 8) {
                    ForEach(Person.Sex.allCases, id: \.rawValue) { s in
                        Button(s.displayName) { sex = s }
                            .buttonStyle(SepiaButtonStyle(isActive: sex == s))
                    }
                }
            }
            Text("Это будет первый человек в вашем дереве. Добавить родственников можно позже.")
                .font(SepiaTheme.body(size: 13))
                .foregroundColor(SepiaTheme.inkSoft)
                .padding(.top, 8)
            PlacePickerField(label: "МЕСТО РОЖДЕНИЯ", text: $birthPlace, placeholder: "напр. Москва, Россия")
            PlacePickerField(label: "МЕСТО СМЕРТИ", text: $deathPlace, placeholder: "—")
        }
    }
    
    private func createTree() {
        let tree = FamilyTree(name: treeName, subtitle: subtitle.isEmpty ? nil : subtitle)
        let person = Person(givenNames: givenNames, patronymic: patronymic.isEmpty ? nil : patronymic, surname: surname, sex: sex, birthPlace: birthPlace.isEmpty ? nil : birthPlace, deathPlace: deathPlace.isEmpty ? nil : deathPlace)
        tree.people.append(person)
        tree.homePersonId = person.id
        onComplete(tree)
    }
}

struct SepiaTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SepiaTheme.ui(size: 9.5))
                .tracking(1.5)
                .foregroundColor(SepiaTheme.inkSoft)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(SepiaTheme.body(size: 15))
                .foregroundColor(SepiaTheme.ink)
                .colorMultiply(Color(hex: "f5eed8"))
        }
    }
}
