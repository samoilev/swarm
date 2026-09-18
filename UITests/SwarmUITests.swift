import AppKit
import XCTest

private let swarmUITestHostURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(".build/debug/SwarmUITestHost.app", isDirectory: true)

final class SwarmUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storageURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        app = XCUIApplication(url: swarmUITestHostURL)
        app.launchArguments = ["-appLanguage", "ru", "--storage-folder", storageURL.path]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: storageURL)
    }

    func testCreateEditAndCancelPersonLeavesSavedValue() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let name = app.textFields["ИМЯ"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click(); name.typeKey("a", modifierFlags: .command); name.typeText("Несохранённое")
        app.buttons["Отмена"].firstMatch.click()
        XCTAssertFalse(app.staticTexts["Несохранённое"].exists)
    }

    /// The card's controls stop scrolling with the record: on a person too long to fit,
    /// the edit and close circles are still in the corner, and closing the card does not
    /// mean scrolling back to the top to find the button first.
    func testCardActionsStayReachableWhileScrolled() {
        createInitialTree()
        // A record long enough to need scrolling. Notes are the cheapest way to make one:
        // a single wrapped paragraph fills the card several screens deep.
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let notes = app.textViews.firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.click()
        notes.typeText(String(repeating: "Запись в метрической книге прихода. ", count: 60))
        app.buttons["Сохранить"].firstMatch.click()

        let close = app.buttons["Закрыть карточку"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let restingCorner = close.frame.origin

        let scroller = app.scrollViews.firstMatch
        XCTAssertTrue(scroller.waitForExistence(timeout: 5))
        scroller.scroll(byDeltaX: 0, deltaY: -600)

        XCTAssertTrue(app.buttons["Редактировать"].firstMatch.isHittable, "Edit scrolled out of reach")
        XCTAssertTrue(close.isHittable, "Close scrolled out of reach")
        XCTAssertEqual(close.frame.origin.x, restingCorner.x, accuracy: 1, "Close moved sideways")
        XCTAssertEqual(close.frame.origin.y, restingCorner.y, accuracy: 1, "Close did not stay pinned")

        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2), "The card stayed open after Close")
    }

    /// The whole point of the sources rebuild: an entry you add is visible in a list,
    /// survives a save/reopen, and can be changed and removed. Fields are addressed by
    /// accessibility identifier because labels like НАЗВАНИЕ appear more than once in
    /// this editor.
    func testSourceEntryCanBeAddedEditedAndDeleted() {
        // Sources do not need an imported fixture; onboarding leaves a person to edit.
        // The import route cannot be driven from this harness (see the skipped
        // open-GEDCOM test), so this journey no longer depends on it.
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["ИСТОЧНИКИ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Добавить источник"].exists)
        XCTAssertFalse(app.buttons["Изменить источник"].exists)

        func field(_ identifier: String) -> XCUIElement {
            app.textFields[identifier].firstMatch
        }

        // The form stays closed until it is asked for.
        XCTAssertFalse(field("source.title").exists)
        app.buttons["Добавить источник"].click()
        field("source.title").click()
        field("source.title").typeText("Метрическая книга")
        field("source.fond").click(); field("source.fond").typeText("350")
        field("source.opis").click(); field("source.opis").typeText("2")
        field("source.delo").click(); field("source.delo").typeText("1841")
        app.buttons["Сохранить источник"].click()

        XCTAssertTrue(app.staticTexts["Метрическая книга"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Ф. 350 · Оп. 2 · Д. 1841"].exists)
        XCTAssertFalse(app.staticTexts["Источники не добавлены"].exists)

        // Save, reopen: the entry reads back. This is the gap the rebuild exists to close.
        app.buttons["Сохранить"].click()
        XCTAssertTrue(app.staticTexts["Иванов Иван"].waitForExistence(timeout: 5))
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Ф. 350 · Оп. 2 · Д. 1841"].waitForExistence(timeout: 3))

        // Edit it in place, through the row's own edit button.
        XCTAssertFalse(field("source.delo").exists)
        app.buttons["Изменить источник"].firstMatch.click()
        let delo = field("source.delo")
        delo.click(); delo.typeKey("a", modifierFlags: .command); delo.typeText("1842")
        app.buttons["Сохранить источник"].click()
        XCTAssertTrue(app.staticTexts["Ф. 350 · Оп. 2 · Д. 1842"].waitForExistence(timeout: 3))

        // Delete it.
        app.buttons["Удалить источник"].firstMatch.click()
        XCTAssertTrue(app.buttons["Добавить источник"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Изменить источник"].exists)
        app.buttons["Сохранить"].click()
        XCTAssertTrue(app.staticTexts["Иванов Иван"].waitForExistence(timeout: 5))
    }

    /// Cancel discards the draft, sources included.
    func testCancellingTheEditorDiscardsANewSourceEntry() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["ИСТОЧНИКИ"].waitForExistence(timeout: 3))
        app.buttons["Добавить источник"].click()
        let title = app.textFields["source.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click(); title.typeText("Не сохранится")
        app.buttons["Сохранить источник"].click()
        XCTAssertTrue(app.staticTexts["Не сохранится"].waitForExistence(timeout: 3))

        app.buttons["Отмена"].firstMatch.click()
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Добавить источник"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Изменить источник"].exists)
    }

    func testSwitchingToOfflineMapDoesNotAskForNetworkConsent() {
        createInitialTree()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Карта и конфиденциальность"].waitForExistence(timeout: 3))
        let offline = app.buttons["Офлайн-карта"].firstMatch
        if offline.exists { offline.click() }
        XCTAssertFalse(app.alerts["Включить Apple Maps?"].exists)
    }

    /// Settings must say plainly what each map provider sends off the Mac. There is no
    /// consent alert - the previous version of this test asserted one that has never
    /// existed - so the standing privacy notice is the disclosure.
    func testMapProviderDisclosesWhatLeavesTheMac() {
        createInitialTree()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Карта и конфиденциальность"].waitForExistence(timeout: 5))
        let apple = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Apple Maps")
        ).firstMatch
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Онлайн-карта. Apple видит просматриваемый участок."].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testRecoveryWorkspaceOpens() {
        openRecoveryWorkspace()
        XCTAssertTrue(app.staticTexts["Восстановление"].waitForExistence(timeout: 5))
    }

    /// Restoring from the library, where the tree is not open: the card's own menu. The
    /// version list used to live in Recovery as well; it does not any more, and this test
    /// is what holds the library door open.
    func testRestoringGEDCOMRevisionFromTheLibraryCard() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let name = app.textFields["ИМЯ"].firstMatch
        name.click(); name.typeKey("a", modifierFlags: .command); name.typeText("Пётр")
        app.buttons["Сохранить"].click()
        XCTAssertTrue(app.staticTexts["Иванов Пётр"].waitForExistence(timeout: 5))
        app.buttons["К списку деревьев"].click()

        let cardMenu = app.menuButtons["library.treeActions"].firstMatch
        XCTAssertTrue(cardMenu.waitForExistence(timeout: 10), "The card actions menu is not reachable")
        cardMenu.click()
        let versions = app.menuItems["Предыдущие версии…"]
        XCTAssertTrue(versions.waitForExistence(timeout: 5), "The card menu offers no version history")
        versions.click()

        let restore = app.buttons["Вернуть эту версию"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 15), "No saved revision was offered")
        restore.click()
        let confirm = app.buttons["Вернуть версию"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "The restore was not confirmed first")
        confirm.click()

        // Assert the outcome rather than the status line, which the sheet renders in a
        // way the accessibility tree does not surface: the edit is undone on the canvas.
        Thread.sleep(forTimeInterval: 3)
        app.buttons["Закрыть предыдущие версии"].firstMatch.click()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "UI Test")).firstMatch.click()
        XCTAssertTrue(app.buttons["Иванов Иван"].waitForExistence(timeout: 15), "The restored version was not the one on the canvas")
        XCTAssertFalse(app.buttons["Иванов Пётр"].exists)
    }

    /// Recovery is the rescue tool now, not a second version list. Its three groups stay;
    /// the revisions group must not come back.
    func testRecoveryNoLongerListsVersions() {
        createInitialTree()
        app.buttons["К списку деревьев"].click()
        openRecoveryWorkspace()
        XCTAssertTrue(app.staticTexts["Восстановление"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Вернуть эту версию"].exists, "Recovery is listing versions again")
    }

    /// The same restore reached the way a reader actually finds it: the save clock in the
    /// workspace toolbar, without closing the tree. The confirmation is the gate — nothing
    /// is written until it is accepted.
    func testRestoringAVersionFromTheSaveClock() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let name = app.textFields["ИМЯ"].firstMatch
        name.click(); name.typeKey("a", modifierFlags: .command); name.typeText("Пётр")
        app.buttons["Сохранить"].click()
        XCTAssertTrue(app.staticTexts["Иванов Пётр"].waitForExistence(timeout: 5))

        let clock = app.buttons["workspace.savedStatus"].firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 10), "The save clock is not reachable")
        clock.click()
        XCTAssertTrue(app.staticTexts["Предыдущие версии"].waitForExistence(timeout: 5))

        let restore = app.buttons["Вернуть эту версию"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 15), "No saved version was offered")
        restore.click()
        let confirm = app.buttons["Вернуть версию"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "The restore was not confirmed first")
        confirm.click()

        XCTAssertTrue(app.buttons["Иванов Иван"].waitForExistence(timeout: 15), "The restored version was not the one on the canvas")
        XCTAssertFalse(app.buttons["Иванов Пётр"].exists)
    }

    /// Opening a GEDCOM must reach the verified preview rather than importing
    /// silently. Not reachable from this harness: Launch Services routes `.ged` to
    /// whichever application it has registered, never this unregistered test bundle,
    /// and the open panel runs in `com.apple.appkit.xpc.openAndSavePanelService`,
    /// which exposes no window to XCUITest. The preview itself is covered in the core
    /// suite by `previewReportsValidatorFindingsWithoutRefusingTheFile`.
    func testOpeningGEDCOMRoutesToVerifiedPreview() throws {
        throw XCTSkip("The open panel is out of process; see this test's note.")
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-open-\(UUID().uuidString).ged")
        defer { try? FileManager.default.removeItem(at: fixture) }
        try "0 HEAD\n1 _NAME Finder\n0 @I1@ INDI\n1 NAME Анна /Иванова/\n0 TRLR".write(
            to: fixture,
            atomically: true,
            encoding: .utf8
        )
        openImportPanel(for: fixture)
        XCTAssertTrue(app.staticTexts["Предпросмотр импорта"].waitForExistence(timeout: 20))
    }

    func testArchivedTreeAppearsInRecovery() {
        createInitialTree()
        app.buttons["К списку деревьев"].click()
        app.menuButtons["library.treeActions"].click()
        app.menuItems["Удалить…"].click()
        let archive = app.windows.buttons["Архивировать (оставить файлы)"].firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.click()
        // Archiving reveals the folder in Finder, which steals the focus.
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertTrue(app.buttons["Новое дерево"].waitForExistence(timeout: 10))
        openRecoveryWorkspace()
        let returnToLibrary = app.buttons["Вернуть в библиотеку"].firstMatch
        XCTAssertTrue(returnToLibrary.waitForExistence(timeout: 15), "The archived tree was not offered back")
    }

    func testTreeCardAndActionsAreSeparateAccessibleControls() {
        createInitialTree()
        app.buttons["К списку деревьев"].click()

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Test'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertEqual(card.elementType, .button)

        let actions = app.menuButtons["library.treeActions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
    }

    func testBlankRenameExplainsHowToRecover() {
        createInitialTree()
        app.buttons["К списку деревьев"].click()
        app.menuButtons["library.treeActions"].click()
        app.menuItems["Переименовать…"].click()

        let name = app.textFields["Название"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeKey(.delete, modifierFlags: [])
        app.buttons["Сохранить"].click()

        XCTAssertTrue(app.staticTexts["Введите название дерева."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Сохранить"].isEnabled)
    }

    func testVerifiedExportAndDeleteLeavesImportableBundle() throws {
        createInitialTree()
        app.buttons["К списку деревьев"].click()
        app.menuButtons["library.treeActions"].click()
        app.menuItems["Удалить…"].click()
        app.windows.buttons["Сохранить копию и удалить дерево…"].firstMatch.click()

        let exportFolder = storageURL.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        app.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = app.sheets.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 3))
        pathField.typeText(exportFolder.path)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        let deadline = Date().addingTimeInterval(8)
        var exportedGEDCOM: URL?
        repeat {
            exportedGEDCOM = FileManager.default.enumerator(at: exportFolder, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.pathExtension.lowercased() == "ged" }
            if exportedGEDCOM == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        } while exportedGEDCOM == nil && Date() < deadline
        XCTAssertNotNil(exportedGEDCOM)
        XCTAssertFalse(app.staticTexts["UI Test"].exists)
    }

    /// A note past the soft limit warns and keeps every character. The limit exists so a
    /// note cannot quietly become a performance problem, but it must never be the reason
    /// text goes missing — so this asserts the counter appeared AND nothing was cut.
    /// Pasted line separators are folded to newlines, which is the one permitted edit.
    func testOverlongNoteWarnsAndKeepsEveryCharacter() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let notes = app.textViews["person.notes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))

        // Typing 100k characters is not viable; the pasteboard is the realistic path a
        // note this size arrives by anyway. The U+2028 stands in for text copied out of
        // a PDF or a web page.
        let unit = "Запись в метрической книге\u{2028}"
        let pasted = String(String(repeating: unit, count: 100_100 / unit.count + 1).prefix(100_100))
        XCTAssertEqual(pasted.count, 100_100)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pasted, forType: .string)

        notes.click()
        notes.typeKey("v", modifierFlags: .command)

        XCTAssertTrue(
            app.staticTexts["person.notes.overflow"].waitForExistence(timeout: 10),
            "No overflow warning past the soft limit"
        )
        let value = notes.value as? String ?? ""
        XCTAssertEqual(value.count, pasted.count, "Pasted text was truncated")
        XCTAssertFalse(value.unicodeScalars.contains("\u{2028}"), "U+2028 survived into the field")
        XCTAssertEqual(value, pasted.replacingOccurrences(of: "\u{2028}", with: "\n"))
    }

    private func createInitialTree() {
        let newTree = app.buttons["Новое дерево"]
        if newTree.waitForExistence(timeout: 2) { newTree.click() }
        let title = app.textFields["Название дерева"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click(); title.typeText("UI Test")
        let name = app.textFields["ИМЯ"]
        name.click(); name.typeText("Иван")
        let surname = app.textFields["ФАМИЛИЯ"]
        surname.click(); surname.typeText("Иванов")
        app.buttons["Далее"].click()
        app.buttons["Создать дерево"].click()
        // The finished card is shown for confirmation before the canvas opens.
        let open = app.buttons["Открыть дерево"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        // A card is one accessibility element labelled with the person's name, so it
        // is a button — not a static text.
        let person = app.buttons["Иванов Иван"]
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.click()
        XCTAssertTrue(app.buttons["Редактировать"].firstMatch.waitForExistence(timeout: 3))
    }

    /// Imports a file the way a reader does: the library's Import GEDCOM button, then
    /// the open panel, addressed by path through Go to Folder.
    ///
    /// Not through Finder: Launch Services routes a `.ged` to whichever application it
    /// has registered for the type, which is never this unregistered test bundle, so
    /// the document event never arrives.
    private func openImportPanel(for file: URL) {
        app.buttons["Импорт GEDCOM"].firstMatch.click()
        let panel = app.windows["open"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "The open panel did not appear")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(.enter, modifierFlags: [])
        app.typeKey(.enter, modifierFlags: [])
    }

    private func openRecoveryWorkspace() {
        let maintenance = app.menuButtons["Действия с библиотекой"]
        XCTAssertTrue(maintenance.waitForExistence(timeout: 10))
        maintenance.click()
        let restore = app.menuItems["Восстановить из резервной копии…"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.click()
    }

}

final class SwarmEnglishUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storageURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-ui-en-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        app = XCUIApplication(url: swarmUITestHostURL)
        app.launchArguments = [
            "-appLanguage", "en",
            "-appLanguageChoiceCompleted", "YES",
            "--storage-folder", storageURL.path,
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: storageURL)
    }

    func testEnglishCoreJourneyAndWorkspaceParity() {
        app.buttons["New Tree"].click()
        let title = app.textFields["FAMILY NAME"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click(); title.typeText("Smith Archive")
        let given = app.textFields["GIVEN NAMES"]
        given.click(); given.typeText("John")
        let surname = app.textFields["SURNAME"]
        surname.click(); surname.typeText("Smith")
        app.buttons["Next"].click()
        app.buttons["Create tree"].click()

        // The finished card is shown for confirmation before the canvas opens.
        let open = app.buttons["Open this tree"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()

        // A card is one accessibility element, announced as name plus lifespan and
        // sex, so it is a button labelled with the name — not a static text.
        let person = app.buttons["John Smith"]
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.click()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))

        // The list workspaces live behind the toolbar's view-options menu. It is
        // addressed by identifier: macOS names this control after its SF Symbol.
        for workspace in ["People", "Timeline", "Places", "Review"] {
            let menu = app.menuButtons["workspace.viewOptions"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.click()
            let item = app.menuItems[workspace]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing English workspace: \(workspace)")
            item.click()
        }

        // The save clock opens the version history, in English too. Restoring itself is
        // covered by the Russian suite; what matters here is that the panel is reachable
        // and translated.
        let clock = app.buttons["workspace.savedStatus"].firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 10), "The save clock is not reachable")
        clock.click()
        XCTAssertTrue(app.staticTexts["Previous Versions"].waitForExistence(timeout: 5))
        app.buttons["Close previous versions"].firstMatch.click()

        app.typeKey("?", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Swarm Help"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Dates"].exists)
        app.buttons["Close"].click()

        // Settings offers both languages and both map providers, and marks the one
        // in force. Switching cannot be exercised here: this suite pins the language
        // with `-appLanguage en`, which lands in UserDefaults' argument domain and
        // outranks anything the button writes. That both languages render correctly
        // is what this suite and its Russian twin demonstrate between them.
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Maps and privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Language"].exists)
        for option in ["Русский", "English", "Apple Maps", "Offline Map"] {
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", option)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing settings option: \(option)")
        }
        XCTAssertTrue(app.buttons["English"].isSelected, "The language in force is not marked selected")
    }

    /// The first screen must state the choice in both languages and refuse to be
    /// walked past. It cannot also assert that choosing advances the app:
    /// `-appLanguageChoiceCompleted NO` lands in UserDefaults' argument domain, which
    /// outranks the application domain the button writes to, so the flag stays NO for
    /// the life of this launch. Advancing is covered by every other test here, each of
    /// which launches with the choice already made.
    func testPristineLaunchRequiresAccessibleBilingualChoice() {
        app.terminate()
        app.launchArguments = [
            "-appLanguageChoiceCompleted", "NO",
            "--storage-folder", storageURL.path,
        ]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Choose your language\nВыберите язык"]
                .waitForExistence(timeout: 10)
        )
        // Neither language is pre-chosen, and both are reachable.
        for language in ["Русский", "English"] {
            let button = app.buttons[language]
            XCTAssertTrue(button.exists, "Missing language button: \(language)")
            XCTAssertTrue(button.isHittable, "Unreachable language button: \(language)")
        }
        // ⌘N must not open the new-tree flow behind the chooser.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Choose your language\nВыберите язык"].exists)
        XCTAssertFalse(app.textFields["FAMILY NAME"].exists)
    }

}

