import AppKit
import SwarmCore
import SwiftUI

/// First run. One screen collects the record and the first person; the second earns its
/// place by creating a *relationship*, because a tree of one person is not yet a tree —
/// kinship, the fan chart and the ⌘-click hint all need two people to mean anything.
///
/// Dates, places, sex and photographs are deliberately absent: they live in the person
/// card, which does them properly. Onboarding asks for the least that produces a tree.
///
/// It takes the whole window rather than sitting in a 480pt sheet. Creating a family
/// record is the one thing this app is for; a utility dialog was the wrong size for it,
/// and the width bought the right half of the screen — where the card the library will
/// hold is drawn live, filling in as the reader types.
struct OnboardingView: View {
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
    /// The record once it is on disk. Held so the done step can open it.
    @State private var createdTree: FamilyTree?
    @FocusState private var focusedField: Field?

    /// Stable identities for the three seats in the preview card. They stand in for people
    /// who do not exist yet, and they must not change as the reader types or the diagram
    /// would rebuild itself on every keystroke.
    @State private var previewIDs = (first: UUID(), second: UUID(), next: UUID())

    enum Step: Int { case record = 0, relative = 1, done = 2 }
    enum Field: Hashable {
        case treeName, subtitle, surname, givenNames, patronymic
        case relativeSurname, relativeGivenNames
    }

    /// Leaves without creating anything.
    var onCancel: () -> Void
    /// Writes the finished tree. It throws so the flow can report the failure itself,
    /// with everything the user typed still on screen and the button still live.
    let onComplete: (FamilyTree) async throws -> Void
    /// Hands the written record to the workspace.
    var onOpen: (FamilyTree) -> Void

    private static let leftColumnWidth: CGFloat = 612

