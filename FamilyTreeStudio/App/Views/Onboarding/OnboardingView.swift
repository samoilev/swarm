import FamilyTreeCore
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

/// Date field that only accepts ДД.ММ.ГГГГ, ММ.ГГГГ, or ГГГГ
struct SepiaDateField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = "ДД.ММ.ГГГГ"

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
                .onChange(of: text) { _, newValue in
                    let filtered = filterDateInput(newValue)
                    if filtered != newValue {
                        text = filtered
                    }
                }
            if !text.isEmpty && !isValidDateFormat(text) {
                Text("Формат: ДД.ММ.ГГГГ, ММ.ГГГГ или ГГГГ")
                    .font(SepiaTheme.ui(size: 9))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
    }

    /// Allow only digits and dots, auto-insert dots, limit length
    private func filterDateInput(_ input: String) -> String {
        // Remove anything that's not a digit or dot
        var cleaned = String(input.filter { $0.isNumber || $0 == "." })

        // Remove leading dots
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }

        // Remove consecutive dots
        while cleaned.contains("..") {
            cleaned = cleaned.replacingOccurrences(of: "..", with: ".")
        }

        // Limit: max 10 chars (DD.MM.YYYY)
        if cleaned.count > 10 {
            cleaned = String(cleaned.prefix(10))
        }

        // Limit to max 2 dots
        let dots = cleaned.filter { $0 == "." }
        if dots.count > 2 {
            // Keep only up to second dot
            var dotCount = 0
            var result = ""
            for ch in cleaned {
                if ch == "." {
                    dotCount += 1
                    if dotCount > 2 { break }
                }
                result.append(ch)
            }
            cleaned = result
        }

        return cleaned
    }

    private func isValidDateFormat(_ input: String) -> Bool {
        let str = input.trimmingCharacters(in: .whitespaces)
        if str.isEmpty { return true }

        // ГГГГ
        if str.range(of: #"^\d{4}$"#, options: .regularExpression) != nil { return true }
        // ММ.ГГГГ
        if str.range(of: #"^\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil {
            let parts = str.components(separatedBy: ".")
            if let m = Int(parts[0]), m >= 1, m <= 12 { return true }
        }
        // ДД.ММ.ГГГГ
        if str.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil {
            let parts = str.components(separatedBy: ".")
            if let d = Int(parts[0]), let m = Int(parts[1]), d >= 1, d <= 31, m >= 1, m <= 12 { return true }
        }
        // Partial input (still typing)
        if str.range(of: #"^\d{1,2}\.?$"#, options: .regularExpression) != nil { return true }
        if str.range(of: #"^\d{1,2}\.\d{1,2}\.?$"#, options: .regularExpression) != nil { return true }
        if str.range(of: #"^\d{1,2}\.\d{1,4}$"#, options: .regularExpression) != nil { return true }
        if str.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { return true }

        return false
    }
}
