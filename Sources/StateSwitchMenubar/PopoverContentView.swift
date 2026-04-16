import SwiftUI
import AppKit

struct PopoverContentView: View {
    private enum InteractionStage {
        case idle
        case armingBurst(PromptBurstPayload)
        case selecting
        case confirming(PromptBurstPayload)
    }

    @EnvironmentObject private var store: RecordStore
    @State private var showTodayTimeline = false
    @State private var showSettings = false
    @State private var interactionStage: InteractionStage = .idle
    @State private var phaseTask: DispatchWorkItem?
    @State private var idlePulse = false
    @State private var historyScope: RecordRangeScope = .today

    private var theme: AppTheme { store.theme }

    var body: some View {
        panelShell {
            if showSettings {
                settingsScreen
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        topStageView
                        if !interactionStageIsSelecting {
                            liveStatusSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if showTodayTimeline && !interactionStageIsSelecting {
                            historyTimeline
                        }

                        if interactionStageIsSelecting {
                            selectingPhase
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !showSettings {
                HStack(spacing: 8) {
                    quitButton
                    settingsButton
                }
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
        }
        .alert(item: $store.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("确定"))
            )
        }
        .onAppear {
            resetToIdle()
        }
        .onDisappear {
            cancelPhaseTask()
            if store.isArmed {
                store.cancelPendingRecord()
            }
            interactionStage = .idle
            showSettings = false
        }
    }

    private var settingsButton: some View {
        overlayIconButton(symbol: "gearshape", action: openSettingsWindow)
    }

    private var quitButton: some View {
        overlayIconButton(symbol: "power", action: terminateApp)
    }

    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                overlayIconButton(symbol: "chevron.left", action: closeSettings)
                Spacer(minLength: 0)
                quitButton
            }

            SettingsView(presentation: .embedded)
                .environmentObject(store)
        }
    }

    private func overlayIconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(theme.surface.opacity(theme.style.id == .glass ? 0.72 : 0.94))
                        .overlay(
                            Circle()
                                .stroke(theme.border.opacity(0.92), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var topStageView: some View {
        ZStack {
            StageBackdropView(theme: theme)

            switch interactionStage {
            case .idle:
                idlePhase
            case .armingBurst(let payload), .confirming(let payload):
                AnimatedPromptBurstView(payload: payload, theme: theme)
                    .id(payload.centerText + payload.particles.joined(separator: "|"))
            case .selecting:
                selectingReadyPhase
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: stageHeight)
        .clipShape(RoundedRectangle(cornerRadius: theme.style.stageCornerRadius, style: .continuous))
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: interactionStageIsSelecting)
    }

    private var idlePhase: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 20)

            Button(action: startArmingPhase) {
                AccentControlView(
                    theme: theme,
                    frameSize: 142,
                    showsHalo: true,
                    usesArmedGradient: false,
                    pulseScale: idlePulse ? 1.06 : 0.96
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)
        }
        .onAppear {
            if !idlePulse {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    idlePulse = true
                }
            }
        }
    }

    private var selectingReadyPhase: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)

            AccentControlView(
                theme: theme,
                frameSize: 84,
                showsHalo: true,
                usesArmedGradient: true
            )

            if let pendingTimestamp = store.pendingTimestamp {
                Text("已记录 \(Self.recordLabel(for: pendingTimestamp))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 6)
        }
    }

    private var liveStatusSection: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let activeState = activeStateDisplay

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(stateIndicatorColor(for: activeState.colorHex))
                            .frame(width: 10, height: 10)

                        Text(activeState.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .center, spacing: 10) {
                        FlipClockView(date: context.date, theme: theme)

                        Spacer(minLength: 0)

                        Text(liveDurationLabel(at: context.date))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(theme.surfaceAlt.opacity(0.94))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(theme.border.opacity(0.92), lineWidth: 1)
                                    )
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: theme.style.surfaceCornerRadius, style: .continuous)
                        .fill(theme.surface.opacity(theme.style.id == .glass ? 0.82 : 0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.style.surfaceCornerRadius, style: .continuous)
                                .stroke(theme.border.opacity(0.92), lineWidth: 1)
                        )
                )
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showTodayTimeline.toggle()
                }
            } label: {
                Image(systemName: showTodayTimeline ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 28, height: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.surface.opacity(0.96))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(theme.border.opacity(0.92), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var selectingPhase: some View {
        VStack(spacing: 10) {
            stateGrid
            utilityRow
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var stateGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(store.states) { state in
                let enabled = interactionStageIsSelecting && store.isArmed
                let selected = store.currentStateCode == state.code && !store.isArmed

                Button {
                    commitWithAnimation(state)
                } label: {
                    HStack(spacing: 8) {
                        Text(state.label)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if selected {
                            Circle()
                                .fill(theme.stateText(on: state.colorHex, enabled: false, selected: true).opacity(0.9))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: theme.style.chipCornerRadius, style: .continuous)
                            .fill(theme.stateFill(state.colorHex, enabled: enabled, selected: selected))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.style.chipCornerRadius, style: .continuous)
                                    .stroke(theme.stateEdge(state.colorHex), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.stateText(on: state.colorHex, enabled: enabled, selected: selected))
                .opacity(enabled || selected ? 1 : 0.92)
                .disabled(!enabled)
            }
        }
    }

    private var utilityRow: some View {
        HStack(spacing: 8) {
            utilityButton("撤销") {
                handleUndo()
            }
        }
    }

    private var historyTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(RecordRangeScope.allCases) { scope in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            historyScope = scope
                        }
                    } label: {
                        Text(scope.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(historyScope == scope ? theme.ink : theme.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(historyScope == scope ? theme.accentSoft.opacity(0.28) : theme.surface)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(
                                                historyScope == scope ? theme.accentPrimary.opacity(0.52) : theme.border.opacity(0.92),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            if timelineRecords.isEmpty {
                Text(historyScope == .today ? "今天暂无切换" : "暂无历史记录")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textDim)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(timelineRecords.reversed())) { record in
                        Text("\(Self.timelineLabel(for: record, scope: historyScope)) - \(record.currentState)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: theme.style.utilityCornerRadius, style: .continuous)
                                    .fill(theme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: theme.style.utilityCornerRadius, style: .continuous)
                                            .stroke(theme.border.opacity(0.92), lineWidth: 1)
                                    )
                            )
                    }
                }
            }
        }
    }

    private var timelineRecords: [RecordEvent] {
        store.records(for: historyScope)
    }

    private func utilityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: theme.style.utilityCornerRadius, style: .continuous)
                        .fill(theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.style.utilityCornerRadius, style: .continuous)
                                .stroke(theme.border.opacity(0.92), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func panelShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(width: 348)
            .background(
                ZStack {
                    theme.shellGradient
                    RoundedRectangle(cornerRadius: theme.style.shellCornerRadius, style: .continuous)
                        .fill(theme.panel.opacity(theme.style.id == .glass ? 0.88 : 0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.style.shellCornerRadius, style: .continuous)
                                .stroke(theme.border.opacity(0.9), lineWidth: 1)
                        )
                }
            )
            .shadow(color: theme.ink.opacity(0.08), radius: 18, y: 10)
            .clipShape(RoundedRectangle(cornerRadius: theme.style.shellCornerRadius, style: .continuous))
    }

    private var interactionStageIsSelecting: Bool {
        if case .selecting = interactionStage {
            return true
        }
        return false
    }

    private var stageHeight: CGFloat {
        switch interactionStage {
        case .selecting:
            return 124
        default:
            return 224
        }
    }

    private var activeStateDisplay: (label: String, colorHex: String?) {
        if let state = store.currentStateDefinition {
            return (state.label, state.colorHex)
        }
        if let label = store.currentStateLabel {
            return (label, nil)
        }
        if store.isArmed {
            return ("待选择", nil)
        }
        return ("未设定", nil)
    }

    private func startArmingPhase() {
        cancelPhaseTask()
        showTodayTimeline = false
        store.armRecord()
        interactionStage = .armingBurst(armingPayload())

        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                interactionStage = .selecting
            }
        }
        phaseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.26, execute: task)
    }

    private func commitWithAnimation(_ state: StateDefinition) {
        store.commit(state: state)
        guard !store.isArmed else {
            return
        }

        cancelPhaseTask()
        interactionStage = .confirming(confirmPayload(for: state.label))

        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.2)) {
                interactionStage = .idle
            }
        }
        phaseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.22, execute: task)
    }

    private func resetToIdle() {
        cancelPhaseTask()
        if store.isArmed {
            store.cancelPendingRecord()
        }
        interactionStage = .idle
        idlePulse = false
    }

    private func cancelPhaseTask() {
        phaseTask?.cancel()
        phaseTask = nil
    }

    private func openSettingsWindow() {
        withAnimation(.easeOut(duration: 0.18)) {
            showSettings = true
        }
    }

    private func closeSettings() {
        withAnimation(.easeOut(duration: 0.18)) {
            showSettings = false
        }
    }

    private func handleUndo() {
        let wasArmed = store.isArmed
        store.undoLastRecord()
        if wasArmed {
            cancelPhaseTask()
            withAnimation(.easeOut(duration: 0.18)) {
                interactionStage = .idle
            }
        }
    }

    private func terminateApp() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.terminateApp()
            return
        }
        NSApp.terminate(nil)
    }

    private func stateIndicatorColor(for colorHex: String?) -> Color {
        guard let colorHex else {
            return theme.textDim.opacity(0.38)
        }
        return Color(hex: colorHex)
    }

    private func liveDurationLabel(at now: Date) -> String {
        guard let startedAt = store.currentStateStartedAt else {
            return store.isArmed ? "待选标签" : "暂无状态"
        }
        return "已持续 \(Self.durationLabel(since: startedAt, now: now))"
    }

    private func armingPayload() -> PromptBurstPayload {
        PromptBurstPayload(
            centerText: "记录成功～",
            particles: [
                "记录完成～",
                "时间入链～",
                "节奏就位～",
                "灵感落点～",
                "状态起笔～",
                "轨迹生成～",
            ]
        )
    }

    private func confirmPayload(for label: String) -> PromptBurstPayload {
        PromptBurstPayload(
            centerText: "已转换为\n\(label)",
            particles: [
                "切换完成～",
                label,
                "形态更新～",
                "状态落稳～",
                label,
                "轨迹续上～",
            ]
        )
    }

    private static func recordLabel(for date: Date) -> String {
        clockFormatter.string(from: date)
    }

    private static func timelineLabel(for record: RecordEvent, scope: RecordRangeScope) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        fallbackFormatter.timeZone = .current

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = scope == .today ? "HH:mm:ss" : "MM-dd HH:mm"
        displayFormatter.timeZone = .current

        if let date = formatter.date(from: record.recordedAt) ?? fallbackFormatter.date(from: record.recordedAt) {
            return displayFormatter.string(from: date)
        }
        return record.recordedAt
    }

    private static func durationLabel(since start: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()
}
