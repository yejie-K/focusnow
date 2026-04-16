import XCTest
@testable import StateSwitchMenubar

final class RecordStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-switch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    @MainActor
    func testCreateRecordAndUndo() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        XCTAssertEqual(store.states.count, 6)

        store.armRecord()
        store.commit(state: store.states[0])
        store.armRecord()
        store.commit(state: store.states[1])

        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.records.last?.previousState, store.records.first?.currentState)
        XCTAssertEqual(store.currentStateLabel, store.states[1].label)
        XCTAssertEqual(store.currentStateDefinition?.code, store.states[1].code)
        XCTAssertNotNil(store.currentStateStartedAt)

        store.undoLastRecord()

        XCTAssertEqual(store.records.count, 1)
        XCTAssertNil(store.records.first?.previousState)
    }

    @MainActor
    func testAddStateAndExportFiles() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        store.draftStateName = "写方案"
        store.addState()

        XCTAssertTrue(store.states.contains(where: { $0.label == "写方案" }))

        store.armRecord()
        if let newState = store.states.last {
            store.commit(state: newState)
        }

        let urls = try XCTUnwrap(store.exportAll())
        XCTAssertEqual(urls.count, 2)
        let jsonURL = urls.first { $0.pathExtension == "json" }
        let xlsxURL = urls.first { $0.pathExtension == "xlsx" }

        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(jsonURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(xlsxURL).path))

        let xlsxData = try Data(contentsOf: try XCTUnwrap(xlsxURL))
        XCTAssertTrue(xlsxData.starts(with: [0x50, 0x4B]))
        XCTAssertEqual(store.todayRecords.count, 1)
    }

    @MainActor
    func testRenameStateUpdatesHistoryAndDeleteCustomState() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        store.draftStateName = "写方案"
        store.addState()
        let newState = try XCTUnwrap(store.states.last)

        store.armRecord()
        store.commit(state: newState)

        store.renameState(code: newState.code, to: "写 PRD")

        XCTAssertTrue(store.states.contains(where: { $0.code == newState.code && $0.label == "写 PRD" }))
        XCTAssertTrue(store.records.contains(where: { $0.stateCode == newState.code && $0.currentState == "写 PRD" }))

        store.deleteState(code: newState.code)

        XCTAssertFalse(store.states.contains(where: { $0.code == newState.code }))
    }


    @MainActor
    func testAppearanceSelectionPersists() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        store.setAppearanceStyle(.glass)
        store.setAppearancePalette(.ocean)
        store.setBeaconAnchor(x: 0.22, y: 0.78)

        let reloaded = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        XCTAssertEqual(reloaded.appearanceSelection.styleID, .classic)
        XCTAssertEqual(reloaded.appearanceSelection.paletteID, .ocean)
        XCTAssertEqual(reloaded.appearanceSelection.beaconAnchor, BeaconAnchor(x: 0.22, y: 0.78))
    }

    @MainActor
    func testReloadRebalancesDuplicateStateColors() throws {
        _ = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        let dataDirectoryURL = temporaryDirectoryURL.appendingPathComponent("data", isDirectory: true)
        let statesURL = dataDirectoryURL.appendingPathComponent("states.json")
        let duplicated = [
            StateDefinition(label: "A", code: "a", colorHex: "#8a6a4a", builtin: false),
            StateDefinition(label: "B", code: "b", colorHex: "#8a6a4a", builtin: false),
            StateDefinition(label: "C", code: "c", colorHex: "#596273", builtin: false),
            StateDefinition(label: "D", code: "d", colorHex: "#596273", builtin: false),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(duplicated).write(to: statesURL, options: .atomic)

        let reloaded = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        XCTAssertEqual(reloaded.states.count, 4)
        XCTAssertEqual(Set(reloaded.states.map(\.colorHex)).count, 4)
        XCTAssertEqual(reloaded.states.first?.colorHex, "#8a6a4a")
    }

    @MainActor
    func testAddStateUsesUnusedColorFirst() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        for code in store.states.map(\.code) {
            store.deleteState(code: code)
        }

        ["标签A", "标签B", "标签C"].forEach { label in
            store.draftStateName = label
            store.addState()
        }

        XCTAssertEqual(store.states.map(\.colorHex), ["#4f6fd6", "#4e8a61", "#b7792d"])
    }

    @MainActor
    func testExportTodayScopeOnlyExportsTodayRecords() throws {
        _ = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        let dataDirectoryURL = temporaryDirectoryURL.appendingPathComponent("data", isDirectory: true)
        let recordsURL = dataDirectoryURL.appendingPathComponent("records.json")
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = .current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        let seedRecords = [
            RecordEvent(
                id: "evt_yesterday",
                recordedAt: isoFormatter.string(from: yesterday),
                date: dateFormatter.string(from: yesterday),
                previousState: nil,
                previousStateCode: nil,
                currentState: "昨天",
                stateCode: "yesterday",
                source: "manual_click",
                createdAt: isoFormatter.string(from: yesterday)
            ),
            RecordEvent(
                id: "evt_today",
                recordedAt: isoFormatter.string(from: today),
                date: dateFormatter.string(from: today),
                previousState: "昨天",
                previousStateCode: "yesterday",
                currentState: "今天",
                stateCode: "today",
                source: "manual_click",
                createdAt: isoFormatter.string(from: today)
            )
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(seedRecords).write(to: recordsURL, options: .atomic)

        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)
        XCTAssertEqual(store.records(for: .today).count, 1)
        XCTAssertEqual(store.records(for: .all).count, 2)

        let exportURLs = try XCTUnwrap(store.exportAll(scope: .today))
        let jsonURL = try XCTUnwrap(exportURLs.first(where: { $0.pathExtension == "json" }))
        let exported = try JSONDecoder().decode([RecordEvent].self, from: Data(contentsOf: jsonURL))

        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported.first?.id, "evt_today")
        XCTAssertTrue(jsonURL.lastPathComponent.contains("records_today"))
    }

    @MainActor
    func testUndoRemovesLatestRecordOnly() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        store.armRecord()
        store.commit(state: store.states[0])
        let keptRecordID = try XCTUnwrap(store.records.first?.id)
        store.armRecord()
        store.commit(state: store.states[1])

        store.undoLastRecord()

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.id, keptRecordID)
    }

    @MainActor
    func testUndoDuringPendingRecordCancelsCurrentPendingOnly() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL)

        store.armRecord()
        store.commit(state: store.states[0])
        let keptRecordID = try XCTUnwrap(store.records.first?.id)

        store.armRecord()
        XCTAssertTrue(store.isArmed)

        store.undoLastRecord()

        XCTAssertFalse(store.isArmed)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.id, keptRecordID)
    }
}
