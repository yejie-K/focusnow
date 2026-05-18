import SwiftUI
import Foundation

struct DashboardView: View {
    let theme: AppTheme
    let states: [StateDefinition]
    let records: [RecordEvent]

    @State private var snapshot: DashboardSnapshot?

    var body: some View {
        Group {
            if let snapshot {
                dashboardContent(snapshot)
            } else {
                loadingCard
            }
        }
        .onAppear {
            refreshSnapshot()
        }
        .onChange(of: records) { _ in
            refreshSnapshot()
        }
        .onChange(of: states) { _ in
            refreshSnapshot()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            refreshSnapshot(now: date)
        }
    }

    private func dashboardContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            dashboardHeader(snapshot)
            metricGrid(snapshot)
            timelineSection(snapshot)
            distributionSection(snapshot)
            appRankingSection(snapshot)
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日看板")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(theme.ink)

            Text("正在整理今天的状态流")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground(cornerRadius: 18))
    }

    private func refreshSnapshot(now: Date = Date()) {
        snapshot = DashboardSnapshot.make(
            records: records,
            states: states,
            now: now
        )
    }

    private func dashboardHeader(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("今日看板")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(theme.ink)

                Spacer(minLength: 0)

                if snapshot.filteredGapDuration > 0 {
                    Text("已过滤 \(snapshot.filteredGapLabel)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.accentSoft.opacity(0.18))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(theme.border.opacity(0.82), lineWidth: 1)
                                )
                        )
                        .help("过滤长空窗，避免睡觉/离开电脑把上一状态延长到数小时。")
                }

                Text(snapshot.dayLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.surfaceAlt.opacity(0.88))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(theme.border.opacity(0.9), lineWidth: 1)
                            )
                    )
            }

            Text(snapshot.summaryLine)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.textMuted)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground(cornerRadius: 18))
    }

    private func metricGrid(_ snapshot: DashboardSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 122), spacing: 8)],
            spacing: 8
        ) {
            DashboardMetricCard(
                title: "完整度",
                value: snapshot.continuityScoreLabel,
                footnote: snapshot.continuityHint,
                theme: theme,
                tint: theme.accentPrimary
            )
            DashboardMetricCard(
                title: "切换",
                value: "\(snapshot.transitionCount)",
                footnote: "今日状态转换",
                theme: theme,
                tint: theme.accentSecondary
            )
            DashboardMetricCard(
                title: "平均段",
                value: snapshot.averageSegmentLabel,
                footnote: "平均状态持续",
                theme: theme,
                tint: theme.ink.opacity(0.82)
            )
            DashboardMetricCard(
                title: "最长段",
                value: snapshot.longestSegmentLabel,
                footnote: snapshot.longestSegmentName,
                theme: theme,
                tint: theme.accentPrimary.mixed(with: theme.accentSecondary, amount: 0.48)
            )
        }
    }

    private func timelineSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("时间河流", trailing: snapshot.coverageLabel)

            if snapshot.segments.isEmpty {
                emptyState("今天还没有状态记录")
            } else {
                DashboardTimelineBar(segments: snapshot.segments, totalDuration: snapshot.totalDuration, theme: theme)
                    .frame(height: 42)

                HStack(spacing: 8) {
                    Text(snapshot.timelineStartLabel)
                    Spacer(minLength: 0)
                    Text(snapshot.timelineEndLabel)
                }
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textDim)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 7)], spacing: 7) {
                    ForEach(snapshot.topStateShares.prefix(4)) { share in
                        DashboardLegendPill(share: share, theme: theme)
                    }
                }
            }
        }
        .padding(12)
        .background(cardBackground(cornerRadius: 18))
    }

    private func distributionSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("状态占比", trailing: snapshot.totalTrackedLabel)

            if snapshot.stateShares.isEmpty {
                emptyState("暂无可统计时长")
            } else {
                HStack(alignment: .center, spacing: 14) {
                    DashboardRingChart(shares: snapshot.stateShares, theme: theme)
                        .frame(width: 92, height: 92)

                    VStack(spacing: 7) {
                        ForEach(snapshot.topStateShares.prefix(5)) { share in
                            DashboardShareRow(share: share, theme: theme)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(cardBackground(cornerRadius: 18))
    }

    private func appRankingSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("App-标签排行", trailing: "Auto 归因")

            if snapshot.appShares.isEmpty {
                emptyState("暂无带 App 的自动记录")
            } else {
                VStack(spacing: 7) {
                    ForEach(snapshot.appShares.prefix(6)) { share in
                        DashboardAppRankRow(share: share, theme: theme)
                    }
                }
            }
        }
        .padding(12)
        .background(cardBackground(cornerRadius: 18))
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .heavy))
                .foregroundStyle(theme.ink)

            Spacer(minLength: 0)

            Text(trailing)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textDim)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(theme.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surfaceAlt.opacity(0.72))
            )
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.surface.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(theme.border.opacity(0.92), lineWidth: 1)
            )
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let footnote: String
    let theme: AppTheme
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(0.78))
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(footnote)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.textDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct DashboardTimelineBar: View {
    let segments: [DashboardSegment]
    let totalDuration: TimeInterval
    let theme: AppTheme

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: segment.colorHex))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.26), Color.white.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .frame(width: width(for: segment, totalWidth: proxy.size.width))
                        .help("\(segment.displayName) · \(DashboardFormat.duration(segment.duration))")
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(theme.surfaceAlt.opacity(0.76))
            )
        }
    }

    private func width(for segment: DashboardSegment, totalWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else {
            return 0
        }
        let available = max(0, totalWidth - CGFloat(max(segments.count - 1, 0) * 2) - 6)
        return max(3, available * CGFloat(segment.duration / totalDuration))
    }
}

