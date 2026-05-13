import Foundation
import Combine
import UserNotifications

@MainActor
final class RecordStore: ObservableObject {
    @Published private(set) var states: [StateDefinition] = []
    @Published private(set) var records: [RecordEvent] = [] {
        didSet {
            sortedRecordsCache = nil
        }
    }
    @Published private(set) var appearanceSelection = AppearanceSelection()
    @Published private(set) var automationSettings = AutomationSettings()
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingTimestamp: Date?
    @Published var draftStateName = ""
    @Published var activeAlert: AppAlert?
    @Published private(set) var currentFrontmostApplication: FrontmostApplicationSnapshot?
    @Published private(set) var knownApplications: [FrontmostApplicationSnapshot] = []
    @Published private(set) var autoSwitchCandidate: AutoSwitchCandidate?
    @Published private(set) var autoSwitchFeedbackEvent: AutoSwitchFeedbackEvent?

    let baseDirectoryURL: URL
    private let dataDirectoryURL: URL
    private let recordsURL: URL
    private let statesURL: URL
    private let appearanceURL: URL
    private let automationURL: URL
    private let exportService: ExportService
    private var reminderLoop: AnyCancellable?
    private var reminderRuntime = ReminderRuntime()
    private var lastManualRecordAt: Date?
    private var sortedRecordsCache: [RecordEvent]?

    init(
        baseDirectoryURL: URL = AppPaths.resolveBaseDirectory(),
        enableReminderLoop: Bool = true
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.dataDirectoryURL = baseDirectoryURL.appendingPathComponent("data", isDirectory: true)
        self.recordsURL = dataDirectoryURL.appendingPathComponent("records.json")
        self.statesURL = dataDirectoryURL.appendingPathComponent("states.json")
        self.appearanceURL = dataDirectoryURL.appendingPathComponent("appearance.json")
        self.automationURL = dataDirectoryURL.appendingPathComponent("automation.json")
        self.exportService = ExportService(
            exportsDirectoryURL: dataDirectoryURL.appendingPathComponent("exports", isDirectory: true)
        )

        do {
            try ensureInitialized()
            try reload()
        } catch {
            self.activeAlert = AppAlert(title: "加载失败", message: error.localizedDescription)
            self.states = Self.defaultStates
            self.records = []
            self.appearanceSelection = AppearanceSelection()
            self.automationSettings = Self.defaultAutomationSettings(for: Self.defaultStates)
        }

        if enableReminderLoop {
            startReminderLoop()
        }

        if Self.canUseUserNotifications {
            Task { @MainActor [weak self] in
                await self?.refreshNotificationAuthorizationStatus()
            }
        }
    }

    var isArmed: Bool {
        pendingTimestamp != nil
    }

    var currentStateCode: String? {
        sortedRecords.last?.stateCode
    }

    var currentStateLabel: String? {
        sortedRecords.last?.currentState
    }

    var currentStateDisplayLabel: String? {
        sortedRecords.last?.displayState
    }

    var currentStateDefinition: StateDefinition? {
        guard let currentStateCode else {
            return nil
        }
        return states.first { $0.code == currentStateCode }
    }

    var currentStateStartedAt: Date? {
        sortedRecords.last.flatMap { Self.date(from: $0.recordedAt) }
    }

    var todayRecords: [RecordEvent] {
        let today = Self.dateFormatter.string(from: Date())
        return sortedRecords.filter { $0.date == today }
    }

    var allRecords: [RecordEvent] {
        sortedRecords
    }

    var theme: AppTheme {
        ThemeCatalog.theme(styleID: .classic, paletteID: appearanceSelection.paletteID)
    }

    func setAppearanceStyle(_ styleID: AppearanceStyleID) {
        appearanceSelection.styleID = .classic
        persistAppearanceHandlingError(title: "保存风格失败")
    }

    func setAppearancePalette(_ paletteID: AppearancePaletteID) {
        appearanceSelection.paletteID = paletteID
        persistAppearanceHandlingError(title: "保存颜色失败")
    }

    func setBeaconAnchor(x: Double, y: Double) {
        let nextAnchor = BeaconAnchor(x: x, y: y)
        guard appearanceSelection.beaconAnchor != nextAnchor else {
            return
        }
        appearanceSelection.beaconAnchor = nextAnchor
        persistAppearanceHandlingError(title: "保存位置失败")
    }

