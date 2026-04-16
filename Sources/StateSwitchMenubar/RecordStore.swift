import Foundation
import Combine

@MainActor
final class RecordStore: ObservableObject {
    @Published private(set) var states: [StateDefinition] = []
    @Published private(set) var records: [RecordEvent] = []
    @Published private(set) var appearanceSelection = AppearanceSelection()
    @Published var pendingTimestamp: Date?
    @Published var draftStateName = ""
    @Published var activeAlert: AppAlert?
    @Published var beaconProximity: CGFloat = 0

    let baseDirectoryURL: URL
    private let dataDirectoryURL: URL
    private let recordsURL: URL
    private let statesURL: URL
    private let appearanceURL: URL
    private let exportService: ExportService

    init(baseDirectoryURL: URL = AppPaths.resolveBaseDirectory()) {
        self.baseDirectoryURL = baseDirectoryURL
        self.dataDirectoryURL = baseDirectoryURL.appendingPathComponent("data", isDirectory: true)
        self.recordsURL = dataDirectoryURL.appendingPathComponent("records.json")
        self.statesURL = dataDirectoryURL.appendingPathComponent("states.json")
        self.appearanceURL = dataDirectoryURL.appendingPathComponent("appearance.json")
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

    func armRecord() {
        let now = Date()
        let latestRecordedAt = sortedRecords.last.flatMap { Self.date(from: $0.recordedAt) }
        let floor = [pendingTimestamp, latestRecordedAt].compactMap { $0 }.max() ?? .distantPast
        pendingTimestamp = now > floor ? now : floor.addingTimeInterval(0.001)
    }

    func cancelPendingRecord() {
        pendingTimestamp = nil
    }

    func commit(state: StateDefinition) {
        do {
            guard let timestamp = pendingTimestamp else {
                throw StoreError.noPendingRecord
            }
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
                source: "manual_click",
                createdAt: Self.isoFormatter.string(from: Date())
            )

            records = rebuildPreviousLinks(records + [event])
            try persistRecords()
            pendingTimestamp = nil
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
            try persistStates()
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
            try persistStates()
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

    private var sortedRecords: [RecordEvent] {
        records.sorted {
            let left = Self.date(from: $0.recordedAt) ?? .distantPast
            let right = Self.date(from: $1.recordedAt) ?? .distantPast
            if left != right {
                return left < right
            }
            return $0.id < $1.id
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
        if synchronizedStates != loadedStates {
            try persistStates()
        }
        if synchronizedRecords != loadedRecords {
            try persistRecords()
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

    private func persistAppearanceHandlingError(title: String) {
        do {
            try persistAppearance()
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