/// The offline vector map, launched straight into that provider rather than switched
/// to through Settings.
///
/// Screenshots are written when `SWARM_UI_SHOTS` names a directory, so the same test
/// can capture a before and an after run for visual comparison.
final class SwarmOfflineMapUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storageURL: URL!

    private var exampleTree: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples/romanovy/romanovy.ged")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-ui-map-\(UUID().uuidString)", isDirectory: true)
        // Seeded on disk rather than imported: a tree folder is any directory holding a
        // .ged, and the open panel is out of process and exposes no window to XCUITest.
        let treeFolder = storageURL.appendingPathComponent("Романовы", isDirectory: true)
        try FileManager.default.createDirectory(at: treeFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: exampleTree,
            to: treeFolder.appendingPathComponent("romanovy.ged")
        )
        app = XCUIApplication(url: swarmUITestHostURL)
        app.launchArguments = [
            "-appLanguage", "ru",
            "-appLanguageChoiceCompleted", "YES",
            // Straight into the offline renderer: the provider is plain `@AppStorage`.
            "-mapProvider", "offlineVector",
            "--storage-folder", storageURL.path,
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Tests

    func testOfflineMapReportsItsScale() throws {
        try openOfflineMap()
        let reading = try XCTUnwrap(scaleReading(), "The offline map published no distance reading")
        XCTAssertTrue(reading.hasSuffix("км") || reading.hasSuffix("м"), reading)
    }

    /// Guards the zoom buttons against saturating again. `mapZoom` was clamped to
    /// 0.25-1.6 and read as a ratio by a renderer spanning a 50x range, so the button
    /// went dead after about five clicks with most of the range unreached.
    func testZoomStepperKeepsWorkingPastTheOldCeiling() throws {
        try openOfflineMap()
        let start = try XCTUnwrap(zoomPercentage(), "No zoom readout to compare against")
        let startDistance = scaleReading()

        var readings: [Int] = []
        for _ in 0 ..< 10 {
            clickZoomIn()
            if let reading = zoomPercentage() { readings.append(reading) }
        }
        let last = try XCTUnwrap(readings.last)
        XCTAssertGreaterThan(last, start, "Ten zoom-in clicks left the zoom where it began")

        // The later clicks have to still do something. The old clamp stopped at 160%,
        // which five clicks reached, and every click after that was inert.
        XCTAssertGreaterThan(
            Set(readings.suffix(5)).count, 1,
            "Zoom stopped responding partway through: \(readings)"
        )
        XCTAssertGreaterThan(last, 160, "Zoom never passed the old 160% ceiling")

        // The distance reading has to follow the camera, not just the percentage.
        XCTAssertNotEqual(scaleReading(), startDistance, "The scale bar did not follow the zoom")
    }

    func testDraggingPansTheMap() throws {
        try openOfflineMap()
        // Zoom in first. The fitted view of this tree spans more than the window, so the
        // camera sits on its clamp and a drag correctly has nowhere to go.
        for _ in 0 ..< 6 { clickZoomIn() }
        let before = try screenshot(named: "drag-before")

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
            .press(
                forDuration: 0.3,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.58))
            )
        let after = try screenshot(named: "drag-after")
        XCTAssertNotEqual(before, after, "The drag did not move the map")
    }

    /// Capture only — the comparison is done by eye against a run of the previous build.
    /// Off by default: it asserts nothing, and parsing the place index a fourth time in
    /// one run makes it the slowest and flakiest thing in the class.
    func testCaptureOfflineMapAtThreeZoomLevels() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SWARM_UI_SHOTS"] == nil,
            "Screenshot capture aid; set SWARM_UI_SHOTS to a writable folder to run it."
        )
        try openOfflineMap()
        _ = try screenshot(named: "01-fitted")
        for _ in 0 ..< 5 { clickZoomIn() }
        _ = try screenshot(named: "02-country")
        for _ in 0 ..< 6 { clickZoomIn() }
        _ = try screenshot(named: "03-close")
    }

    // MARK: - Helpers

    private func openOfflineMap() throws {
        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Романовы")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "The seeded tree never appeared")
        card.click()

        // Addressed by identifier, not label: every button in a toolbar `Group` reports
        // the first button's accessibility label, so this one announces itself as
        // "Древовидная схема" and both zoom buttons as "Уменьшить масштаб".
        let map = app.buttons["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 60), "The workspace never opened")
        map.click()
        // The gazetteer is read from an 80 MB bundled index on a background queue; the
        // map draws before it settles.
        XCTAssertTrue(
            app.staticTexts["Места семьи"].waitForExistence(timeout: 60),
            "The offline map never appeared"
        )
        waitForPlaceIndex()
    }

    /// The gazetteer is an 80 MB bundled index parsed on a background queue, and the map
    /// draws long before it settles - without labels until it does. The slow-load
    /// indicator only appears five seconds in, so its absence alone does not mean ready;
    /// this waits for a sustained quiet window instead.
    private func waitForPlaceIndex() {
        let loading = app.activityIndicators["map.loading"]
        let deadline = Date().addingTimeInterval(300)
        var quiet = 0
        while Date() < deadline {
            quiet = loading.exists ? 0 : quiet + 1
            if quiet >= 6 { return }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTFail("The place index never finished loading")
    }

    private func clickZoomIn() {
        let button = app.buttons["plus"].firstMatch
        guard button.exists, button.isHittable else { return }
        button.click()
        Thread.sleep(forTimeInterval: 0.4)
    }

    /// SwiftUI surfaces a `Text` inside an accessibility representation as the element's
    /// value, not its label.
    /// The toolbar readout, exposed as the element's value.
    private func zoomPercentage() -> Int? {
        let readout = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "Масштаб ")
        ).firstMatch
        guard readout.waitForExistence(timeout: 10),
              let value = readout.value as? String else { return nil }
        return Int(value.filter(\.isNumber))
    }

    private func scaleReading() -> String? {
        let reading = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "Масштаб: ")
        ).firstMatch
        guard reading.waitForExistence(timeout: 10) else { return nil }
        return reading.value as? String
    }

    /// The runner is sandboxed, so screenshots go to its own temporary directory unless
    /// `SWARM_UI_SHOTS` names somewhere it can reach. The path is printed either way.
    @discardableResult
    private func screenshot(named name: String) throws -> Data {
        Thread.sleep(forTimeInterval: 1)
        let data = app.screenshot().pngRepresentation
        let folder = ProcessInfo.processInfo.environment["SWARM_UI_SHOTS"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-map-shots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(name).png")
            try data.write(to: file)
            print("SHOT \(file.path)")
        } catch {
            print("SHOT FAILED \(folder.path): \(error)")
        }
        return data
    }
}