    func setReminderEnabled(_ enabled: Bool) {
        guard automationSettings.reminder.isEnabled != enabled else {
            return
        }

        automationSettings.reminder.isEnabled = enabled
        persistAutomationHandlingError(title: "保存提醒失败")

        guard enabled else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.warmupReminderAuthorization()
        }
    }

    func setReminderSnoozeMinutes(_ minutes: Int) {
        let normalized = Self.clampSnoozeMinutes(minutes)
        guard automationSettings.reminder.snoozeMinutes != normalized else {
            return
        }
        automationSettings.reminder.snoozeMinutes = normalized
        persistAutomationHandlingError(title: "保存提醒失败")
    }

    func reminderRule(for stateCode: String) -> StateReminderRule {
        automationSettings.reminder.rules.first(where: { $0.stateCode == stateCode })
            ?? Self.defaultReminderRule(for: stateCode)
    }

    func setReminderRuleEnabled(for stateCode: String, enabled: Bool) {
        guard let index = automationSettings.reminder.rules.firstIndex(where: { $0.stateCode == stateCode }) else {
            return
        }
        guard automationSettings.reminder.rules[index].isEnabled != enabled else {
            return
        }
        automationSettings.reminder.rules[index].isEnabled = enabled
        persistAutomationHandlingError(title: "保存提醒失败")

        if enabled {
            Task { @MainActor [weak self] in
                await self?.warmupReminderAuthorization()
            }
        }
    }

    func setReminderThreshold(for stateCode: String, minutes: Int) {
        guard let index = automationSettings.reminder.rules.firstIndex(where: { $0.stateCode == stateCode }) else {
            return
        }
        let normalized = Self.clampReminderThreshold(minutes)
        guard automationSettings.reminder.rules[index].thresholdMinutes != normalized else {
            return
        }
        automationSettings.reminder.rules[index].thresholdMinutes = normalized
        persistAutomationHandlingError(title: "保存提醒失败")
    }

    func setAutoSwitchEnabled(_ enabled: Bool) {
        guard automationSettings.autoSwitch.isEnabled != enabled else {
            return
        }

        automationSettings.autoSwitch.isEnabled = enabled
        if !enabled {
            autoSwitchCandidate = nil
        }
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func setAutoSwitchSettleSeconds(_ seconds: Int) {
        let normalized = AutoSwitchSettings.clampSettleSeconds(seconds)
        guard automationSettings.autoSwitch.settleSeconds != normalized else {
            return
        }

        automationSettings.autoSwitch.settleSeconds = normalized
        autoSwitchCandidate = nil
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func setAutoSwitchCountdownStyle(_ style: AutoSwitchCountdownStyle) {
        guard automationSettings.autoSwitch.countdownStyle != style else {
            return
        }
        automationSettings.autoSwitch.countdownStyle = style
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func setAutoSwitchFeedbackBeaconPulse(_ enabled: Bool) {
        guard automationSettings.autoSwitch.feedback.beaconPulse != enabled else {
            return
        }
        automationSettings.autoSwitch.feedback.beaconPulse = enabled
        persistAutomationHandlingError(title: "保存自动反馈失败")
    }

    func setAutoSwitchFeedbackBeaconBubble(_ enabled: Bool) {
        guard automationSettings.autoSwitch.feedback.beaconBubble != enabled else {
            return
        }
        automationSettings.autoSwitch.feedback.beaconBubble = enabled
        persistAutomationHandlingError(title: "保存自动反馈失败")
    }

    func setAutoSwitchFeedbackTimelineHighlight(_ enabled: Bool) {
        guard automationSettings.autoSwitch.feedback.timelineHighlight != enabled else {
            return
        }
        automationSettings.autoSwitch.feedback.timelineHighlight = enabled
        persistAutomationHandlingError(title: "保存自动反馈失败")
    }

    func setAutoSwitchFeedbackSystemNotification(_ enabled: Bool) {
        guard automationSettings.autoSwitch.feedback.systemNotification != enabled else {
            return
        }
        automationSettings.autoSwitch.feedback.systemNotification = enabled
        persistAutomationHandlingError(title: "保存自动反馈失败")

        guard enabled else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.warmupAutoSwitchNotificationAuthorization()
        }
    }

    func autoSwitchRule(for stateCode: String) -> StateAppRule {
        automationSettings.autoSwitch.rules.first(where: { $0.stateCode == stateCode })
            ?? StateAppRule(stateCode: stateCode, isEnabled: false, appIdentifiers: [])
    }

    func autoSwitchBindingText(for stateCode: String) -> String {
        autoSwitchRule(for: stateCode).appIdentifiers.joined(separator: "、")
    }

    func setAutoSwitchRuleEnabled(for stateCode: String, enabled: Bool) {
        guard let index = automationSettings.autoSwitch.rules.firstIndex(where: { $0.stateCode == stateCode }) else {
            return
        }
        guard automationSettings.autoSwitch.rules[index].isEnabled != enabled else {
            return
        }

        automationSettings.autoSwitch.rules[index].isEnabled = enabled
        autoSwitchCandidate = nil
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func setAutoSwitchAppBindingText(for stateCode: String, text: String) {
        guard let index = automationSettings.autoSwitch.rules.firstIndex(where: { $0.stateCode == stateCode }) else {
            return
        }

        let identifiers = Self.appIdentifiers(from: text)
        guard automationSettings.autoSwitch.rules[index].appIdentifiers != identifiers else {
            return
        }

        automationSettings.autoSwitch.rules[index].appIdentifiers = identifiers
        var displayNames = StateAppRule.normalizedDisplayNames(
            automationSettings.autoSwitch.rules[index].appDisplayNames,
            allowedIdentifiers: identifiers
        )
        for identifier in identifiers where displayNames[identifier] == nil {
            if let displayName = cachedDisplayName(for: identifier) {
                displayNames[identifier] = displayName
            }
        }
        automationSettings.autoSwitch.rules[index].appDisplayNames = displayNames
        autoSwitchCandidate = nil
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func bindAutoSwitchAppIdentifier(_ identifier: String, to stateCode: String) {
        let normalized = StateAppRule.normalizedIdentifiers([identifier])
        guard let appIdentifier = normalized.first,
              states.contains(where: { $0.code == stateCode }),
              let targetIndex = automationSettings.autoSwitch.rules.firstIndex(where: { $0.stateCode == stateCode }) else {
            return
        }
        let displayName = cachedDisplayName(for: appIdentifier)

        for index in automationSettings.autoSwitch.rules.indices {
            automationSettings.autoSwitch.rules[index].appIdentifiers.removeAll {
                $0.caseInsensitiveCompare(appIdentifier) == .orderedSame
            }
            removeCachedAutoSwitchDisplayName(for: appIdentifier, fromRuleAt: index)
        }

        if !automationSettings.autoSwitch.rules[targetIndex].appIdentifiers.contains(where: { $0.caseInsensitiveCompare(appIdentifier) == .orderedSame }) {
            automationSettings.autoSwitch.rules[targetIndex].appIdentifiers.append(appIdentifier)
        }
        if let displayName {
            automationSettings.autoSwitch.rules[targetIndex].appDisplayNames[appIdentifier] = displayName
        }
        automationSettings.autoSwitch.rules[targetIndex].isEnabled = true
        autoSwitchCandidate = nil
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func unbindAutoSwitchAppIdentifier(_ identifier: String, from stateCode: String) {
        guard let index = automationSettings.autoSwitch.rules.firstIndex(where: { $0.stateCode == stateCode }) else {
            return
        }

        let original = automationSettings.autoSwitch.rules[index].appIdentifiers
        automationSettings.autoSwitch.rules[index].appIdentifiers.removeAll {
            $0.caseInsensitiveCompare(identifier) == .orderedSame
        }
        removeCachedAutoSwitchDisplayName(for: identifier, fromRuleAt: index)

        guard automationSettings.autoSwitch.rules[index].appIdentifiers != original else {
            return
        }

        autoSwitchCandidate = nil
        persistAutomationHandlingError(title: "保存自动切换失败")
    }

    func boundAutoSwitchAppIdentifiers(for stateCode: String) -> [String] {
        autoSwitchRule(for: stateCode).appIdentifiers
    }

    func autoSwitchDisplayName(for identifier: String) -> String {
        cachedDisplayName(for: identifier) ?? identifier
    }

    private func removeCachedAutoSwitchDisplayName(for identifier: String, fromRuleAt index: Int) {
        let normalizedIdentifier = Self.normalizedAppIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            return
        }

        let matchingKeys = automationSettings.autoSwitch.rules[index].appDisplayNames.keys.filter {
            Self.normalizedAppIdentifier($0) == normalizedIdentifier
        }

        for key in matchingKeys {
            automationSettings.autoSwitch.rules[index].appDisplayNames.removeValue(forKey: key)
        }
    }

    func autoSwitchBoundState(for app: FrontmostApplicationSnapshot) -> StateDefinition? {
        for rule in automationSettings.autoSwitch.rules where rule.isEnabled {
            guard rule.appIdentifiers.contains(where: { Self.appIdentifier($0, matches: app) }) else {
                continue
            }
            return states.first { $0.code == rule.stateCode }
        }
        return nil
    }

    func armRecord() {
        let now = Date()
        let latestRecordedAt = sortedRecords.last.flatMap { Self.date(from: $0.recordedAt) }
        let floor = [pendingTimestamp, latestRecordedAt].compactMap { $0 }.max() ?? .distantPast
        let minimumNextTimestamp = floor.addingTimeInterval(0.001)
        pendingTimestamp = now > minimumNextTimestamp ? now : minimumNextTimestamp
    }

    func cancelPendingRecord() {
        pendingTimestamp = nil
    }

    func commit(state: StateDefinition) {
        do {
            guard let timestamp = pendingTimestamp else {
                throw StoreError.noPendingRecord
            }

            try recordTransition(to: state, timestamp: timestamp, source: "manual_click")
            pendingTimestamp = nil
            autoSwitchCandidate = nil
        } catch {
            activeAlert = AppAlert(title: "保存失败", message: error.localizedDescription)
        }
    }

    func addState() {
        do {
            let trimmed = draftStateName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.emptyStateLabel
            }
            guard !states.contains(where: { $0.label == trimmed }) else {
                throw StoreError.duplicatedState
            }

            let state = StateDefinition(
                label: trimmed,
                code: Self.stateCode(for: trimmed, existingCodes: Set(states.map(\.code))),
                colorHex: Self.nextColorHex(for: states),
                builtin: false
            )
            states.append(state)
            automationSettings = synchronizedAutomationSettings(automationSettings, with: states)
            try persistStates()
            try persistAutomation()
            draftStateName = ""
        } catch {
            activeAlert = AppAlert(title: "新增标签失败", message: error.localizedDescription)
        }
    }

    func renameState(code: String, to label: String) {
        do {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.emptyStateLabel
            }

            guard let index = states.firstIndex(where: { $0.code == code }) else {
                throw StoreError.stateNotFound
            }

            guard !states.contains(where: { $0.label == trimmed && $0.code != code }) else {
                throw StoreError.duplicatedState
            }

            let original = states[index]
            states[index] = StateDefinition(
                label: trimmed,
                code: original.code,
                colorHex: original.colorHex,
                builtin: original.builtin
            )

            records = rebuildPreviousLinks(
                records.map { record in
                    var mutable = record
                    if mutable.stateCode == code {
                        mutable.currentState = trimmed
                    }
                    return mutable
                }
            )

            try persistStates()
            try persistRecords()
        } catch {
            activeAlert = AppAlert(title: "修改标签失败", message: error.localizedDescription)
        }
    }

    func deleteState(code: String) {
        do {
            guard states.contains(where: { $0.code == code }) else {
                throw StoreError.stateNotFound
            }

            states.removeAll { $0.code == code }
            automationSettings = synchronizedAutomationSettings(automationSettings, with: states)
            try persistStates()
            try persistAutomation()
        } catch {
            activeAlert = AppAlert(title: "删除标签失败", message: error.localizedDescription)
        }
    }

    func undoLastRecord() {
        do {
            if pendingTimestamp != nil {
                pendingTimestamp = nil
                return
            }

            guard let latest = sortedRecords.last else {
                throw StoreError.noRecordToUndo
            }

            records.removeAll { $0.id == latest.id }
            records = rebuildPreviousLinks(records)
            try persistRecords()
        } catch {
            activeAlert = AppAlert(title: "撤销失败", message: error.localizedDescription)
        }
    }

    func records(for scope: RecordRangeScope) -> [RecordEvent] {
        switch scope {
        case .today:
            return todayRecords
        case .all:
            return allRecords
        }
    }

    func exportJSON(scope: RecordRangeScope = .all) -> URL? {
        do {
            let ordered = records(for: scope).reversed()
            return try exportService.exportJSON(
                records: Array(ordered),
                baseName: "records_\(scope.exportName)"
            )
        } catch {
            activeAlert = AppAlert(title: "导出失败", message: error.localizedDescription)
            return nil
        }
    }

    func exportExcel(scope: RecordRangeScope = .all) -> URL? {
        do {
            let ordered = records(for: scope).reversed()
            return try exportService.exportExcel(
                records: Array(ordered),
                baseName: "records_\(scope.exportName)"
            )
        } catch {
            activeAlert = AppAlert(title: "导出失败", message: error.localizedDescription)
            return nil
        }
    }

    func exportAll(scope: RecordRangeScope = .all) -> [URL]? {
        do {
            let ordered = Array(records(for: scope).reversed())
            let baseName = "records_\(scope.exportName)"
            let jsonURL = try exportService.exportJSON(records: ordered, baseName: baseName)
            let excelURL = try exportService.exportExcel(records: ordered, baseName: baseName)
            return [jsonURL, excelURL]
        } catch {
            activeAlert = AppAlert(title: "导出失败", message: error.localizedDescription)
            return nil
        }
    }

    func observeFrontmostApplication(
        localizedName: String,
        bundleIdentifier: String?,
        bundleURLPath: String? = nil,
        now: Date = Date()
    ) {
        let snapshot = FrontmostApplicationSnapshot(
            localizedName: localizedName,
            bundleIdentifier: bundleIdentifier,
            bundleURLPath: bundleURLPath
        )
        currentFrontmostApplication = snapshot
        upsertKnownApplication(snapshot)

        guard automationSettings.autoSwitch.isEnabled else {
            autoSwitchCandidate = nil
            return
        }

        guard let match = matchedAutoSwitchRule(for: snapshot) else {
            autoSwitchCandidate = nil
            return
        }

        guard !currentRecordMatches(
            stateCode: match.state.code,
            appName: snapshot.localizedName,
            appBundleIdentifier: snapshot.bundleIdentifier
        ) else {
            autoSwitchCandidate = nil
            return
        }

        guard !isInsideManualCooldown(now: now) else {
            autoSwitchCandidate = nil
            return
        }

        let reason = Self.autoSwitchReason(
            appName: snapshot.localizedName,
            bundleIdentifier: snapshot.bundleIdentifier,
            stateLabel: match.state.label,
            token: match.token
        )

        if let candidate = autoSwitchCandidate,
           candidate.stateCode == match.state.code,
           candidate.appName == snapshot.localizedName,
           candidate.bundleIdentifier == snapshot.bundleIdentifier {
            return
        }

        autoSwitchCandidate = AutoSwitchCandidate(
            appName: snapshot.localizedName,
            bundleIdentifier: snapshot.bundleIdentifier,
            stateCode: match.state.code,
            stateLabel: match.state.label,
            firstSeenAt: now,
            reason: reason
        )
    }

    func observeRunningApplications(_ apps: [FrontmostApplicationSnapshot]) {
        apps.forEach(upsertKnownApplication)
    }

    private func cachedDisplayName(for identifier: String) -> String? {
        let normalizedIdentifier = Self.normalizedAppIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            return nil
        }

        if let app = knownApplications.first(where: {
            Self.normalizedAppIdentifier($0.stableIdentifier) == normalizedIdentifier
                || Self.normalizedAppIdentifier($0.localizedName) == normalizedIdentifier
        }) {
            return app.localizedName
        }

        for rule in automationSettings.autoSwitch.rules {
            if let match = rule.appDisplayNames.first(where: {
                Self.normalizedAppIdentifier($0.key) == normalizedIdentifier
            }) {
                return match.value
            }
        }

        return nil
    }

    @discardableResult
    func evaluateAutoSwitch(now: Date = Date()) -> AutoSwitchResult? {
        guard automationSettings.autoSwitch.isEnabled,
              let candidate = autoSwitchCandidate else {
            return nil
        }

        guard !isInsideManualCooldown(now: now),
              !currentRecordMatches(
                stateCode: candidate.stateCode,
                appName: candidate.appName,
                appBundleIdentifier: candidate.bundleIdentifier
              ),
              now.timeIntervalSince(candidate.firstSeenAt) >= TimeInterval(automationSettings.autoSwitch.settleSeconds),
              let state = states.first(where: { $0.code == candidate.stateCode }) else {
            return nil
        }

        do {
            let event = try recordTransition(
                to: state,
                timestamp: now,
                source: "auto_app_rule",
                sourceDetail: candidate.reason,
                appName: candidate.appName,
                appBundleIdentifier: candidate.bundleIdentifier
            )
            autoSwitchCandidate = nil
            let result = AutoSwitchResult(
                recordID: event.id,
                stateCode: state.code,
                stateLabel: state.label,
                appName: candidate.appName,
                appBundleIdentifier: candidate.bundleIdentifier,
                sourceDetail: candidate.reason
            )
            publishAutoSwitchFeedback(from: result, occurredAt: now)
            return result
        } catch {
            autoSwitchCandidate = nil
            activeAlert = AppAlert(title: "自动切换失败", message: error.localizedDescription)
            return nil
        }
    }

    func evaluateReminderIfNeeded(now: Date = Date()) -> ReminderTrigger? {
        guard automationSettings.reminder.isEnabled else {
            reminderRuntime.reset(for: nil)
            return nil
        }

        guard let context = currentReminderContext() else {
            reminderRuntime.reset(for: nil)
            return nil
        }

        synchronizeReminderRuntime(for: context.segmentKey)

        let rule = reminderRule(for: context.state.code)
        guard rule.isEnabled else {
            return nil
        }

        let duration = now.timeIntervalSince(context.startedAt)
        guard duration >= TimeInterval(rule.thresholdMinutes * 60) else {
            return nil
        }

        if let snoozedUntil = reminderRuntime.snoozedUntil, now < snoozedUntil {
            return nil
        }

        if reminderRuntime.lastTriggeredAt != nil && reminderRuntime.snoozedUntil == nil {
            return nil
        }

        reminderRuntime.lastTriggeredAt = now
        reminderRuntime.snoozedUntil = nil

        return ReminderTrigger(
            segmentKey: context.segmentKey,
            stateCode: context.state.code,
            stateLabel: context.state.label,
            thresholdMinutes: rule.thresholdMinutes,
            duration: duration
        )
    }

    func snoozeReminder(segmentKey: String, now: Date = Date()) {
        guard let currentSegmentKey = synchronizeReminderRuntimeWithCurrentState(),
              currentSegmentKey == segmentKey else {
            return
        }

        reminderRuntime.lastTriggeredAt = now
        reminderRuntime.snoozedUntil = now.addingTimeInterval(TimeInterval(automationSettings.reminder.snoozeMinutes * 60))
    }

    func switchToRestFromReminder(segmentKey: String, now: Date = Date()) {
        guard let currentSegmentKey = synchronizeReminderRuntimeWithCurrentState(),
              currentSegmentKey == segmentKey else {
            return
        }

        guard let restState = states.first(where: { $0.code == Self.restStateCode })
            ?? states.first(where: { $0.label == "休息恢复" }) else {
            activeAlert = AppAlert(title: "提醒失败", message: "未找到休息恢复标签。")
            return
        }

        do {
            try recordTransition(to: restState, timestamp: now, source: "reminder_action")
            reminderRuntime.reset(for: nil)
        } catch {
            activeAlert = AppAlert(title: "提醒失败", message: error.localizedDescription)
        }
    }

    private func matchedAutoSwitchRule(
        for snapshot: FrontmostApplicationSnapshot
    ) -> (state: StateDefinition, token: String)? {
        for rule in automationSettings.autoSwitch.rules where rule.isEnabled {
            guard let state = states.first(where: { $0.code == rule.stateCode }) else {
                continue
            }

            if let token = rule.appIdentifiers.first(where: { Self.appIdentifier($0, matches: snapshot) }) {
                return (state, token)
            }
        }

        return nil
    }

    private func isInsideManualCooldown(now: Date) -> Bool {
        guard let lastManualRecordAt else {
            return false
        }

        return now.timeIntervalSince(lastManualRecordAt) < TimeInterval(automationSettings.autoSwitch.manualCooldownSeconds)
    }

    private func currentRecordMatches(
        stateCode: String,
        appName: String,
        appBundleIdentifier: String?
    ) -> Bool {
        guard let current = sortedRecords.last,
              current.stateCode == stateCode else {
            return false
        }

        if let currentBundleID = current.appBundleIdentifier,
           let appBundleIdentifier {
            return currentBundleID.caseInsensitiveCompare(appBundleIdentifier) == .orderedSame
        }

        return current.appName?.caseInsensitiveCompare(appName) == .orderedSame
    }

    private func upsertKnownApplication(_ app: FrontmostApplicationSnapshot) {
        let normalizedID = Self.normalizedAppIdentifier(app.stableIdentifier)
        guard !normalizedID.isEmpty else {
            return
        }

        knownApplications.removeAll {
            Self.normalizedAppIdentifier($0.stableIdentifier) == normalizedID
                || Self.normalizedAppIdentifier($0.localizedName) == normalizedID
        }
        knownApplications.insert(app, at: 0)

        let sorted = knownApplications
            .prefix(60)
            .sorted { left, right in
                left.localizedName.localizedCaseInsensitiveCompare(right.localizedName) == .orderedAscending
            }
        knownApplications = Array(sorted)

        if refreshAutoSwitchDisplayNameCache(for: app) {
            persistAutomationHandlingError(title: "保存自动切换失败")
        }
    }

    private func refreshAutoSwitchDisplayNameCache(for app: FrontmostApplicationSnapshot) -> Bool {
        var didChange = false

        for index in automationSettings.autoSwitch.rules.indices {
            let identifiers = automationSettings.autoSwitch.rules[index].appIdentifiers
            guard let identifier = identifiers.first(where: { Self.appIdentifier($0, matches: app) }) else {
                continue
            }

            guard automationSettings.autoSwitch.rules[index].appDisplayNames[identifier] != app.localizedName else {
                continue
            }

            automationSettings.autoSwitch.rules[index].appDisplayNames[identifier] = app.localizedName
            didChange = true
        }

        return didChange
    }

    private var sortedRecords: [RecordEvent] {
        if let sortedRecordsCache {
            return sortedRecordsCache
        }

        let sorted = records.sorted {
            let left = Self.date(from: $0.recordedAt) ?? .distantPast
            let right = Self.date(from: $1.recordedAt) ?? .distantPast
            if left != right {
                return left < right
            }
            return $0.id < $1.id
        }
        sortedRecordsCache = sorted
        return sorted
    }

    private func startReminderLoop() {
        reminderLoop = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self,
                      let trigger = self.evaluateReminderIfNeeded(now: now) else {
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.deliverReminder(trigger)
                }
            }
    }

    private func deliverReminder(_ trigger: ReminderTrigger) async {
        guard automationSettings.reminder.isEnabled,
              let currentContext = currentReminderContext(),
              currentContext.segmentKey == trigger.segmentKey else {
            return
        }

        let authorized = await ensureReminderAuthorization()
        guard authorized else {
            disableReminderBecauseNotificationsUnavailable()
            return
        }

        let content = UNMutableNotificationContent()
        let restLabel = states.first(where: { $0.code == Self.restStateCode })?.label ?? "休息恢复"
        content.title = "\(trigger.stateLabel) 已持续 \(trigger.thresholdMinutes) 分钟"
        content.body = "喝点水，或者切到\(restLabel)。"
        content.sound = .default
        content.categoryIdentifier = ReminderNotificationDescriptor.categoryID
        content.userInfo = [
            ReminderNotificationDescriptor.segmentKeyUserInfoKey: trigger.segmentKey
        ]

        let request = UNNotificationRequest(
            identifier: "state-switch-reminder-\(trigger.segmentKey)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            activeAlert = AppAlert(title: "提醒失败", message: "系统通知发送失败。")
        }
    }

    private func warmupReminderAuthorization() async {
        guard Self.canUseUserNotifications else {
            notificationAuthorizationStatus = .notDetermined
            return
        }
        let authorized = await ensureReminderAuthorization()
        guard !authorized else {
            return
        }
        disableReminderBecauseNotificationsUnavailable()
    }

    private func ensureReminderAuthorization() async -> Bool {
        guard Self.canUseUserNotifications else {
            notificationAuthorizationStatus = .notDetermined
            return false
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refreshNotificationAuthorizationStatus()
            return granted
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        guard Self.canUseUserNotifications else {
            notificationAuthorizationStatus = .notDetermined
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }

    private func disableReminderBecauseNotificationsUnavailable() {
        guard automationSettings.reminder.isEnabled else {
            return
        }
        automationSettings.reminder.isEnabled = false
        persistAutomationHandlingError(title: "保存提醒失败")
        activeAlert = AppAlert(title: "提醒不可用", message: "通知权限未开启，请先到系统设置里允许通知。")
    }

    private func warmupAutoSwitchNotificationAuthorization() async {
        let authorized = await ensureReminderAuthorization()
        guard !authorized else {
            return
        }

        automationSettings.autoSwitch.feedback.systemNotification = false
        persistAutomationHandlingError(title: "保存自动反馈失败")
        activeAlert = AppAlert(title: "通知不可用", message: "通知权限未开启，已关闭 Auto 系统通知。")
    }

    private func currentReminderContext() -> (state: StateDefinition, startedAt: Date, segmentKey: String)? {
        guard let state = currentStateDefinition,
              let startedAt = currentStateStartedAt else {
            return nil
        }

        return (
            state,
            startedAt,
            Self.reminderSegmentKey(for: state.code, startedAt: startedAt)
        )
    }

    private func synchronizeReminderRuntime(for segmentKey: String?) {
        guard reminderRuntime.segmentKey != segmentKey else {
            return
        }
        reminderRuntime.reset(for: segmentKey)
    }

    private func synchronizeReminderRuntimeWithCurrentState() -> String? {
        let segmentKey = currentReminderContext()?.segmentKey
        synchronizeReminderRuntime(for: segmentKey)
        return segmentKey
    }

    @discardableResult
    private func recordTransition(
        to state: StateDefinition,
        timestamp: Date,
        source: String,
        sourceDetail: String? = nil,
        appName: String? = nil,
        appBundleIdentifier: String? = nil
    ) throws -> RecordEvent {
        guard states.contains(where: { $0.code == state.code }) else {
            throw StoreError.stateNotFound
        }

        let previous = sortedRecords.last
        let event = RecordEvent(
            id: Self.recordID(for: timestamp),
            recordedAt: Self.isoFormatter.string(from: timestamp),
            date: Self.dateFormatter.string(from: timestamp),
            previousState: previous?.currentState,
            previousStateCode: previous?.stateCode,
            currentState: state.label,
            stateCode: state.code,
            appName: appName,
            appBundleIdentifier: appBundleIdentifier,
            source: source,
            sourceDetail: sourceDetail,
            createdAt: Self.isoFormatter.string(from: Date())
        )

        records = rebuildPreviousLinks(records + [event])
        try persistRecords()

        if source == "manual_click" {
            lastManualRecordAt = timestamp
        }

        return event
    }

    private func publishAutoSwitchFeedback(from result: AutoSwitchResult, occurredAt: Date) {
        let event = AutoSwitchFeedbackEvent(
            recordID: result.recordID,
            stateCode: result.stateCode,
            stateLabel: result.stateLabel,
            appName: result.appName,
            appBundleIdentifier: result.appBundleIdentifier,
            sourceDetail: result.sourceDetail,
            occurredAt: occurredAt
        )
        autoSwitchFeedbackEvent = event

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.autoSwitchFeedbackEvent?.id == event.id else {
                    return
                }
                self.autoSwitchFeedbackEvent = nil
            }
        }
    }

    private func ensureInitialized() throws {
        do {
            try FileManager.default.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(
                at: exportService.exportsDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw StoreError.writeFailed(dataDirectoryURL)
        }

        if !FileManager.default.fileExists(atPath: recordsURL.path) {
            try writeJSON([RecordEvent](), to: recordsURL)
        }

        if !FileManager.default.fileExists(atPath: statesURL.path) {
            try writeJSON(Self.defaultStates, to: statesURL)
        }

        if !FileManager.default.fileExists(atPath: appearanceURL.path) {
            try writeJSON(AppearanceSelection(), to: appearanceURL)
        }

        if !FileManager.default.fileExists(atPath: automationURL.path) {
            try writeJSON(Self.defaultAutomationSettings(for: Self.defaultStates), to: automationURL)
        }
    }

    private func reload() throws {
        let loadedStates = try readJSON([StateDefinition].self, from: statesURL, fallback: Self.defaultStates)
        let synchronizedStates = Self.normalizeStateColors(in: loadedStates)
        states = synchronizedStates

        let loadedRecords = try readJSON([RecordEvent].self, from: recordsURL, fallback: [])
        let synchronizedRecords = synchronizeRecordLabels(in: loadedRecords, with: states)
        records = rebuildPreviousLinks(synchronizedRecords)

        appearanceSelection = try readJSON(AppearanceSelection.self, from: appearanceURL, fallback: AppearanceSelection())
        if appearanceSelection.styleID != .classic {
            appearanceSelection.styleID = .classic
            try persistAppearance()
        }

        let loadedAutomation = try readJSON(
            AutomationSettings.self,
            from: automationURL,
            fallback: Self.defaultAutomationSettings(for: states)
        )
        let synchronizedAutomation = synchronizedAutomationSettings(loadedAutomation, with: states)
        automationSettings = synchronizedAutomation

        if synchronizedStates != loadedStates {
            try persistStates()
        }
        if synchronizedRecords != loadedRecords {
            try persistRecords()
        }
        if synchronizedAutomation != loadedAutomation {
            try persistAutomation()
        }
    }

    private func persistStates() throws {
        try writeJSON(states, to: statesURL)
    }

    private func persistRecords() throws {
        try writeJSON(records, to: recordsURL)
    }

    private func persistAppearance() throws {
        try writeJSON(appearanceSelection, to: appearanceURL)
    }

    private func persistAutomation() throws {
        try writeJSON(automationSettings, to: automationURL)
    }

    private func persistAppearanceHandlingError(title: String) {
        do {
            try persistAppearance()
        } catch {
            activeAlert = AppAlert(title: title, message: error.localizedDescription)
        }
    }

    private func persistAutomationHandlingError(title: String) {
        do {
            try persistAutomation()
        } catch {
            activeAlert = AppAlert(title: title, message: error.localizedDescription)
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(type, from: data)
        } catch let error as DecodingError {
            _ = error
            throw StoreError.invalidJSON(url)
        } catch {
            throw StoreError.readFailed(url)
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try Self.encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.writeFailed(url)
        }
    }

    private func rebuildPreviousLinks(_ input: [RecordEvent]) -> [RecordEvent] {
        let ordered = input.sorted {
            let left = Self.date(from: $0.recordedAt) ?? .distantPast
            let right = Self.date(from: $1.recordedAt) ?? .distantPast
            if left != right {
                return left < right
            }
            return $0.id < $1.id
        }

        var previous: RecordEvent?
        return ordered.map { record in
            var mutable = record
            mutable.previousState = previous?.currentState
            mutable.previousStateCode = previous?.stateCode
            previous = mutable
            return mutable
        }
    }

    private func synchronizeRecordLabels(in input: [RecordEvent], with states: [StateDefinition]) -> [RecordEvent] {
        let labelsByCode = Dictionary(uniqueKeysWithValues: states.map { ($0.code, $0.label) })
        return input.map { record in
            var mutable = record
            if let label = labelsByCode[record.stateCode] {
                mutable.currentState = label
            }
            return mutable
        }
    }

    private func synchronizedAutomationSettings(_ input: AutomationSettings, with states: [StateDefinition]) -> AutomationSettings {
        var output = input
        output.reminder.snoozeMinutes = Self.clampSnoozeMinutes(output.reminder.snoozeMinutes)

        let existingRules = Dictionary(uniqueKeysWithValues: output.reminder.rules.map { ($0.stateCode, $0) })
        output.reminder.rules = states.map { state in
            if let existing = existingRules[state.code] {
                return StateReminderRule(
                    stateCode: existing.stateCode,
                    isEnabled: existing.isEnabled,
                    thresholdMinutes: existing.thresholdMinutes
                )
            }
            return Self.defaultReminderRule(for: state.code)
        }

        output.autoSwitch.settleSeconds = AutoSwitchSettings.clampSettleSeconds(output.autoSwitch.settleSeconds)
        output.autoSwitch.manualCooldownSeconds = AutoSwitchSettings.clampManualCooldownSeconds(output.autoSwitch.manualCooldownSeconds)

        let existingAutoRules = Dictionary(uniqueKeysWithValues: output.autoSwitch.rules.map { ($0.stateCode, $0) })
        output.autoSwitch.rules = states.map { state in
            if let existing = existingAutoRules[state.code] {
                return StateAppRule(
                    stateCode: existing.stateCode,
                    isEnabled: existing.isEnabled,
                    appIdentifiers: existing.appIdentifiers,
                    appDisplayNames: existing.appDisplayNames
                )
            }
            return StateAppRule(stateCode: state.code, isEnabled: false, appIdentifiers: [])
        }

        return output
    }

    private static func defaultAutomationSettings(for states: [StateDefinition]) -> AutomationSettings {
        AutomationSettings(
            reminder: ReminderSettings(
                isEnabled: false,
                snoozeMinutes: 10,
                rules: states.map { defaultReminderRule(for: $0.code) }
            ),
            autoSwitch: AutoSwitchSettings(
                isEnabled: false,
                settleSeconds: 60,
                manualCooldownSeconds: 180,
                rules: states.map { StateAppRule(stateCode: $0.code, isEnabled: false, appIdentifiers: []) }
            )
        )
    }

    private static func defaultReminderRule(for stateCode: String) -> StateReminderRule {
        switch stateCode {
        case "focus_work":
            return StateReminderRule(stateCode: stateCode, isEnabled: true, thresholdMinutes: 60)
        case "meeting":
            return StateReminderRule(stateCode: stateCode, isEnabled: true, thresholdMinutes: 50)
        case "study":
            return StateReminderRule(stateCode: stateCode, isEnabled: true, thresholdMinutes: 50)
        case "rest":
            return StateReminderRule(stateCode: stateCode, isEnabled: false, thresholdMinutes: 30)
        case "interrupt":
            return StateReminderRule(stateCode: stateCode, isEnabled: false, thresholdMinutes: 45)
        case "other":
            return StateReminderRule(stateCode: stateCode, isEnabled: false, thresholdMinutes: 60)
        default:
            return StateReminderRule(stateCode: stateCode, isEnabled: false, thresholdMinutes: 60)
        }
    }

    private static func normalizeStateColors(in input: [StateDefinition]) -> [StateDefinition] {
        var normalized: [StateDefinition] = []
        var reserved = Set<String>()

        for state in input {
            let canonical = canonicalPaletteColor(for: state.colorHex)
            let assignedColor: String

            if let canonical, !reserved.contains(canonical.lowercased()) {
                assignedColor = canonical
            } else {
                assignedColor = nextColorHex(for: normalized)
            }

            normalized.append(
                StateDefinition(
                    label: state.label,
                    code: state.code,
                    colorHex: assignedColor,
                    builtin: state.builtin
                )
            )
            reserved.insert(assignedColor.lowercased())
        }

        return normalized
    }

    private static func nextColorHex(for states: [StateDefinition]) -> String {
        let usage = Dictionary(
            states.map { (canonicalPaletteColor(for: $0.colorHex) ?? $0.colorHex.lowercased(), 1) },
            uniquingKeysWith: +
        )

        return palette.min { left, right in
            let leftUsage = usage[left.lowercased()] ?? 0
            let rightUsage = usage[right.lowercased()] ?? 0
            if leftUsage != rightUsage {
                return leftUsage < rightUsage
            }

            let leftIndex = palette.firstIndex(of: left) ?? 0
            let rightIndex = palette.firstIndex(of: right) ?? 0
            return leftIndex < rightIndex
        } ?? palette[0]
    }

    private static func canonicalPaletteColor(for hex: String) -> String? {
        palette.first { $0.caseInsensitiveCompare(hex) == .orderedSame }
    }

    private static func clampReminderThreshold(_ minutes: Int) -> Int {
        min(max(minutes, 10), 240)
    }

    private static func clampSnoozeMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 5), 60)
    }

    private static func appIdentifiers(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，、;\n")
        return StateAppRule.normalizedIdentifiers(
            text.components(separatedBy: separators)
        )
    }

    private static func appIdentifier(_ identifier: String, matches snapshot: FrontmostApplicationSnapshot) -> Bool {
        let needle = normalizedAppIdentifier(identifier)
        guard !needle.isEmpty else {
            return false
        }

        let appName = normalizedAppIdentifier(snapshot.localizedName)
        let bundleID = normalizedAppIdentifier(snapshot.bundleIdentifier ?? "")

        return appName == needle
            || bundleID == needle
            || appName.contains(needle)
            || bundleID.contains(needle)
    }

    private static func normalizedAppIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func autoSwitchReason(
        appName: String,
        bundleIdentifier: String?,
        stateLabel: String,
        token: String
    ) -> String {
        let bundlePart = bundleIdentifier.map { " / \($0)" } ?? ""
        return "前台 App：\(appName)\(bundlePart)，命中规则：\(token) -> \(stateLabel)"
    }

    private static func reminderSegmentKey(for stateCode: String, startedAt: Date) -> String {
        "\(stateCode)|\(isoFormatter.string(from: startedAt))"
    }

    private static let palette = [
        "#4f6fd6",
        "#4e8a61",
        "#b7792d",
        "#b8574b",
        "#6c7f99",
        "#3d7f8c",
        "#8a6a4a",
        "#596273",
    ]

    private static let defaultStates = [
        StateDefinition(label: "深度工作", code: "focus_work", colorHex: "#4f6fd6", builtin: false),
        StateDefinition(label: "沟通协作", code: "meeting", colorHex: "#b7792d", builtin: false),
        StateDefinition(label: "学习输入", code: "study", colorHex: "#4e8a61", builtin: false),
        StateDefinition(label: "休息恢复", code: "rest", colorHex: "#6c7f99", builtin: false),
        StateDefinition(label: "临时中断", code: "interrupt", colorHex: "#b8574b", builtin: false),
        StateDefinition(label: "其他事项", code: "other", colorHex: "#596273", builtin: false),
    ]

    private static let restStateCode = "rest"

    private static let canUseUserNotifications = Bundle.main.bundleURL.pathExtension == "app"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    private static let fallbackISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static func date(from string: String) -> Date? {
        isoFormatter.date(from: string) ?? fallbackISOFormatter.date(from: string)
    }

    private static func recordID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        formatter.timeZone = .current
        let prefix = formatter.string(from: date)
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)
        return "evt_\(prefix)_\(suffix)"
    }

    private static func stateCode(for label: String, existingCodes: Set<String>) -> String {
        let lowered = label.lowercased()
        let slug = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "_",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        var candidate = slug.isEmpty ? "state_\(UUID().uuidString.prefix(8))" : "\(slug)_\(UUID().uuidString.prefix(4))"
        candidate = candidate.replacingOccurrences(of: "-", with: "").lowercased()

        while existingCodes.contains(candidate) {
            candidate = "state_\(UUID().uuidString.prefix(8))".replacingOccurrences(of: "-", with: "").lowercased()
        }
        return candidate
    }
}

private struct ReminderRuntime {
    var segmentKey: String?
    var lastTriggeredAt: Date?
    var snoozedUntil: Date?

    mutating func reset(for segmentKey: String?) {
        self.segmentKey = segmentKey
        self.lastTriggeredAt = nil
        self.snoozedUntil = nil
    }
}

enum AppPaths {
    static func resolveBaseDirectory() -> URL {
        let fileManager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ]

        for candidate in candidates {
            if let found = searchUp(from: candidate) {
                return found
            }
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    private static func searchUp(from startingURL: URL) -> URL? {
        var current = startingURL.standardizedFileURL

        while true {
            let dataPath = current.appendingPathComponent("data").path
            let packagePath = current.appendingPathComponent("Package.swift").path
            if FileManager.default.fileExists(atPath: dataPath) || FileManager.default.fileExists(atPath: packagePath) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }
}
