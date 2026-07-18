import AppKit
import XCTest

final class FamilyTreeStudioUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storageURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "ru", "--storage-folder", storageURL.path]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: storageURL)
    }

    func testCreateEditAndCancelPersonLeavesSavedValue() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.click()
        let name = app.textFields["напр. Иван"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click(); name.typeKey("a", modifierFlags: .command); name.typeText("Несохранённое")
        app.buttons["Отмена"].firstMatch.click()
        XCTAssertFalse(app.staticTexts["Несохранённое"].exists)
    }

    func testUnionAndCitationCanBeEditedAndSaved() throws {
        try importTree("""
        0 HEAD
        1 _NAME Evidence UI
        0 @I1@ INDI
        1 NAME Иван /Иванов/
        1 SEX M
        1 FAMS @F1@
        0 @I2@ INDI
        1 NAME Анна /Иванова/
        1 SEX F
        1 FAMS @F1@
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 MARR
        2 DATE 2000
        0 TRLR
        """)
        app.staticTexts["Иванов Иван"].click()
        app.buttons["Редактировать"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Иванов Иван + Иванова Анна"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ИСТОЧНИКИ И ДОКАЗАТЕЛЬСТВА"].waitForExistence(timeout: 3))
        let sourceTitle = app.textFields["Название"]
        sourceTitle.click(); sourceTitle.typeText("Метрическая книга")
        app.buttons["Добавить в библиотеку"].click()
        app.buttons["Привязать ссылку"].click()
        app.buttons["Сохранить"].click()
        XCTAssertTrue(app.staticTexts["Иванов Иван"].waitForExistence(timeout: 5))
    }

    func testSwitchingToOfflineMapDoesNotAskForNetworkConsent() {
        createInitialTree()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Карта и конфиденциальность"].waitForExistence(timeout: 3))
        let offline = app.radioButtons["Офлайн-карта"]
        if offline.exists { offline.click() }
        XCTAssertFalse(app.alerts["Включить Apple Maps?"].exists)
    }

    func testAppleMapsRequiresDisclosure() {
        createInitialTree()
        app.typeKey(",", modifierFlags: .command)
        let apple = app.radioButtons["Apple Maps"]
        XCTAssertTrue(apple.waitForExistence(timeout: 3))
        apple.click()
        XCTAssertTrue(app.alerts["Включить Apple Maps?"].waitForExistence(timeout: 2))
        app.alerts.buttons["Остаться офлайн"].click()
    }

    func testRecoveryWorkspaceOpens() {
        app.buttons["Отмена"].firstMatch.click()
        XCTAssertTrue(app.buttons["Восстановление"].waitForExistence(timeout: 3))
        app.buttons["Восстановление"].click()
        XCTAssertTrue(app.staticTexts["Восстановление и миграция"].waitForExistence(timeout: 3))
    }

    func testRestoringGEDCOMRevisionCompletes() {
        createInitialTree()
        app.buttons["Редактировать"].firstMatch.click()
        let name = app.textFields["напр. Иван"].firstMatch
        name.click(); name.typeKey("a", modifierFlags: .command); name.typeText("Пётр")
        app.buttons["Сохранить"].click()
        XCTAssertTrue(app.staticTexts["Иванов Пётр"].waitForExistence(timeout: 5))
        app.buttons["Вернуться к списку деревьев"].click()
        app.buttons["Восстановление"].click()
        XCTAssertTrue(app.staticTexts["Версия GEDCOM"].waitForExistence(timeout: 3))
        app.buttons["Восстановить"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Восстановление проверено и сохранено."].waitForExistence(timeout: 5))
    }

    func testFinderOpenGEDCOMRoutesToVerifiedPreview() throws {
        app.buttons["Отмена"].firstMatch.click()
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-open-\(UUID().uuidString).ged")
        defer { try? FileManager.default.removeItem(at: fixture) }
        try "0 HEAD\n1 _NAME Finder\n0 @I1@ INDI\n1 NAME Анна /Иванова/\n0 TRLR".write(
            to: fixture,
            atomically: true,
            encoding: .utf8
        )
        NSWorkspace.shared.open(fixture)
        XCTAssertTrue(app.staticTexts["Предпросмотр импорта"].waitForExistence(timeout: 5))
    }

    func testArchivedTreeAppearsInRecovery() {
        createInitialTree()
        app.buttons["Вернуться к списку деревьев"].click()
        app.buttons["Действия с деревом"].click()
        app.menuItems["Удалить…"].click()
        XCTAssertTrue(app.buttons["Архивировать (оставить файлы)"].waitForExistence(timeout: 3))
        app.buttons["Архивировать (оставить файлы)"].click()
        app.activate()
        app.buttons["Восстановление"].click()
        XCTAssertTrue(app.staticTexts["Все архивы"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'UI Test'")).firstMatch.exists)
    }

    func testVerifiedExportAndDeleteLeavesImportableBundle() throws {
        createInitialTree()
        app.buttons["Вернуться к списку деревьев"].click()
        app.buttons["Действия с деревом"].click()
        app.menuItems["Удалить…"].click()
        app.buttons["Экспортировать копию и удалить…"].click()

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

    private func createInitialTree() {
        let title = app.textFields["напр. Семья Ивановых"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click(); title.typeText("UI Test")
        app.buttons["Далее"].click()
        let name = app.textFields["напр. Иван"]
        name.click(); name.typeText("Иван")
        let surname = app.textFields["напр. Иванов"]
        surname.click(); surname.typeText("Иванов")
        app.buttons["Создать"].click()
        let person = app.staticTexts["Иванов Иван"]
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.click()
        XCTAssertTrue(app.buttons["Редактировать"].firstMatch.waitForExistence(timeout: 3))
    }

    private func importTree(_ gedcom: String) throws {
        app.buttons["Отмена"].firstMatch.click()
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-import-\(UUID().uuidString).ged")
        defer { try? FileManager.default.removeItem(at: fixture) }
        try gedcom.write(to: fixture, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(fixture)
        XCTAssertTrue(app.staticTexts["Предпросмотр импорта"].waitForExistence(timeout: 5))
        app.buttons["Импортировать проверенную копию"].click()
        XCTAssertTrue(app.staticTexts["Evidence UI"].waitForExistence(timeout: 5))
    }
}