private struct DashboardRingChart: View {
    let shares: [DashboardStateShare]
    let theme: AppTheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.surfaceAlt.opacity(0.82), lineWidth: 12)

            ForEach(ringSlices) { slice in
                Circle()
                    .trim(from: slice.start, to: slice.end)
                    .stroke(
                        Color(hex: slice.colorHex),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text("\(Int(round((shares.first?.percentage ?? 0) * 100)))%")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.ink)

                Text(shares.first?.label ?? "-")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
                    .frame(width: 62)
            }
        }
    }

    private var ringSlices: [DashboardRingSlice] {
        var cursor: Double = 0
        return shares.map { share in
            let start = cursor
            cursor += max(0.008, share.percentage)
            return DashboardRingSlice(
                id: share.id,
                colorHex: share.colorHex,
                start: start,
                end: min(cursor, 1)
            )
        }
    }
}

private struct DashboardShareRow: View {
    let share: DashboardStateShare
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: share.colorHex))
                    .frame(width: 8, height: 8)

                Text(share.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(share.durationLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(theme.surfaceAlt.opacity(0.82))

                    Capsule(style: .continuous)
                        .fill(Color(hex: share.colorHex).opacity(0.82))
                        .frame(width: max(4, proxy.size.width * CGFloat(share.percentage)))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct DashboardLegendPill: View {
    let share: DashboardStateShare
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: share.colorHex))
                .frame(width: 7, height: 7)

            Text(share.label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("\(Int(round(share.percentage * 100)))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textDim)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surfaceAlt.opacity(0.82))
        )
    }
}

