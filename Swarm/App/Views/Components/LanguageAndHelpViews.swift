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
                Text(L10n.tr("Справка Swarm"))
                    .font(SepiaTheme.display(size: 25))
                    .foregroundStyle(SepiaTheme.ink)
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
                        L10n.tr("Создайте дерево или импортируйте файл GEDCOM. Изменения в карточке нужно сохранять кнопкой «Сохранить». Остальные изменения сохраняются автоматически.")
                    )
                    helpSection(
                        L10n.tr("Даты"),
                        L10n.tr("Укажите полную дату (05.03.1978), месяц и год (03.1978) или только год (1978). Если точная дата неизвестна, выберите «Около», «До» или «После».")
                    )
                    helpSection(
                        L10n.tr("Родство"),
                        L10n.tr("Выберите человека, затем нажмите на другого, удерживая ⌘. Swarm покажет, кем они приходятся друг другу, в том числе по браку.")
                    )
                    helpSection(
                        L10n.tr("Виды дерева"),
                        L10n.tr("Переключайтесь между схемой дерева, списком людей, хронологией, местами, проверкой, веером предков и картой. Во всех разделах — данные одного дерева.")
                    )
                    helpSection(
                        L10n.tr("Клавиатура"),
                        L10n.tr("⌘F — поиск, ⌘Z — отменить, ⇧⌘Z — повторить. ⌘+ и ⌘− — изменить масштаб, ⌘0 — показать дерево целиком.")
                    )
                    helpSection(
                        L10n.tr("Карта и данные"),
                        L10n.tr("Поиск мест и карта без интернета работают на этом Mac. Названия мест взяты из GeoNames, контуры — из Natural Earth. Справочник охватывает бывший СССР, Европу и Северную Америку. Координаты сохраняются в GEDCOM. При использовании Apple Maps Apple видит, какой участок карты открыт.")
                    )
                    helpSection(
                        L10n.tr("Восстановление"),
                        L10n.tr("Чтобы открыть предыдущие версии, нажмите «Сохранено» или выберите их в меню дерева. Хранятся последние 50 версий без фотографий и вложений. В разделе «Восстановление» можно вернуть удалённые файлы в течение 30 дней после удаления, а также найти резервные копии и деревья из архива.")
                    )
                    helpSection(
                        L10n.tr("Поддержка"),
                        L10n.tr("Задайте вопрос или сообщите об ошибке на GitHub. Не прикладывайте семейные данные.")
                    )
                    Link(
                        L10n.tr("Написать в поддержку на GitHub"),
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
