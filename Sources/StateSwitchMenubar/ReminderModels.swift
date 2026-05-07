import Foundation

struct AutomationSettings: Codable, Equatable {
    var reminder: ReminderSettings = ReminderSettings()
    var autoSwitch: AutoSwitchSettings = AutoSwitchSettings()

    init(
        reminder: ReminderSettings = ReminderSettings(),
        autoSwitch: AutoSwitchSettings = AutoSwitchSettings()
    ) {
        self.reminder = reminder
        self.autoSwitch = autoSwitch
    }

    private enum CodingKeys: String, CodingKey {
        case reminder
        case autoSwitch = "auto_switch"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminder = try container.decodeIfPresent(ReminderSettings.self, forKey: .reminder) ?? ReminderSettings()
        autoSwitch = try container.decodeIfPresent(AutoSwitchSettings.self, forKey: .autoSwitch) ?? AutoSwitchSettings()
    }
}

struct ReminderSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var snoozeMinutes: Int = 10
    var rules: [StateReminderRule] = []

    init(
        isEnabled: Bool = false,
        snoozeMinutes: Int = 10,
        rules: [StateReminderRule] = []
    ) {
        self.isEnabled = isEnabled
        self.snoozeMinutes = Self.clampSnooze(snoozeMinutes)
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case snoozeMinutes
        case rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        snoozeMinutes = Self.clampSnooze(try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 10)
        rules = try container.decodeIfPresent([StateReminderRule].self, forKey: .rules) ?? []
    }

    private static func clampSnooze(_ minutes: Int) -> Int {
        min(max(minutes, 5), 60)
    }
}

struct StateReminderRule: Codable, Identifiable, Hashable {
    let stateCode: String
    var isEnabled: Bool
    var thresholdMinutes: Int

    var id: String { stateCode }

    init(stateCode: String, isEnabled: Bool, thresholdMinutes: Int) {
        self.stateCode = stateCode
        self.isEnabled = isEnabled
        self.thresholdMinutes = Self.clampThreshold(thresholdMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case stateCode = "state_code"
        case isEnabled = "is_enabled"
        case thresholdMinutes = "threshold_minutes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stateCode = try container.decode(String.self, forKey: .stateCode)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        thresholdMinutes = Self.clampThreshold(try container.decodeIfPresent(Int.self, forKey: .thresholdMinutes) ?? 60)
    }

    private static func clampThreshold(_ minutes: Int) -> Int {
        min(max(minutes, 10), 240)
    }
}

struct ReminderTrigger: Equatable {
    let segmentKey: String
    let stateCode: String
    let stateLabel: String
    let thresholdMinutes: Int
    let duration: TimeInterval
}

struct AutoSwitchSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var settleSeconds: Int = 60
    var manualCooldownSeconds: Int = 180
    var rules: [StateAppRule] = []

    init(
        isEnabled: Bool = false,
        settleSeconds: Int = 60,
        manualCooldownSeconds: Int = 180,
        rules: [StateAppRule] = []
    ) {
        self.isEnabled = isEnabled
        self.settleSeconds = Self.clampSettleSeconds(settleSeconds)
        self.manualCooldownSeconds = Self.clampManualCooldownSeconds(manualCooldownSeconds)
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case settleSeconds = "settle_seconds"
        case manualCooldownSeconds = "manual_cooldown_seconds"
        case rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        settleSeconds = Self.clampSettleSeconds(try container.decodeIfPresent(Int.self, forKey: .settleSeconds) ?? 60)
        manualCooldownSeconds = Self.clampManualCooldownSeconds(try container.decodeIfPresent(Int.self, forKey: .manualCooldownSeconds) ?? 180)
        rules = try container.decodeIfPresent([StateAppRule].self, forKey: .rules) ?? []
    }

    static func clampSettleSeconds(_ seconds: Int) -> Int {
        min(max(seconds, 10), 600)
    }

    static func clampManualCooldownSeconds(_ seconds: Int) -> Int {
        min(max(seconds, 0), 1_800)
    }
}

struct StateAppRule: Codable, Identifiable, Hashable {
    let stateCode: String
    var isEnabled: Bool
    var appIdentifiers: [String]

    var id: String { stateCode }

    init(stateCode: String, isEnabled: Bool, appIdentifiers: [String]) {
        self.stateCode = stateCode
        self.isEnabled = isEnabled
        self.appIdentifiers = Self.normalizedIdentifiers(appIdentifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case stateCode = "state_code"
        case isEnabled = "is_enabled"
        case appIdentifiers = "app_identifiers"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stateCode = try container.decode(String.self, forKey: .stateCode)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        appIdentifiers = Self.normalizedIdentifiers(
            try container.decodeIfPresent([String].self, forKey: .appIdentifiers) ?? []
        )
    }

    static func normalizedIdentifiers(_ input: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for item in input {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            output.append(trimmed)
        }

        return output
    }
}

struct FrontmostApplicationSnapshot: Identifiable, Hashable {
    let localizedName: String
    let bundleIdentifier: String?
    let bundleURLPath: String?

    init(localizedName: String, bundleIdentifier: String?, bundleURLPath: String? = nil) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURLPath = bundleURLPath
    }

    var id: String { stableIdentifier }

    var stableIdentifier: String {
        bundleIdentifier ?? localizedName
    }
}

struct AutoSwitchCandidate: Identifiable, Equatable {
    let appName: String
    let bundleIdentifier: String?
    let stateCode: String
    let stateLabel: String
    let firstSeenAt: Date
    let reason: String

    var id: String {
        "\(stateCode)|\(bundleIdentifier ?? appName)|\(firstSeenAt.timeIntervalSince1970)"
    }
}

struct AutoSwitchResult: Equatable {
    let stateCode: String
    let stateLabel: String
    let appName: String
    let appBundleIdentifier: String?
    let sourceDetail: String
}

enum ReminderNotificationDescriptor {
    static let categoryID = "STATE_SWITCH_DURATION_REMINDER"
    static let snoozeActionID = "STATE_SWITCH_REMINDER_SNOOZE"
    static let restActionID = "STATE_SWITCH_REMINDER_REST"
    static let segmentKeyUserInfoKey = "segment_key"
}