private struct DashboardAppRankRow: View {
    let share: DashboardAppShare
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 9) {
            Text("\(share.rank)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.textDim)
                .frame(width: 18)

            Circle()
                .fill(Color(hex: share.colorHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(share.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(share.stateLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(share.durationLabel)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(theme.surfaceAlt.opacity(0.74))
        )
    }
}

struct DashboardSnapshot {
    let segments: [DashboardSegment]
    let stateShares: [DashboardStateShare]
    let appShares: [DashboardAppShare]
    let transitionCount: Int
    let totalDuration: TimeInterval
    let filteredGapCount: Int
    let filteredGapDuration: TimeInterval
    let dayLabel: String
    let timelineStartLabel: String
    let timelineEndLabel: String

    private static let longGapThreshold: TimeInterval = 3 * 3600
    private static let currentOpenSegmentLimit: TimeInterval = 4 * 3600

    var topStateShares: [DashboardStateShare] {
        stateShares.sorted {
            if $0.duration != $1.duration {
                return $0.duration > $1.duration
            }
            return $0.label < $1.label
        }
    }

    var totalTrackedLabel: String {
        DashboardFormat.duration(totalDuration)
    }

    var filteredGapLabel: String {
        guard filteredGapCount > 0 else {
            return "0m"
        }
        return "\(filteredGapCount) 段 · \(DashboardFormat.duration(filteredGapDuration))"
    }

    var coverageLabel: String {
        segments.isEmpty ? "暂无流动" : "\(segments.count) 段"
    }

    var averageSegmentLabel: String {
        guard !segments.isEmpty else {
            return "-"
        }
        return DashboardFormat.duration(totalDuration / Double(segments.count))
    }

    var longestSegmentLabel: String {
        guard let longest = segments.max(by: { $0.duration < $1.duration }) else {
            return "-"
        }
        return DashboardFormat.duration(longest.duration)
    }

    var longestSegmentName: String {
        segments.max(by: { $0.duration < $1.duration })?.displayName ?? "暂无记录"
    }

    var continuityScoreLabel: String {
        guard !segments.isEmpty else {
            return "-"
        }
        return "\(continuityScore)"
    }

    var continuityHint: String {
        guard !segments.isEmpty else {
            return "暂无数据"
        }
        if continuityScore >= 78 {
            return "长段较多"
        }
        if continuityScore >= 54 {
            return "节奏正常"
        }
        return "切换偏碎"
    }

    var summaryLine: String {
        guard !segments.isEmpty else {
            return "今天还没有形成状态流。先记录几次，Board 会开始长出纹理。"
        }
        let top = topStateShares.first?.label ?? "当前状态"
        if filteredGapDuration > 0 {
            return "今天记录 \(transitionCount) 次切换，主要状态是 \(top)，已覆盖 \(totalTrackedLabel)，已过滤空窗 \(DashboardFormat.duration(filteredGapDuration))。"
        }
        return "今天记录 \(transitionCount) 次切换，主要状态是 \(top)，已覆盖 \(totalTrackedLabel)。"
    }

    private var continuityScore: Int {
        guard totalDuration > 0, !segments.isEmpty else {
            return 0
        }
        let avgMinutes = totalDuration / Double(segments.count) / 60
        let hours = max(totalDuration / 3600, 0.25)
        let switchesPerHour = Double(max(transitionCount - 1, 0)) / hours
        let raw = (min(avgMinutes, 60) / 60) * 62 + max(0, 38 - switchesPerHour * 8)
        return Int(min(max(raw, 0), 100).rounded())
    }

    static func make(records: [RecordEvent], states: [StateDefinition], now: Date) -> DashboardSnapshot {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayFormatter = DashboardFormat.dayFormatter
        let dayLabel = dayFormatter.string(from: now)
        let parsedRecords = records.compactMap { record -> ParsedDashboardRecord? in
            guard let date = DashboardFormat.date(from: record.recordedAt), date <= now else {
                return nil
            }
            return ParsedDashboardRecord(record: record, date: date)
        }
        .sorted { $0.date < $1.date }

        let stateByCode = Dictionary(uniqueKeysWithValues: states.map { ($0.code, $0) })
        let carryFromPreviousDay = parsedRecords.last { $0.date < dayStart }
        let events = parsedRecords.filter { $0.date >= dayStart }

        var segments: [DashboardSegment] = []
        var filteredGapCount = 0
        var filteredGapDuration: TimeInterval = 0
        if carryFromPreviousDay != nil {
            let crossDayEnd = min(events.first?.date ?? now, now)
            if crossDayEnd > dayStart {
                filteredGapCount += 1
                filteredGapDuration += crossDayEnd.timeIntervalSince(dayStart)
            }
        }

        for index in events.indices {
            let event = events[index]
            let nextDate = index + 1 < events.count ? events[index + 1].date : now
            let start = max(event.date, dayStart)
            let rawEnd = min(nextDate, now)
            let limit = segmentEndLimit(
                start: start,
                rawEnd: rawEnd,
                hasNextRecord: index + 1 < events.count,
                calendar: calendar
            )
            let end = min(rawEnd, limit)
            guard end > start else {
                if rawEnd > start {
                    filteredGapCount += 1
                    filteredGapDuration += rawEnd.timeIntervalSince(start)
                }
                continue
            }

            let state = stateByCode[event.record.stateCode]
            let label = state?.label ?? event.record.currentState
            let colorHex = state?.colorHex ?? "#4f6fd6"
            let duration = end.timeIntervalSince(start)
            segments.append(
                DashboardSegment(
                    id: "\(event.record.id)-\(index)",
                    stateCode: event.record.stateCode,
                    label: label,
                    colorHex: colorHex,
                    start: start,
                    end: end,
                    duration: duration,
                    appName: event.record.appName
                )
            )

            if rawEnd > end {
                filteredGapCount += 1
                filteredGapDuration += rawEnd.timeIntervalSince(end)
            }
        }

        let totalDuration = segments.reduce(0) { $0 + $1.duration }
        let todayTransitionCount = parsedRecords.filter { $0.date >= dayStart }.count
        let stateShares = makeStateShares(segments: segments, states: states, totalDuration: totalDuration)
        let appShares = makeAppShares(segments: segments)
        let startLabel = segments.first.map { DashboardFormat.time($0.start) } ?? "--:--"
        let endLabel = DashboardFormat.time(now)

        return DashboardSnapshot(
            segments: segments,
            stateShares: stateShares,
            appShares: appShares,
            transitionCount: todayTransitionCount,
            totalDuration: totalDuration,
            filteredGapCount: filteredGapCount,
            filteredGapDuration: filteredGapDuration,
            dayLabel: dayLabel,
            timelineStartLabel: startLabel,
            timelineEndLabel: endLabel
        )
    }

    private static func segmentEndLimit(
        start: Date,
        rawEnd: Date,
        hasNextRecord: Bool,
        calendar: Calendar
    ) -> Date {
        var limits: [Date] = []

        if let dayEnd = calendar.dateInterval(of: .day, for: start)?.end {
            limits.append(dayEnd)
        }

        if rawEnd.timeIntervalSince(start) > longGapThreshold {
            limits.append(start.addingTimeInterval(longGapThreshold))
        }

        if !hasNextRecord, rawEnd.timeIntervalSince(start) > currentOpenSegmentLimit {
            limits.append(start.addingTimeInterval(currentOpenSegmentLimit))
        }

        return limits.min() ?? rawEnd
    }

    private static func makeStateShares(
        segments: [DashboardSegment],
        states: [StateDefinition],
        totalDuration: TimeInterval
    ) -> [DashboardStateShare] {
        let stateByCode = Dictionary(uniqueKeysWithValues: states.map { ($0.code, $0) })
        var durations: [String: TimeInterval] = [:]

        for segment in segments {
            durations[segment.stateCode, default: 0] += segment.duration
        }

        return durations.map { code, duration in
            let state = stateByCode[code]
            let label = state?.label ?? segments.first(where: { $0.stateCode == code })?.label ?? code
            let colorHex = state?.colorHex ?? segments.first(where: { $0.stateCode == code })?.colorHex ?? "#4f6fd6"
            return DashboardStateShare(
                id: code,
                label: label,
                colorHex: colorHex,
                duration: duration,
                percentage: totalDuration > 0 ? duration / totalDuration : 0
            )
        }
        .sorted {
            if $0.duration != $1.duration {
                return $0.duration > $1.duration
            }
            return $0.label < $1.label
        }
    }

    private static func makeAppShares(segments: [DashboardSegment]) -> [DashboardAppShare] {
        var buckets: [String: (appName: String, stateLabel: String, colorHex: String, duration: TimeInterval)] = [:]

        for segment in segments {
            guard let appName = segment.appName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !appName.isEmpty else {
                continue
            }

            let key = "\(segment.stateCode)|\(appName.lowercased())"
            var bucket = buckets[key] ?? (appName, segment.label, segment.colorHex, 0)
            bucket.duration += segment.duration
            buckets[key] = bucket
        }

        return buckets.values
            .sorted {
                if $0.duration != $1.duration {
                    return $0.duration > $1.duration
                }
                return $0.appName < $1.appName
            }
            .enumerated()
            .map { index, bucket in
                DashboardAppShare(
                    id: "\(bucket.stateLabel)-\(bucket.appName)",
                    rank: index + 1,
                    appName: bucket.appName,
                    stateLabel: bucket.stateLabel,
                    colorHex: bucket.colorHex,
                    duration: bucket.duration
                )
            }
    }
}

struct ParsedDashboardRecord {
    let record: RecordEvent
    let date: Date
}

struct DashboardSegment: Identifiable {
    let id: String
    let stateCode: String
    let label: String
    let colorHex: String
    let start: Date
    let end: Date
    let duration: TimeInterval
    let appName: String?

    var displayName: String {
        guard let appName, !appName.isEmpty else {
            return label
        }
        return "\(label) - \(appName)"
    }
}

struct DashboardStateShare: Identifiable {
    let id: String
    let label: String
    let colorHex: String
    let duration: TimeInterval
    let percentage: Double

    var durationLabel: String {
        DashboardFormat.duration(duration)
    }
}

struct DashboardAppShare: Identifiable {
    let id: String
    let rank: Int
    let appName: String
    let stateLabel: String
    let colorHex: String
    let duration: TimeInterval

    var durationLabel: String {
        DashboardFormat.duration(duration)
    }
}

private struct DashboardRingSlice: Identifiable {
    let id: String
    let colorHex: String
    let start: Double
    let end: Double
}

private enum DashboardFormat {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd EEE"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    static func date(from string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = .current

        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        fallbackISOFormatter.timeZone = .current

        return isoFormatter.date(from: string) ?? fallbackISOFormatter.date(from: string)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }
}
