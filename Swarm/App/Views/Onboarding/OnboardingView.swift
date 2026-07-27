import SwarmCore
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
    @State private var selectedBirthPlace: PlaceEntry?
    @State private var selectedDeathPlace: PlaceEntry?
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case treeName, subtitle, givenNames, patronymic, surname }

    let onComplete: (FamilyTree) -> Void

    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(L10n.tr("Создать родословное дерево"))
                        .font(SepiaTheme.display(size: 26))
                        .foregroundColor(SepiaTheme.ink)
                    Text(step == 0 ? L10n.tr("Назовите вашу семейную запись") : L10n.tr("Добавьте первого человека"))
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
                    Button(L10n.tr("Отмена")) { dismiss() }
                        .buttonStyle(SepiaButtonStyle())
                    if step > 0 {
                        Button(L10n.tr("Назад")) { withAnimation { step -= 1 } }
                            .buttonStyle(SepiaButtonStyle())
                    }
                    Spacer()
                    if step == 0 {
                        Button(L10n.tr("Далее")) { withAnimation { step = 1 }; focusedField = .givenNames }
                            .buttonStyle(SepiaButtonStyle(isActive: true))
                            .disabled(treeName.isEmpty)
                    } else {
                        Button(L10n.tr("Создать")) { createTree() }
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
            SepiaTextField(label: L10n.tr("НАЗВАНИЕ СЕМЬИ"), text: $treeName, placeholder: L10n.tr("напр. Семья Ивановых"))
                .focused($focusedField, equals: .treeName)
            SepiaTextField(label: L10n.tr("ПОДЗАГОЛОВОК (необяз.)"), text: $subtitle, placeholder: L10n.tr("напр. Потомки Ивана и Марии"))
                .focused($focusedField, equals: .subtitle)
        }
        .onAppear { focusedField = .treeName }
    }

    private var firstPersonStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SepiaTextField(label: L10n.tr("ИМЯ"), text: $givenNames, placeholder: L10n.tr("напр. Иван"))
                    .focused($focusedField, equals: .givenNames)
                SepiaTextField(label: L10n.tr("ОТЧЕСТВО"), text: $patronymic, placeholder: L10n.tr("напр. Петрович"))
                    .focused($focusedField, equals: .patronymic)
                SepiaTextField(label: L10n.tr("ФАМИЛИЯ"), text: $surname, placeholder: L10n.tr("напр. Иванов"))
                    .focused($focusedField, equals: .surname)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("ПОЛ"))
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
            Text(L10n.tr("Это будет первый человек в вашем дереве. Добавить родственников можно позже."))
                .font(SepiaTheme.body(size: 13))
                .foregroundColor(SepiaTheme.inkSoft)
                .padding(.top, 8)
            PlacePickerField(label: L10n.tr("МЕСТО РОЖДЕНИЯ"), text: $birthPlace, placeholder: L10n.tr("напр. Москва, Россия")) {
                selectedBirthPlace = $0
            }
            PlacePickerField(label: L10n.tr("МЕСТО СМЕРТИ"), text: $deathPlace, placeholder: "—") {
                selectedDeathPlace = $0
            }
        }
    }

    private func createTree() {
        let tree = FamilyTree(name: treeName, subtitle: subtitle.isEmpty ? nil : subtitle)
        let person = Person(givenNames: givenNames, patronymic: patronymic.isEmpty ? nil : patronymic, surname: surname, sex: sex, birthPlace: birthPlace.isEmpty ? nil : birthPlace, deathPlace: deathPlace.isEmpty ? nil : deathPlace)
        if let selectedBirthPlace, selectedBirthPlace.displayName == birthPlace {
            person.setStructuredPlace(selectedBirthPlace.placeReference, for: .birth)
        }
        if let selectedDeathPlace, selectedDeathPlace.displayName == deathPlace {
            person.setStructuredPlace(selectedDeathPlace.placeReference, for: .death)
        }
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

/// Multiline freeform notes field with a draggable bottom edge to resize vertically.
struct SepiaNotesField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    @State private var height: CGFloat = 90
    @State private var heightAtDragStart: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SepiaTheme.ui(size: 9.5))
                .tracking(1.5)
                .foregroundColor(SepiaTheme.inkSoft)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "f5eed8"))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SepiaTheme.fieldLine, lineWidth: 1))

                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(SepiaTheme.body(size: 15))
                        .foregroundColor(SepiaTheme.inkSoft.opacity(0.45))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(SepiaTheme.body(size: 15))
                    .foregroundColor(SepiaTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
            }
            .frame(height: height)
            .overlay(alignment: .bottom) {
                // Drag handle along the bottom edge
                ZStack {
                    Capsule()
                        .fill(SepiaTheme.inkSoft.opacity(0.35))
                        .frame(width: 28, height: 3)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            height = min(420, max(60, heightAtDragStart + value.translation.height))
                        }
                        .onEnded { _ in heightAtDragStart = height }
                )
            }
        }
    }
}

/// Structured date editor. It validates real Gregorian dates and keeps GEDCOM
/// qualifiers/ranges explicit instead of encoding them into an ambiguous text field.
struct SepiaDateField: View {
    let label: String
    @Binding var text: String
    @Binding var qualifier: GenealogyDate.Qualifier
    @Binding var endText: String
    var placeholder: String = L10n.tr("ДД.ММ.ГГГГ")

    init(
        label: String,
        text: Binding<String>,
        qualifier: Binding<GenealogyDate.Qualifier> = .constant(.exact),
        endText: Binding<String> = .constant(""),
        placeholder: String = L10n.tr("ДД.ММ.ГГГГ")
    ) {
        self.label = label
        _text = text
        _qualifier = qualifier
        _endText = endText
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SepiaTheme.ui(size: 9.5))
                .tracking(1.5)
                .foregroundColor(SepiaTheme.inkSoft)
            HStack(spacing: 8) {
                Picker("", selection: $qualifier) {
                    ForEach(GenealogyDate.Qualifier.allCases, id: \.rawValue) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 145)

                dateTextField(text: $text, placeholder: placeholder)
                if isRange {
                    Text(qualifier == .between ? L10n.tr("и") : L10n.tr("по"))
                        .font(SepiaTheme.body(size: 12))
                        .foregroundColor(SepiaTheme.inkSoft)
                    dateTextField(text: $endText, placeholder: placeholder)
                }
            }
            if !text.isEmpty && !isValidDate {
                Text(L10n.tr("Введите существующую дату или полный диапазон: ДД.ММ.ГГГГ, ММ.ГГГГ или ГГГГ"))
                    .font(SepiaTheme.ui(size: 9))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
    }

    private var isRange: Bool {
        qualifier == .between || qualifier == .fromTo
    }

    private var isValidDate: Bool {
        GenealogyDate(
            userInput: text,
            qualifier: qualifier,
            endValue: isRange ? endText : nil
        ).isValid
    }

    private func dateTextField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(SepiaTheme.body(size: 15))
            .foregroundColor(SepiaTheme.ink)
            .colorMultiply(Color(hex: "f5eed8"))
    }
}
