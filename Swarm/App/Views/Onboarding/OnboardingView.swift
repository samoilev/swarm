import AppKit
import SwarmCore
import SwiftUI

/// First run. One screen collects the record and the first person; the second earns its
/// place by creating a *relationship*, because a tree of one person is not yet a tree —
/// kinship, the fan chart and the ⌘-click hint all need two people to mean anything.
///
/// Dates, places, sex and photographs are deliberately absent: they live in the person
/// card, which does them properly. Onboarding asks for the least that produces a tree.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue

    // The record
    @State private var treeName = ""
    @State private var subtitle = ""
    // The first person
    @State private var surname = ""
    @State private var givenNames = ""
    @State private var patronymic = ""
    // The first relationship
    @State private var role: FirstRelative?
    @State private var relativeSurname = ""
    @State private var relativeGivenNames = ""

    @State private var step: Step = .record
    @State private var invalidField: Field?
    @State private var invalidMessage: String?
    /// Set when the verified write fails. Creation keeps its own error identity instead
    /// of borrowing the library's import alert.
    @State private var createError: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    enum Step: Int { case record = 0, relative = 1 }
    enum Field: Hashable {
        case treeName, subtitle, surname, givenNames, patronymic
        case relativeSurname, relativeGivenNames
    }

    /// Writes the finished tree. It throws so the sheet can report the failure itself,
    /// with everything the user typed still on screen and the button still live.
    let onComplete: (FamilyTree) async throws -> Void

    var body: some View {
        ZStack {
            LiquidGlassPanelBackground()

            VStack(spacing: 0) {
                header

                Group {
                    switch step {
                    case .record: recordStep
                    case .relative: relativeStep
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)

                if let createError {
                    failureBanner(createError)
                }

                buttonRow
            }
        }
        // Width is fixed, height is not: the two steps hold different amounts and a
        // pinned height either crams one or leaves the other mostly empty.
        .frame(width: 480)
        .background(SepiaTheme.paper)
        .onChange(of: step) { _, newValue in
            sepiaAnnounce("\(stepTitle(newValue)). \(L10n.tr("Шаг \(newValue.rawValue + 1) из 2"))")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 12) {
            LiquidGlassPanelHeader(
                title: stepTitle(step),
                subtitle: stepSubtitle,
                minimumHeight: 62,
                closeLabel: L10n.tr("Закрыть"),
                onClose: { dismiss() }
            )

            stepIndicator
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func stepTitle(_ step: Step) -> String {
        switch step {
        case .record: L10n.tr("Создать родословное дерево")
        case .relative: L10n.tr("Кто ещё?")
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .record: L10n.tr("Назовите семейную запись и впишите первого человека")
        case .relative: L10n.tr("Дерево начинается со связи между двумя людьми")
        }
    }

    /// Two capsules, but they carry a label and a value: a step indicator nobody can
    /// hear is not an indicator.
    private var stepIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0 ..< 2, id: \.self) { index in
                Capsule()
                    .fill(index == step.rawValue ? SepiaTheme.accent : SepiaTheme.cardLine)
                    .frame(width: index == step.rawValue ? 20 : 8, height: 5)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Шаг"))
        .accessibilityValue(L10n.tr("\(step.rawValue + 1) из 2"))
    }

    private var buttonRow: some View {
        LiquidGlassActionRow {
            if step == .relative {
                Button(L10n.tr("Назад")) { goBack() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(isSaving)
            }
            Spacer(minLength: 12)
            Button(L10n.tr("Отмена")) { dismiss() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityHidden(true)
                    }
                    Text(primaryLabel)
                    if !isSaving {
                        Image(systemName: step == .record ? "arrow.right" : "checkmark")
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(SepiaTheme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private var primaryLabel: String {
        switch step {
        case .record: L10n.tr("Далее")
        case .relative: isSaving ? L10n.tr("Создаём…") : L10n.tr("Создать дерево")
        }
    }

    // MARK: - Step 1: the record and the first person

    private var recordStep: some View {
        VStack(alignment: .leading, spacing: 15) {
            SepiaTextField(label: L10n.tr("НАЗВАНИЕ СЕМЬИ"), text: $treeName, placeholder: L10n.tr("напр. Семья Ивановых"))
                .focused($focusedField, equals: .treeName)
                .onSubmit { primaryAction() }
            validationMessage(for: .treeName)

            SepiaTextField(label: L10n.tr("ПОДЗАГОЛОВОК (необяз.)"), text: $subtitle, placeholder: L10n.tr("напр. Потомки Ивана и Марии"))
                .focused($focusedField, equals: .subtitle)
                .onSubmit { primaryAction() }

            titledRule(L10n.tr("Первый человек"))

            nameFields(
                surname: $surname,
                givenNames: $givenNames,
                surnameFocus: .surname,
                givenFocus: .givenNames,
                givenPlaceholder: L10n.tr("напр. Иван")
            )
            // Half width, so the name block reads as one two-column group instead of a
            // full-width field that looks more important than the given name.
            HStack(alignment: .top, spacing: 12) {
                SepiaTextField(
                    label: language == .english ? L10n.tr("ОТЧЕСТВО (необяз.)") : L10n.tr("ОТЧЕСТВО"),
                    text: $patronymic,
                    placeholder: L10n.tr("напр. Петрович")
                )
                .focused($focusedField, equals: .patronymic)
                .onSubmit { primaryAction() }
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            validationMessage(for: .surname)

            Text(L10n.tr("Даты, места и фотографии добавите в карточке человека — там для них есть всё."))
                .font(SepiaTheme.ui(size: 11.5))
                .foregroundColor(SepiaTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .onAppear { focusedField = .treeName }
    }

    // MARK: - Step 2: the first relationship

    private var relativeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Свяжем с: \(firstPersonName)"))
                .font(SepiaTheme.ui(size: 11.5))
                .foregroundColor(SepiaTheme.inkSoft)
                .lineLimit(1)

            HStack(spacing: 8) {
                ForEach(FirstRelative.allCases) { candidate in
                    relativeRoleButton(candidate)
                }
            }

            if let role {
                nameFields(
                    surname: $relativeSurname,
                    givenNames: $relativeGivenNames,
                    surnameFocus: .relativeSurname,
                    givenFocus: .relativeGivenNames,
                    givenPlaceholder: role.givenNameExample
                )
                validationMessage(for: .relativeGivenNames)
            }

            Text(role == nil
                ? L10n.tr("Можно пропустить: нажмите «Создать дерево», родственников добавите позже.")
                : L10n.tr("Мы запишем родство и откроем дерево — дальше можно достраивать в любую сторону."))
                .font(SepiaTheme.ui(size: 11.5))
                .foregroundColor(SepiaTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: role)
    }

    private var firstPersonName: String {
        let components = language == .english
            ? [givenNames, patronymic, surname]
            : [surname, givenNames, patronymic]
        let parts = components
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? L10n.tr("первый человек") : parts.joined(separator: " ")
    }

    private func nameFields(
        surname: Binding<String>,
        givenNames: Binding<String>,
        surnameFocus: Field,
        givenFocus: Field,
        givenPlaceholder: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if language == .english {
                SepiaTextField(label: L10n.tr("ИМЯ"), text: givenNames, placeholder: givenPlaceholder)
                    .focused($focusedField, equals: givenFocus)
                    .onSubmit { primaryAction() }
                SepiaTextField(label: L10n.tr("ФАМИЛИЯ"), text: surname, placeholder: L10n.tr("напр. Иванов"))
                    .focused($focusedField, equals: surnameFocus)
                    .onSubmit { primaryAction() }
            } else {
                SepiaTextField(label: L10n.tr("ФАМИЛИЯ"), text: surname, placeholder: L10n.tr("напр. Иванов"))
                    .focused($focusedField, equals: surnameFocus)
                    .onSubmit { primaryAction() }
                SepiaTextField(label: L10n.tr("ИМЯ"), text: givenNames, placeholder: givenPlaceholder)
                    .focused($focusedField, equals: givenFocus)
                    .onSubmit { primaryAction() }
            }
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .default
    }

    @ViewBuilder
    private func relativeRoleButton(_ candidate: FirstRelative) -> some View {
        if role == candidate {
            Button(candidate.label) { select(candidate) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(SepiaTheme.accent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(candidate.label) { select(candidate) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }

    /// Selecting a role is a toggle, and it carries a smart default: relatives who
    /// usually share the surname get it filled in, so the common case is one word typed.
    private func select(_ candidate: FirstRelative) {
        guard role != candidate else {
            role = nil
            return
        }
        role = candidate
        if candidate.inheritsSurname, relativeSurname.isEmpty {
            relativeSurname = surname.trimmingCharacters(in: .whitespaces)
        }
        // The fields appear in this same frame; focus has to wait for them to exist.
        DispatchQueue.main.async {
            focusedField = relativeSurname.isEmpty ? .relativeSurname : .relativeGivenNames
        }
    }

    // MARK: - Shared pieces

    /// A section break that names what follows. Not a card, not an eyebrow.
    private func titledRule(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(SepiaTheme.body(size: 13))
                .foregroundColor(SepiaTheme.ink)
            Rectangle()
                .fill(SepiaTheme.fieldLine)
                .frame(height: 1)
        }
        .padding(.top, 5)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func validationMessage(for field: Field) -> some View {
        if invalidField == field, let invalidMessage {
            Text(invalidMessage)
                .font(SepiaTheme.ui(size: 11.5))
                .foregroundColor(SepiaTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(SepiaTheme.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("Не удалось создать дерево"))
                    .font(SepiaTheme.body(size: 13.5))
                    .foregroundColor(SepiaTheme.ink)
                Text(message)
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(L10n.tr("Введённое сохранено — можно попробовать ещё раз."))
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(SepiaTheme.cardBg)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Flow

    private func primaryAction() {
        switch step {
        case .record:
            guard validateRecord() else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { step = .relative }
        case .relative:
            createTree()
        }
    }

    private func goBack() {
        invalidField = nil
        invalidMessage = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { step = .record }
    }

    /// Validation happens on submit rather than by disabling the button: a disabled
    /// primary that never says why is the state a first-time user hits first.
    private func validateRecord() -> Bool {
        invalidField = nil
        invalidMessage = nil
        if trimmed(treeName).isEmpty {
            return fail(.treeName, L10n.tr("Назовите дерево — под этим именем оно появится в архиве."))
        }
        if trimmed(surname).isEmpty, trimmed(givenNames).isEmpty {
            return fail(.surname, L10n.tr("Впишите имя или фамилию первого человека."))
        }
        return true
    }

    private func fail(_ field: Field, _ message: String) -> Bool {
        invalidField = field
        invalidMessage = message
        focusedField = field
        sepiaAnnounce(message)
        return false
    }

    private func createTree() {
        guard validateRecord() else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { step = .record }
            return
        }
        if role != nil, trimmed(relativeSurname).isEmpty, trimmed(relativeGivenNames).isEmpty {
            _ = fail(.relativeGivenNames, L10n.tr("Впишите имя родственника или снимите выбор роли."))
            return
        }

        let tree = FamilyTree(
            name: trimmed(treeName),
            subtitle: trimmed(subtitle).isEmpty ? nil : trimmed(subtitle)
        )
        let first = Person(
            givenNames: trimmed(givenNames),
            patronymic: trimmed(patronymic).isEmpty ? nil : trimmed(patronymic),
            surname: trimmed(surname)
        )
        tree.people.append(first)
        tree.homePersonId = first.id

        if let role {
            let relative = Person(
                givenNames: trimmed(relativeGivenNames),
                surname: trimmed(relativeSurname),
                sex: role.sex
            )
            tree.people.append(relative)
            tree.addRelation(role.relation, person: relative, target: first.id)
        }
        tree.optimizeRoot()

        createError = nil
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onComplete(tree)
                dismiss()
            } catch {
                createError = error.localizedDescription
                sepiaAnnounce(L10n.tr("Не удалось создать дерево"))
            }
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Field caption. 11pt with light tracking: the old 9.5pt tracked caps were below a
/// comfortable floor for an audience reading handwriting through this app.
struct SepiaFieldLabel: View {
    let text: String
    /// Hidden from VoiceOver when the control it captions carries the same name itself
    /// (a text field). A caption over a group of buttons is real content: pass `false`.
    let isDecorative: Bool

    init(_ text: String, isDecorative: Bool = true) {
        self.text = text
        self.isDecorative = isDecorative
    }

    var body: some View {
        Text(text)
            .font(SepiaTheme.ui(size: 11))
            .tracking(0.6)
            .foregroundColor(SepiaTheme.inkSoft)
            .accessibilityHidden(isDecorative)
    }
}

/// A sepia text input: our own fill, placeholder and focus ring. See `sepiaFieldChrome`
/// for why the system field plus a colour multiply was not good enough.
struct SepiaFieldInput: View {
    @Binding var text: String
    var placeholder: String = ""
    /// What VoiceOver should call this field. Without it the field announces its
    /// placeholder ("напр. Иванов") as its name.
    var label: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(SepiaTheme.body(size: 15))
            .foregroundColor(SepiaTheme.ink)
            .focused($isFocused)
            .accessibilityLabel(label)
            .sepiaFieldChrome(isFocused: isFocused, placeholder: placeholder, isEmpty: text.isEmpty)
    }
}

struct SepiaTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SepiaFieldLabel(label)
            SepiaFieldInput(text: $text, placeholder: placeholder, label: label)
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
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SepiaFieldLabel(label)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(SepiaTheme.fieldBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isFocused ? SepiaTheme.accent : SepiaTheme.cardLine,
                                lineWidth: isFocused ? 2 : 1
                            )
                    )

                if text.isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .font(SepiaTheme.body(size: 15))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .font(SepiaTheme.body(size: 15))
                    .foregroundColor(SepiaTheme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .accessibilityLabel(label)
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
        VStack(alignment: .leading, spacing: 5) {
            SepiaFieldLabel(label)
            HStack(spacing: 8) {
                Picker("", selection: $qualifier) {
                    ForEach(GenealogyDate.Qualifier.allCases, id: \.rawValue) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 145)
                .accessibilityLabel(L10n.tr("Уточнение даты"))

                SepiaFieldInput(text: $text, placeholder: placeholder, label: label)
                if isRange {
                    Text(qualifier == .between ? L10n.tr("и") : L10n.tr("по"))
                        .font(SepiaTheme.body(size: 12))
                        .foregroundColor(SepiaTheme.inkSoft)
                    SepiaFieldInput(
                        text: $endText,
                        placeholder: placeholder,
                        label: L10n.tr("\(label) — конец диапазона")
                    )
                }
            }
            if !text.isEmpty, !isValidDate {
                Text(L10n.tr("Введите существующую дату или полный диапазон: ДД.ММ.ГГГГ, ММ.ГГГГ или ГГГГ"))
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundColor(SepiaTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
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
}
