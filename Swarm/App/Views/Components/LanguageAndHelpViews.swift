import SwarmCore
import SwiftUI

struct LanguageSwitchControl: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @AppStorage(AppLanguage.choiceCompletedKey) private var choiceCompleted = false

    var compact = true

    var body: some View {
        Picker(L10n.tr("Язык интерфейса"), selection: languageBinding) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(compact ? .small : .regular)
        .help(L10n.tr("Переключить язык интерфейса"))
        .accessibilityLabel(L10n.tr("Язык интерфейса"))
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? .default },
            set: {
                languageRaw = $0.rawValue
                choiceCompleted = true
            }
        )
    }
}

struct LanguageChooserView: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @AppStorage(AppLanguage.choiceCompletedKey) private var choiceCompleted = false
    @FocusState private var focusedLanguage: AppLanguage?

    var body: some View {
        ZStack {
            SepiaTheme.toolbarBg.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(SepiaTheme.accent)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Выберите язык / Choose your language")
                        .font(SepiaTheme.display(size: 28))
                        .foregroundStyle(SepiaTheme.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Язык можно изменить в любой момент.\nYou can change this at any time.")
                        .font(SepiaTheme.body(size: 14))
                        .foregroundStyle(SepiaTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    languageButton(.russian)
                    languageButton(.english)
                }
            }
            .padding(38)
            .background(SepiaTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SepiaTheme.cardLine, lineWidth: 1)
            }
            .shadow(color: SepiaTheme.ink.opacity(0.12), radius: 20, y: 8)
        }
        .onAppear { focusedLanguage = .russian }
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        Button {
            languageRaw = language.rawValue
            choiceCompleted = true
        } label: {
            Text(language.displayName)
                .font(SepiaTheme.ui(size: 15))
                .fontWeight(.semibold)
                .frame(width: 128, height: 42)
        }
        .buttonStyle(SepiaButtonStyle(isActive: true))
        .focused($focusedLanguage, equals: language)
        .accessibilityHint(
            language == .russian
                ? "Открыть приложение на русском языке"
                : "Open the app in English"
        )
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Справка Swarm"))
                        .font(SepiaTheme.display(size: 25))
                        .foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Краткий путеводитель по семейному архиву"))
                        .font(SepiaTheme.body(size: 13))
                        .foregroundStyle(SepiaTheme.inkSoft)
                }
                Spacer()
                LanguageSwitchControl()
                Button(L10n.tr("Закрыть")) { dismiss() }
                    .buttonStyle(SepiaButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(22)

            Divider().overlay(SepiaTheme.fieldLine)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    helpSection(
                        L10n.tr("Первые шаги"),
                        L10n.tr("Создайте дерево или импортируйте GEDCOM, затем добавляйте людей и связывайте их как родителей, супругов, детей или братьев и сестёр. Изменения сохраняются автоматически.")
                    )
                    helpSection(
                        L10n.tr("Даты и термины"),
                        L10n.tr("Можно вводить полные и частичные даты, диапазоны и уточнения «около», «до» или «после». В английском интерфейсе используйте однозначную форму 5 Mar 1978; GEDCOM сохраняется в стандартном формате.")
                    )
                    helpSection(
                        L10n.tr("Родство"),
                        L10n.tr("Выберите человека, затем удерживайте ⌘ и выберите второго. Swarm покажет родство, включая неполнородные связи, двоюродное родство со смещением поколений и родство по браку.")
                    )
                    helpSection(
                        L10n.tr("Рабочие пространства"),
                        L10n.tr("Используйте схему дерева, список людей, хронологию, места, проверку данных, веер предков и карту. Все режимы работают с одной семейной записью.")
                    )
                    helpSection(
                        L10n.tr("Клавиатура"),
                        L10n.tr("⌘N — новое дерево, ⌘F — найти человека, ⌘Z — отменить, ⇧⌘Z — повторить, ⌘+ и ⌘− — масштаб, ⌘0 — вписать дерево.")
                    )
                    helpSection(
                        L10n.tr("Карта и конфиденциальность"),
                        L10n.tr("Поиск мест и офлайн-карта используют встроенный индекс. Apple Maps получает область просмотра только тогда, когда выбран системный провайдер; имена людей и семейные заметки Apple не передаются.")
                    )
                    helpSection(
                        L10n.tr("Восстановление и поддержка"),
                        L10n.tr("В меню архива откройте восстановление, чтобы вернуть прошлую редакцию, удалённый файл или резервную копию. Перед восстановлением Swarm показывает, что именно будет заменено. Для помощи или сообщения об ошибке откройте страницу поддержки; не прикладывайте приватные семейные данные.")
                    )
                    Link(
                        L10n.tr("Открыть поддержку на GitHub"),
                        destination: URL(string: "https://github.com/samoilev/swarm/issues")!
                    )
                    .font(SepiaTheme.ui(size: 13))
                }
                .padding(24)
            }
        }
        .frame(width: 680, height: 650)
        .background(SepiaTheme.paper)
    }

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SepiaTheme.ui(size: 14))
                .fontWeight(.bold)
                .foregroundStyle(SepiaTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(SepiaTheme.body(size: 13.5))
                .foregroundStyle(SepiaTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
