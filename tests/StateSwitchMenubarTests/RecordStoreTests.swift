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


    @MainActor
    func testReminderSettingsPersist() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        store.setReminderSnoozeMinutes(15)
        store.setReminderThreshold(for: "focus_work", minutes: 75)

        let reloaded = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        XCTAssertEqual(reloaded.automationSettings.reminder.snoozeMinutes, 15)
        XCTAssertEqual(reloaded.reminderRule(for: "focus_work").thresholdMinutes, 75)
    }

    @MainActor
    func testAutoSwitchFeedbackSettingsPersist() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        XCTAssertTrue(store.automationSettings.autoSwitch.feedback.beaconPulse)
        XCTAssertTrue(store.automationSettings.autoSwitch.feedback.beaconBubble)
        XCTAssertTrue(store.automationSettings.autoSwitch.feedback.timelineHighlight)
        XCTAssertTrue(store.automationSettings.autoSwitch.feedback.systemNotification)
        XCTAssertEqual(store.automationSettings.autoSwitch.countdownStyle, .bar)

        store.setAutoSwitchFeedbackBeaconPulse(false)
        store.setAutoSwitchFeedbackBeaconBubble(false)
        store.setAutoSwitchFeedbackTimelineHighlight(false)
        store.setAutoSwitchFeedbackSystemNotification(false)
        store.setAutoSwitchCountdownStyle(.ring)

        let reloaded = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        XCTAssertFalse(reloaded.automationSettings.autoSwitch.feedback.beaconPulse)
        XCTAssertFalse(reloaded.automationSettings.autoSwitch.feedback.beaconBubble)
        XCTAssertFalse(reloaded.automationSettings.autoSwitch.feedback.timelineHighlight)
        XCTAssertFalse(reloaded.automationSettings.autoSwitch.feedback.systemNotification)
        XCTAssertEqual(reloaded.automationSettings.autoSwitch.countdownStyle, .ring)
    }

    @MainActor
    func testReminderFiresOnceAndRespectsSnooze() throws {
        let now = Date()
        let startedAt = now.addingTimeInterval(-4_200)
        try seedRecord(stateCode: "focus_work", currentState: "深度工作", recordedAt: startedAt)
        try seedAutomationSettings(
            AutomationSettings(
                reminder: ReminderSettings(
                    isEnabled: true,
                    snoozeMinutes: 10,
                    rules: [
                        StateReminderRule(stateCode: "focus_work", isEnabled: true, thresholdMinutes: 60),
                        StateReminderRule(stateCode: "meeting", isEnabled: false, thresholdMinutes: 50),
                        StateReminderRule(stateCode: "study", isEnabled: false, thresholdMinutes: 50),
                        StateReminderRule(stateCode: "rest", isEnabled: false, thresholdMinutes: 30),
                        StateReminderRule(stateCode: "interrupt", isEnabled: false, thresholdMinutes: 45),
                        StateReminderRule(stateCode: "other", isEnabled: false, thresholdMinutes: 60),
                    ]
                )
            )
        )

        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        let first = try XCTUnwrap(store.evaluateReminderIfNeeded(now: now))
        XCTAssertEqual(first.stateCode, "focus_work")
        XCTAssertNil(store.evaluateReminderIfNeeded(now: now.addingTimeInterval(60)))

        store.snoozeReminder(segmentKey: first.segmentKey, now: now)

        XCTAssertNil(store.evaluateReminderIfNeeded(now: now.addingTimeInterval(5 * 60)))
        let second = try XCTUnwrap(store.evaluateReminderIfNeeded(now: now.addingTimeInterval(10 * 60)))
        XCTAssertEqual(second.segmentKey, first.segmentKey)
    }

    @MainActor
    func testReminderActionCanSwitchToRest() throws {
        let now = Date()
        let startedAt = now.addingTimeInterval(-4_200)
        try seedRecord(stateCode: "focus_work", currentState: "深度工作", recordedAt: startedAt)
        try seedAutomationSettings(
            AutomationSettings(
                reminder: ReminderSettings(
                    isEnabled: true,
                    snoozeMinutes: 10,
                    rules: [
                        StateReminderRule(stateCode: "focus_work", isEnabled: true, thresholdMinutes: 60),
                        StateReminderRule(stateCode: "meeting", isEnabled: false, thresholdMinutes: 50),
                        StateReminderRule(stateCode: "study", isEnabled: false, thresholdMinutes: 50),
                        StateReminderRule(stateCode: "rest", isEnabled: false, thresholdMinutes: 30),
                        StateReminderRule(stateCode: "interrupt", isEnabled: false, thresholdMinutes: 45),
                        StateReminderRule(stateCode: "other", isEnabled: false, thresholdMinutes: 60),
                    ]
                )
            )
        )

        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)
        let trigger = try XCTUnwrap(store.evaluateReminderIfNeeded(now: now))

        store.switchToRestFromReminder(segmentKey: trigger.segmentKey, now: now)

        XCTAssertEqual(store.currentStateCode, "rest")
        XCTAssertEqual(store.records.last?.source, "reminder_action")
        XCTAssertEqual(store.records.last?.previousStateCode, "focus_work")
    }

    @MainActor
    func testAutoSwitchRecordsAfterAppRuleSettles() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)
        let now = Date()

        store.setAutoSwitchEnabled(true)
        store.setAutoSwitchSettleSeconds(10)
        store.setAutoSwitchAppBindingText(for: "focus_work", text: "Codex、com.openai.codex")
        store.setAutoSwitchRuleEnabled(for: "focus_work", enabled: true)

        store.observeFrontmostApplication(
            localizedName: "Codex",
            bundleIdentifier: "com.openai.codex",
            now: now
        )

        XCTAssertEqual(store.autoSwitchCandidate?.stateCode, "focus_work")
        XCTAssertNil(store.evaluateAutoSwitch(now: now.addingTimeInterval(9)))

        let result = try XCTUnwrap(store.evaluateAutoSwitch(now: now.addingTimeInterval(10)))

        XCTAssertEqual(result.stateCode, "focus_work")
        XCTAssertEqual(result.recordID, store.records.last?.id)
        XCTAssertEqual(result.appName, "Codex")
        XCTAssertEqual(store.currentStateCode, "focus_work")
        XCTAssertEqual(store.records.last?.source, "auto_app_rule")
        XCTAssertEqual(store.records.last?.appName, "Codex")
        XCTAssertEqual(store.records.last?.appBundleIdentifier, "com.openai.codex")
        XCTAssertEqual(store.records.last?.displayState, "深度工作 - Codex")
        XCTAssertTrue(store.records.last?.sourceDetail?.contains("Codex") == true)
        XCTAssertEqual(store.autoSwitchFeedbackEvent?.recordID, store.records.last?.id)
        XCTAssertEqual(store.autoSwitchFeedbackEvent?.displayLabel, "深度工作 - Codex")
    }

    @MainActor
    func testAutoSwitchRecordsDifferentAppUnderSameState() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)
        let now = Date()

        store.setAutoSwitchEnabled(true)
        store.setAutoSwitchSettleSeconds(10)
        store.setAutoSwitchAppBindingText(for: "meeting", text: "飞书、微信")
        store.setAutoSwitchRuleEnabled(for: "meeting", enabled: true)

        store.observeFrontmostApplication(
            localizedName: "飞书",
            bundleIdentifier: "com.bytedance.macos.feishu",
            now: now
        )
        _ = store.evaluateAutoSwitch(now: now.addingTimeInterval(10))

        store.observeFrontmostApplication(
            localizedName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            now: now.addingTimeInterval(20)
        )
        _ = store.evaluateAutoSwitch(now: now.addingTimeInterval(30))

        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.records.map(\.displayState), ["沟通协作 - 飞书", "沟通协作 - 微信"])
        XCTAssertEqual(store.records.last?.previousStateCode, "meeting")
    }

    @MainActor
    func testManualRecordCooldownBlocksAutoSwitch() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        store.setAutoSwitchEnabled(true)
        store.setAutoSwitchSettleSeconds(10)
        store.setAutoSwitchAppBindingText(for: "focus_work", text: "Codex")
        store.setAutoSwitchRuleEnabled(for: "focus_work", enabled: true)

        store.armRecord()
        store.commit(state: store.states.first { $0.code == "rest" } ?? store.states[0])

        let now = Date()
        store.observeFrontmostApplication(
            localizedName: "Codex",
            bundleIdentifier: "com.openai.codex",
            now: now
        )

        XCTAssertNil(store.autoSwitchCandidate)
        XCTAssertNil(store.evaluateAutoSwitch(now: now.addingTimeInterval(20)))
        XCTAssertEqual(store.currentStateCode, "rest")
    }

    @MainActor
    func testAutoSwitchVisualBindingMovesAppBetweenStates() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        store.bindAutoSwitchAppIdentifier("com.openai.codex", to: "focus_work")
        store.bindAutoSwitchAppIdentifier("com.openai.codex", to: "meeting")

        XCTAssertFalse(store.boundAutoSwitchAppIdentifiers(for: "focus_work").contains("com.openai.codex"))
        XCTAssertTrue(store.boundAutoSwitchAppIdentifiers(for: "meeting").contains("com.openai.codex"))
        XCTAssertTrue(store.autoSwitchRule(for: "meeting").isEnabled)

        store.unbindAutoSwitchAppIdentifier("com.openai.codex", from: "meeting")

        XCTAssertFalse(store.boundAutoSwitchAppIdentifiers(for: "meeting").contains("com.openai.codex"))
    }

    @MainActor
    func testAutoSwitchVisualBindingCachesDisplayName() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)
        let lark = FrontmostApplicationSnapshot(
            localizedName: "飞书",
            bundleIdentifier: "com.bytedance.ee.lark"
        )

        store.observeRunningApplications([lark])
        store.bindAutoSwitchAppIdentifier(lark.stableIdentifier, to: "meeting")

        XCTAssertEqual(store.autoSwitchDisplayName(for: "com.bytedance.ee.lark"), "飞书")

        let reloaded = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        XCTAssertEqual(reloaded.autoSwitchDisplayName(for: "com.bytedance.ee.lark"), "飞书")
    }

    @MainActor
    func testAutoSwitchTextBindingCachesKnownDisplayName() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)
        let lark = FrontmostApplicationSnapshot(
            localizedName: "飞书",
            bundleIdentifier: "com.bytedance.ee.lark"
        )

        store.observeRunningApplications([lark])
        store.setAutoSwitchAppBindingText(for: "meeting", text: "com.bytedance.ee.lark")

        XCTAssertEqual(store.autoSwitchRule(for: "meeting").appDisplayNames["com.bytedance.ee.lark"], "飞书")

        let reloaded = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        XCTAssertEqual(reloaded.autoSwitchDisplayName(for: "com.bytedance.ee.lark"), "飞书")
    }

    @MainActor
    func testAutoSwitchUnbindRemovesCachedDisplayNameCaseInsensitively() throws {
        let store = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)
        let lark = FrontmostApplicationSnapshot(
            localizedName: "飞书",
            bundleIdentifier: "com.bytedance.ee.lark"
        )

        store.observeRunningApplications([lark])
        store.bindAutoSwitchAppIdentifier(lark.stableIdentifier, to: "meeting")
        store.unbindAutoSwitchAppIdentifier("COM.BYTEDANCE.EE.LARK", from: "meeting")

        XCTAssertTrue(store.autoSwitchRule(for: "meeting").appIdentifiers.isEmpty)
        XCTAssertTrue(store.autoSwitchRule(for: "meeting").appDisplayNames.isEmpty)
    }

    @MainActor
    private func seedRecord(stateCode: String, currentState: String, recordedAt: Date) throws {
        _ = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        let dataDirectoryURL = temporaryDirectoryURL.appendingPathComponent("data", isDirectory: true)
        let recordsURL = dataDirectoryURL.appendingPathComponent("records.json")
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = .current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        let record = RecordEvent(
            id: "evt_seed",
            recordedAt: isoFormatter.string(from: recordedAt),
            date: dateFormatter.string(from: recordedAt),
            previousState: nil,
            previousStateCode: nil,
            currentState: currentState,
            stateCode: stateCode,
            source: "manual_click",
            createdAt: isoFormatter.string(from: recordedAt)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode([record]).write(to: recordsURL, options: .atomic)
    }

    @MainActor
    private func seedAutomationSettings(_ settings: AutomationSettings) throws {
        _ = RecordStore(baseDirectoryURL: temporaryDirectoryURL, enableReminderLoop: false)

        let dataDirectoryURL = temporaryDirectoryURL.appendingPathComponent("data", isDirectory: true)
        let automationURL = dataDirectoryURL.appendingPathComponent("automation.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: automationURL, options: .atomic)
    }

}
