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
            SepiaPaperField(blooms: SepiaPaperField.single)

            // A ghost of the thing the app is for, sitting far enough back to be texture
            // rather than illustration. It also introduces the drawing every library card
            // will use, before the reader has seen one.
            TreeDiagramView(diagram: .placeholder, style: .watermark, scale: 2.9)

            VStack(spacing: 8) {
                Text("Choose your language\nВыберите язык")
                    .font(SepiaTheme.display(size: 24))
                    .foregroundStyle(SepiaTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("You can change this at any time.\nЯзык можно изменить в любой момент.")
                    .font(SepiaTheme.body(size: 13.5))
                    .foregroundStyle(SepiaTheme.inkSoft)
                    .multilineTextAlignment(.center)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        languageButton(.russian)
                        languageButton(.english)
                    }
                    .focusSection()
                }
                .padding(.top, 18)
            }
            .padding(.top, 44)
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
            .frame(width: 560)
            .glassEffect(
                .regular.tint(SepiaTheme.paper.opacity(0.66)),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .shadow(color: SepiaTheme.ink.opacity(0.34), radius: 35, y: 20)
        }
        // Lights and the wordmark, and nothing else: the app introduces itself before it
        // asks anything.
        .toolbar {
            ToolbarItem(placement: .navigation) { SepiaWordmark() }
                .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackground(SepiaTheme.toolbarBg, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .defaultFocus($focusedLanguage, .russian)
        .onAppear { DispatchQueue.main.async { focusedLanguage = .russian } }
    }

    /// Both buttons wear the same neutral glass. Neither is pre-selected — the choice is
    /// the entire point of the screen, and tinting one of them answers it for the reader.
    private func languageButton(_ language: AppLanguage) -> some View {
        Button {
            languageRaw = language.rawValue
            choiceCompleted = true
        } label: {
            Text(language.displayName)
                .font(SepiaTheme.ui(size: 16))
                .fontWeight(.semibold)
                .foregroundStyle(SepiaTheme.ink)
                .frame(width: 170, height: 46)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .focusable()
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
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue

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
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
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
                        L10n.tr("⌘F — найти человека, ⌘Z — отменить, ⇧⌘Z — повторить, ⌘+ и ⌘− — масштаб, ⌘0 — вписать дерево.")
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
        .id(languageRaw)
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
