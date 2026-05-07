import Foundation

struct StateDefinition: Codable, Identifiable, Hashable {
    let label: String
    let code: String
    let colorHex: String
    let builtin: Bool

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case label
        case code
        case colorHex = "color"
        case builtin
    }
}

struct RecordEvent: Codable, Identifiable, Hashable {
    let id: String
    let recordedAt: String
    let date: String
    var previousState: String?
    var previousStateCode: String?
    var currentState: String
    let stateCode: String
    var appName: String? = nil
    var appBundleIdentifier: String? = nil
    let source: String
    var sourceDetail: String? = nil
    let createdAt: String

    var displayState: String {
        guard let appName, !appName.isEmpty else {
            return currentState
        }
        return "\(currentState) - \(appName)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recordedAt = "recorded_at"
        case date
        case previousState = "previous_state"
        case previousStateCode = "previous_state_code"
        case currentState = "current_state"
        case stateCode = "state_code"
        case appName = "app_name"
        case appBundleIdentifier = "app_bundle_id"
        case source
        case sourceDetail = "source_detail"
        case createdAt = "created_at"
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum RecordRangeScope: String, CaseIterable, Identifiable, Codable {
    case today
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "今天"
        case .all:
            return "全部"
        }
    }

    var exportName: String {
        switch self {
        case .today:
            return "today"
        case .all:
            return "all"
        }
    }
}

enum StoreError: LocalizedError {
    case emptyStateLabel
    case duplicatedState
    case stateNotFound
    case noPendingRecord
    case noRecordToUndo
    case invalidJSON(URL)
    case readFailed(URL)
    case writeFailed(URL)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyStateLabel:
            return "标签名称不能为空。"
        case .duplicatedState:
            return "该标签已存在。"
        case .stateNotFound:
            return "未找到对应状态标签。"
        case .noPendingRecord:
            return "请先点击记录。"
        case .noRecordToUndo:
            return "当前没有可撤销的记录。"
        case .invalidJSON(let url):
            return "JSON 文件损坏：\(url.lastPathComponent)"
        case .readFailed(let url):
            return "读取失败：\(url.lastPathComponent)"
        case .writeFailed(let url):
            return "写入失败：\(url.lastPathComponent)"
        case .exportFailed(let message):
            return message
        }
    }
}