    var body: some View {
        ZStack {
            SepiaPaperField(blooms: SepiaPaperField.single)

            HStack(spacing: 0) {
                leftColumn
                    .frame(width: Self.leftColumnWidth, alignment: .topLeading)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 44)

                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, 48)
                    .padding(.vertical, 44)
            }
        }
        .toolbar { onboardingToolbar }
        .toolbarBackground(SepiaTheme.toolbarBg, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 560)
        .onChange(of: step) { _, newValue in
            sepiaAnnounce("\(stepHeadline(newValue)). \(L10n.tr("Шаг \(newValue.rawValue + 1) из 2"))")
        }
    }

    // MARK: - Chrome

    @ToolbarContentBuilder private var onboardingToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            SepiaWordmark(label: L10n.tr("Новая запись"))
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .primaryAction) {
            Button(L10n.tr("Вернуться к библиотеке")) { onCancel() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private func stepHeadline(_ step: Step) -> String {
        switch step {
        case .record: L10n.tr("Назовите запись")
        case .relative: L10n.tr("Кто ещё?")
        case .done: trimmed(treeName)
        }
    }

    private func stepDeck(_ step: Step) -> String {
        switch step {
        case .record:
            L10n.tr("Один файл GEDCOM, одна папка, на этом Mac. Название можно изменить в любой момент.")
        case .relative:
            L10n.tr("Дерево начинается со связи. Выберите, кем приходится второй человек — или пропустите и добавьте родственников позже.")
        case .done:
            L10n.tr("Записано, проверено и сверено с диском. Дерево откроется на первом человеке.")
        }
    }

    // MARK: - The form

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Replaces the two capsules. A step indicator nobody can hear is not an
            // indicator, so the label and value stay exactly as they were.
            SepiaTrackedLabel(
                step == .done
                    ? L10n.tr("Готово")
                    : L10n.tr("Шаг \(step.rawValue + 1) из 2"),
                size: 10.5
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.tr("Шаг"))
            .accessibilityValue(L10n.tr("\(min(step.rawValue + 1, 2)) из 2"))

            VStack(alignment: .leading, spacing: 8) {
                Text(stepHeadline(step))
                    .font(SepiaTheme.display(size: 38))
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(stepDeck(step))
                    .font(SepiaTheme.body(size: 15))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440, alignment: .leading)
            }
            .padding(.top, 10)

            Group {
                switch step {
                case .record: recordStep
                case .relative: relativeStep
                case .done: doneStep
                }
            }
            .padding(.top, 26)
            // The column crossfades between steps; the preview beside it updates in place,
            // because the card is the one thing that is *not* being replaced.
            .id(step)
            .transition(.opacity)

            if let createError {
                failureBanner(createError)
            }

            Spacer(minLength: 20)

            footerRow
        }
        .sepiaMotion(SepiaMotion.state, value: step)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            if step == .relative {
                Button(L10n.tr("Назад")) { goBack() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(isSaving)
            }

            Spacer(minLength: 12)

            if step == .relative, role != nil {
                Button(L10n.tr("Пропустить родственника")) {
                    withMotion { role = nil }
                }
                .buttonStyle(.plain)
                .font(SepiaTheme.ui(size: 12.5))
                .foregroundColor(SepiaTheme.inkSoft)
                .disabled(isSaving)
            }

            Button(action: primaryAction) {
                HStack(spacing: 8) {
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
                .font(SepiaTheme.ui(size: 14))
                .fontWeight(.semibold)
                .frame(height: 38)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(SepiaTheme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
        .sepiaMotion(SepiaMotion.state, value: isSaving)
    }

    private var primaryLabel: String {
        switch step {
        case .record: L10n.tr("Далее")
        case .relative: isSaving ? L10n.tr("Создаём…") : L10n.tr("Создать дерево")
        case .done: L10n.tr("Открыть дерево")
        }
    }

    // MARK: - Step 1: the record and the first person

    private var recordStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            SepiaTextField(
                label: L10n.tr("НАЗВАНИЕ СЕМЬИ"),
                text: $treeName,
                placeholder: L10n.tr("напр. Семья Ивановых"),
                height: 46, radius: 12, fontSize: 17
            )
            .focused($focusedField, equals: .treeName)
            .onSubmit { primaryAction() }
            validationMessage(for: .treeName)

            SepiaTextField(
                label: L10n.tr("ПОДЗАГОЛОВОК (необяз.)"),
                text: $subtitle,
                placeholder: L10n.tr("напр. Потомки Ивана и Марии"),
                height: 46, radius: 12, fontSize: 17
            )
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
            HStack(alignment: .top, spacing: 14) {
                SepiaTextField(
                    label: language == .english ? L10n.tr("ОТЧЕСТВО (необяз.)") : L10n.tr("ОТЧЕСТВО"),
                    text: $patronymic,
                    placeholder: L10n.tr("напр. Петрович"),
                    height: 46, radius: 12, fontSize: 17
                )
                .focused($focusedField, equals: .patronymic)
                .onSubmit { primaryAction() }
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            validationMessage(for: .surname)

            Text(L10n.tr("Даты, места и фотографии добавите в карточке человека — там для них есть всё."))
                .font(SepiaTheme.ui(size: 12))
                .foregroundColor(SepiaTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .onAppear { focusedField = .treeName }
    }

    // MARK: - Step 2: the first relationship

    private var relativeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassEffectContainer(spacing: 9) {
                HStack(spacing: 9) {
                    ForEach(FirstRelative.allCases) { candidate in
                        relativeRoleButton(candidate)
                    }
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

                if role.inheritsSurname {
                    Text(L10n.tr("Фамилия подставлена от «\(firstPersonName)» — на этой стороне родства она обычно общая. Измените, если это не так."))
                        .font(SepiaTheme.ui(size: 12.5))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L10n.tr("Можно пропустить: нажмите «Создать дерево», родственников добавите позже."))
                    .font(SepiaTheme.ui(size: 12.5))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .sepiaMotion(SepiaMotion.state, value: role)
    }

    // MARK: - Step 3: what was written

    /// Not a congratulation. A receipt: the two paths that now exist on disk, so the
    /// reader knows where their family record lives before they ever open it.
    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            receiptLine("\(trimmed(treeName))/\(trimmed(treeName)).ged")
            receiptLine("Media/ · Attachments/ · .Swarm/History/")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("Записано на диск"))
    }

    private func receiptLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(SepiaTheme.pinBirth)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(SepiaTheme.inkSoft)
                .textSelection(.enabled)
        }
    }

    // MARK: - The card, drawn as it fills in

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            SepiaTrackedLabel(L10n.tr("Как она будет выглядеть в библиотеке"), size: 10.5)

            previewCard

            Text(L10n.tr("Карточка берёт форму у самого дерева — ничей портрет не подменяет собой всю семью."))
                .font(SepiaTheme.ui(size: 12))
                .foregroundColor(SepiaTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 400)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [SepiaTheme.photoA, SepiaTheme.photoB],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.5)

                TreeDiagramView(
                    diagram: previewDiagram,
                    scale: 1.15,
                    pendingNodeIDs: [previewIDs.next],
                    dimmedNodeIDs: hasRelativeName ? [] : [previewIDs.second]
                )
            }
            .frame(height: 118)
            .clipped()
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.5)).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(trimmed(treeName).isEmpty ? L10n.tr("Без названия") : trimmed(treeName))
                    .font(SepiaTheme.display(size: 20))
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1)
                Text(trimmed(subtitle).isEmpty ? " " : trimmed(subtitle))
                    .font(SepiaTheme.body(size: 12.5))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text(previewSurnames)
                    .font(SepiaTheme.ui(size: 12.5))
                    .fontWeight(.bold)
                    .foregroundColor(SepiaTheme.accent2)
                    .lineLimit(1)
                Text("\(L10n.tr("пока без дат")) · \(L10n.count(hasRelativeName ? 2 : 1, .person)) · \(L10n.tr("изменено только что"))")
                    .font(SepiaTheme.ui(size: 12))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(height: 226)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: SepiaTheme.ink.opacity(0.42), radius: 22, y: 12)
        // The card is the only thing on screen that is never replaced — it fills in.
        .sepiaMotion(SepiaMotion.state, value: hasRelativeName)
        .accessibilityHidden(true)
    }

    /// Two seats side by side and one waiting below. Fixed on purpose: the preview shows
    /// the *shape* a card takes, and re-laying it out on every keystroke would make the
    /// one thing that is supposed to stay put the busiest thing on the screen.
    private var previewDiagram: TreeDiagram {
        TreeDiagram(
            nodes: [
                TreeDiagram.Node(personId: previewIDs.first, sex: .unknown, isHome: true, x: 0, y: 0),
                TreeDiagram.Node(personId: previewIDs.second, sex: role?.sex ?? .unknown, isHome: false, x: 1, y: 0),
                TreeDiagram.Node(personId: previewIDs.next, sex: .unknown, isHome: false, x: 0.5, y: 1),
            ],
            links: [
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)],
                [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)],
            ],
            aspect: 3.4,
            generationCount: 2
        )
    }

    private var hasRelativeName: Bool {
        role != nil && !(trimmed(relativeSurname).isEmpty && trimmed(relativeGivenNames).isEmpty)
    }

    private var previewSurnames: String {
        let names = [trimmed(surname), hasRelativeName ? trimmed(relativeSurname) : ""]
            .filter { !$0.isEmpty }
        // Two people who share a surname are one name on the card, not the same word twice.
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        return unique.isEmpty ? " " : unique.joined(separator: " · ")
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
        HStack(alignment: .top, spacing: 14) {
            if language == .english {
                nameField(L10n.tr("ИМЯ"), givenNames, givenPlaceholder, givenFocus)
                nameField(L10n.tr("ФАМИЛИЯ"), surname, L10n.tr("напр. Иванов"), surnameFocus)
            } else {
                nameField(L10n.tr("ФАМИЛИЯ"), surname, L10n.tr("напр. Иванов"), surnameFocus)
                nameField(L10n.tr("ИМЯ"), givenNames, givenPlaceholder, givenFocus)
            }
        }
    }

    private func nameField(
        _ label: String,
        _ text: Binding<String>,
        _ placeholder: String,
        _ focus: Field
    ) -> some View {
        SepiaTextField(
            label: label,
            text: text,
            placeholder: placeholder,
            height: 46, radius: 12, fontSize: 17
        )
        .focused($focusedField, equals: focus)
        .onSubmit { primaryAction() }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .default
    }

    @ViewBuilder
    private func relativeRoleButton(_ candidate: FirstRelative) -> some View {
        let label = Text(candidate.label)
            .font(SepiaTheme.ui(size: 14.5))
            .fontWeight(.semibold)
            .frame(height: 38)
            .padding(.horizontal, 10)

        if role == candidate {
            Button { select(candidate) } label: { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(SepiaTheme.accent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button { select(candidate) } label: { label.foregroundStyle(SepiaTheme.ink) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }

    /// Selecting a role is a toggle, and it carries a smart default: relatives who
    /// usually share the surname get it filled in, so the common case is one word typed.
    private func select(_ candidate: FirstRelative) {
        guard role != candidate else {
            withMotion { role = nil }
            return
        }
        withMotion { role = candidate }
        if candidate.inheritsSurname, relativeSurname.isEmpty {
            relativeSurname = surname.trimmingCharacters(in: .whitespaces)
        }
        // The fields appear in this same frame; focus has to wait for them to exist.
        DispatchQueue.main.async {
            focusedField = relativeSurname.isEmpty ? .relativeSurname : .relativeGivenNames
        }
    }

    /// Every state change in this flow moves at the same speed, and stops moving entirely
    /// when the reader has asked for less motion.
    private func withMotion(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(SepiaMotion.state, change)
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
            withMotion { step = .relative }
        case .relative:
            createTree()
        case .done:
            guard let createdTree else { return }
            onOpen(createdTree)
        }
    }

    private func goBack() {
        invalidField = nil
        invalidMessage = nil
        withMotion { step = .record }
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
            withMotion { step = .record }
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
                createdTree = tree
                withMotion { step = .done }
                sepiaAnnounce(L10n.tr("Дерево «\(tree.name)» создано"))
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
    var height: CGFloat = 30
    var radius: CGFloat = 6
    var fontSize: CGFloat = 15
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(SepiaTheme.body(size: fontSize))
            .foregroundColor(SepiaTheme.ink)
            .focused($isFocused)
            .accessibilityLabel(label)
            .sepiaFieldChrome(
                isFocused: isFocused,
                placeholder: placeholder,
                isEmpty: text.isEmpty,
                height: height,
                radius: radius,
                fontSize: fontSize
            )
    }
}

struct SepiaTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var height: CGFloat = 30
    var radius: CGFloat = 6
    var fontSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SepiaFieldLabel(label)
            SepiaFieldInput(
                text: $text,
                placeholder: placeholder,
                label: label,
                height: height,
                radius: radius,
                fontSize: fontSize
            )
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
    @State private var isResizing = false
    @State private var isHoveringHandle = false
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
                // Drag handle straddling the bottom edge
                Capsule()
                    .fill(SepiaTheme.inkSoft.opacity(isResizing || isHoveringHandle ? 0.7 : 0.35))
                    .frame(width: 34, height: 3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .offset(y: 5)
                    .onHover { hovering in
                        isHoveringHandle = hovering
                        if hovering {
                            NSCursor.resizeUpDown.set()
                        } else if !isResizing {
                            NSCursor.arrow.set()
                        }
                    }
                    // Global space: the handle moves with the edge it resizes, so a local
                    // translation would cancel itself out and the drag would stall.
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    heightAtDragStart = height
                                    NSCursor.resizeUpDown.set()
                                }
                                height = min(420, max(60, heightAtDragStart + value.translation.height))
                            }
                            .onEnded { _ in
                                isResizing = false
                                heightAtDragStart = height
                                if !isHoveringHandle {
                                    NSCursor.arrow.set()
                                }
                            }
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
