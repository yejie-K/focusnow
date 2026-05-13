import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum AutoFeedbackPreviewKind: String, Identifiable, Equatable {
    case beaconBubble
    case systemNotification

    var id: String { rawValue }
}

struct SettingsView: View {
    private enum Chrome {
        static let iconButtonSize: CGFloat = 28
    }

    enum Presentation {
        case window
        case embedded
    }

    enum Page: String, CaseIterable, Identifiable {
        case board = "Board"
        case remind = "Remind"
        case auto = "Auto"
        case color = "color"
        case add = "Add"

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: RecordStore
    @State private var editingStateCode: String?
    @State private var editingStateName = ""
    @State private var pendingDeleteState: StateDefinition?
    @State private var activePage: Page = .board
    @State private var activeAutoFeedbackPreview: AutoFeedbackPreviewKind?
    let presentation: Presentation

    private var theme: AppTheme { store.theme }

    init(presentation: Presentation = .window) {
        self.presentation = presentation
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                pageSwitcher
                activePageView
            }
            .padding(presentation == .window ? 22 : 0)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .frame(
            width: presentation == .window ? 620 : nil,
            height: presentation == .window ? 720 : nil
        )
        .background(presentation == .window ? AnyView(theme.shellGradient) : AnyView(Color.clear))
        .alert(item: $store.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("确定"))
            )
        }
        .confirmationDialog(
            "删除标签",
            isPresented: Binding(
                get: { pendingDeleteState != nil },
                set: { if !$0 { pendingDeleteState = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let state = pendingDeleteState {
                Button("删除", role: .destructive) {
                    store.deleteState(code: state.code)
                    pendingDeleteState = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteState = nil
            }
        } message: {
            if let state = pendingDeleteState {
                Text("删除“\(state.label)”后将不能再用于新记录。")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("设置")
                .font(.system(size: presentation == .window ? 26 : 22, weight: .bold))
                .foregroundStyle(theme.ink)

            Spacer(minLength: 0)

            if presentation == .window {
                ExportCircleButton(theme: theme, size: Chrome.iconButtonSize) { scope in
                    exportRecords(scope: scope)
                }
            }
        }
    }

    private var pageSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Page.allCases) { page in
                    Button {
                        activePage = page
                    } label: {
                        Text(page.rawValue)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(activePage == page ? theme.ink : theme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(activePage == page ? theme.accentSoft.opacity(0.28) : theme.surface)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(
                                                activePage == page ? theme.accentPrimary.opacity(0.52) : theme.border.opacity(0.92),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var activePageView: some View {
        switch activePage {
        case .board:
            DashboardView(theme: theme, states: store.states, records: store.records)
        case .remind:
            remindSection
        case .auto:
            autoSection
        case .color:
            paletteSection
        case .add:
            tagSection
        }
    }

    private var autoSection: some View {
        sectionCard {
            VStack(spacing: 8) {
                settingRow(title: "启用") {
                    switchControl(autoSwitchEnabledBinding)
                }

                settingRow(title: "稳定") {
                    secondAdjuster(
                        value: store.automationSettings.autoSwitch.settleSeconds,
                        enabled: store.automationSettings.autoSwitch.isEnabled,
                        decrement: {
                            store.setAutoSwitchSettleSeconds(store.automationSettings.autoSwitch.settleSeconds - 10)
                        },
                        increment: {
                            store.setAutoSwitchSettleSeconds(store.automationSettings.autoSwitch.settleSeconds + 10)
                        }
                    )
                }

                settingRow(title: "倒计时") {
                    autoCountdownStylePicker
                }

                settingRow(title: "前台") {
                    Text(store.currentFrontmostApplication?.localizedName ?? "-")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }

                settingRow(title: "候选") {
                    Text(autoCandidateLabel)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }

                autoFeedbackSection
                autoBindingBoard
            }
        }
    }

    private var remindSection: some View {
        sectionCard {
            VStack(spacing: 8) {
                settingRow(title: "通知") {
                    HStack(spacing: 10) {
                        Text(notificationPermissionLabel)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.textMuted)

                        Button("打开") {
                            openNotificationSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.accentSoft.opacity(0.22))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                                )
                        )
                    }
                }

                settingRow(title: "启用") {
                    switchControl(reminderEnabledBinding)
                }

                settingRow(title: "稍后") {
                    minuteAdjuster(
                        value: store.automationSettings.reminder.snoozeMinutes,
                        enabled: true,
                        decrement: {
                            store.setReminderSnoozeMinutes(store.automationSettings.reminder.snoozeMinutes - 5)
                        },
                        increment: {
                            store.setReminderSnoozeMinutes(store.automationSettings.reminder.snoozeMinutes + 5)
                        }
                    )
                }

                LazyVStack(spacing: 8) {
                    ForEach(store.states) { state in
                        reminderRow(for: state)
                    }
                }
            }
        }
    }

    private var paletteSection: some View {
        sectionCard {
            LazyVStack(spacing: 8) {
                ForEach(ThemeCatalog.palettes) { palette in
                    Button {
                        store.setAppearancePalette(palette.id)
                    } label: {
                        HStack(spacing: 10) {
                            Text(palette.name)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .frame(width: 56, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach(palette.swatches, id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(theme.surfaceAlt.opacity(0.9))
                            )

                            Spacer(minLength: 0)

                            Circle()
                                .fill(store.appearanceSelection.paletteID == palette.id ? theme.accentPrimary : theme.border.opacity(0.72))
                                .frame(width: 8, height: 8)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            store.appearanceSelection.paletteID == palette.id ? theme.accentPrimary.opacity(0.6) : theme.border.opacity(0.92),
                                            lineWidth: store.appearanceSelection.paletteID == palette.id ? 1.4 : 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tagSection: some View {
        sectionCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    IMETextField(
                        placeholder: "新标签",
                        text: $store.draftStateName,
                        font: .systemFont(ofSize: 13, weight: .medium),
                        textColor: NSColor(hex: theme.palette.textHex) ?? .labelColor,
                        placeholderColor: NSColor(hex: theme.palette.textDimHex) ?? .placeholderTextColor,
                        onSubmit: submitDraftState
                    )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.surfaceAlt)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                        )

                    Button(action: submitDraftState) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(theme.accentSoft.opacity(0.22))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(theme.border, lineWidth: 1)
                                    )
                            )
                            .foregroundStyle(theme.ink)
                    }
                    .buttonStyle(.plain)
                }

                LazyVStack(spacing: 8) {
                    ForEach(store.states) { state in
                        managerRow(for: state)
                    }
                }
            }
        }
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.automationSettings.reminder.isEnabled },
            set: { store.setReminderEnabled($0) }
        )
    }

    private var autoSwitchEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.automationSettings.autoSwitch.isEnabled },
            set: { store.setAutoSwitchEnabled($0) }
        )
    }

    private var autoCountdownStylePicker: some View {
        HStack(spacing: 6) {
            ForEach(AutoSwitchCountdownStyle.allCases) { style in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        store.setAutoSwitchCountdownStyle(style)
                    }
                } label: {
                    Text(style.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(store.automationSettings.autoSwitch.countdownStyle == style ? theme.ink : theme.textDim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.automationSettings.autoSwitch.countdownStyle == style ? theme.accentSoft.opacity(0.3) : theme.surfaceAlt.opacity(0.72))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            store.automationSettings.autoSwitch.countdownStyle == style ? theme.accentPrimary.opacity(0.52) : theme.border.opacity(0.86),
                                            lineWidth: 1
                                        )
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var autoFeedbackSection: some View {
        VStack(spacing: 8) {
            boardTitle("反馈")
                .frame(maxWidth: .infinity, alignment: .leading)

            feedbackSettingRow(title: "浮标气泡", kind: .beaconBubble, binding: autoFeedbackBeaconBubbleBinding)
            feedbackPreviewSlot(.beaconBubble)

            feedbackSettingRow(title: "系统通知", kind: .systemNotification, binding: autoFeedbackSystemNotificationBinding)
            feedbackPreviewSlot(.systemNotification)
        }
    }

    @ViewBuilder
    private func feedbackPreviewSlot(_ kind: AutoFeedbackPreviewKind) -> some View {
        if activeAutoFeedbackPreview == kind {
            AutoFeedbackPreviewCard(kind: kind, theme: theme)
                .id(kind.id)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        activeAutoFeedbackPreview = hovering ? kind : nil
                    }
                }
                .padding(.top, -2)
                .padding(.bottom, 2)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
        }
    }

    private func showAutoFeedbackPreview(_ kind: AutoFeedbackPreviewKind) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            if activeAutoFeedbackPreview == kind {
                activeAutoFeedbackPreview = nil
            } else {
                activeAutoFeedbackPreview = kind
            }
        }
    }

    private var autoFeedbackBeaconBubbleBinding: Binding<Bool> {
        Binding(
            get: { store.automationSettings.autoSwitch.feedback.beaconBubble },
            set: { store.setAutoSwitchFeedbackBeaconBubble($0) }
        )
    }

    private var autoFeedbackSystemNotificationBinding: Binding<Bool> {
        Binding(
            get: { store.automationSettings.autoSwitch.feedback.systemNotification },
            set: { store.setAutoSwitchFeedbackSystemNotification($0) }
        )
    }

    private func feedbackToggle(_ binding: Binding<Bool>) -> some View {
        switchControl(binding, size: .mini)
    }

    private func feedbackSettingRow(title: String, kind: AutoFeedbackPreviewKind, binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)

                feedbackInfoIcon(kind)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            feedbackToggle(binding)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            activeAutoFeedbackPreview == kind ? theme.accentPrimary.opacity(0.46) : theme.border.opacity(0.95),
                            lineWidth: activeAutoFeedbackPreview == kind ? 1.2 : 1
                        )
                )
        )
    }

    private func feedbackInfoIcon(_ kind: AutoFeedbackPreviewKind) -> some View {
        let isActive = activeAutoFeedbackPreview == kind

        return ZStack {
            Circle()
                .fill(isActive ? theme.accentSoft.opacity(0.34) : theme.surfaceAlt.opacity(0.9))

            Circle()
                .stroke(isActive ? theme.accentPrimary.opacity(0.64) : theme.border.opacity(0.92), lineWidth: 1)

            Text("i")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(isActive ? theme.ink : theme.textMuted)
        }
        .frame(width: 16, height: 16)
        .contentShape(Circle())
        .onHover { hovering in
            if hovering {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    activeAutoFeedbackPreview = kind
                }
            }
        }
        .onTapGesture {
            showAutoFeedbackPreview(kind)
        }
        .accessibilityLabel("预览")
    }

    private func switchControl(_ binding: Binding<Bool>, size: FocusSwitchSize = .regular) -> some View {
        FocusSwitchControl(isOn: binding, theme: theme, size: size)
    }

    private var autoCandidateLabel: String {
        guard let candidate = store.autoSwitchCandidate else {
            return "-"
        }

        return "\(candidate.appName) -> \(candidate.stateLabel)"
    }

    private var autoBindingBoard: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                boardTitle("标签")
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(store.states) { state in
                            autoStateDropCard(for: state)
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: autoBoardHeight)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                boardTitle("App")
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        if store.knownApplications.isEmpty {
                            Text("暂无")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(theme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(theme.border.opacity(0.92), lineWidth: 1)
                                        )
                                )
                        } else {
                            ForEach(store.knownApplications) { app in
                                autoAppDragCard(for: app)
                            }
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: autoBoardHeight)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var autoBoardHeight: CGFloat {
        presentation == .window ? 440 : 260
    }

    private func boardTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.textMuted)
            .padding(.horizontal, 2)
    }

    private func autoStateDropCard(for state: StateDefinition) -> some View {
        let boundIdentifiers = store.boundAutoSwitchAppIdentifiers(for: state.code)
        let rule = store.autoSwitchRule(for: state.code)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: state.colorHex))
                    .frame(width: 9, height: 9)

                Text(state.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                switchControl(
                    Binding(
                        get: { store.autoSwitchRule(for: state.code).isEnabled },
                        set: { store.setAutoSwitchRuleEnabled(for: state.code, enabled: $0) }
                    ),
                    size: .mini
                )
            }

            if boundIdentifiers.isEmpty {
                Text("拖入")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.surfaceAlt.opacity(0.7))
                    )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(boundIdentifiers, id: \.self) { identifier in
                        autoBoundChip(identifier: identifier, stateCode: state.code)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface.opacity(rule.isEnabled ? 1 : 0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                )
        )
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleAutoAppDrop(providers, to: state)
        }
    }

    private func autoBoundChip(identifier: String, stateCode: String) -> some View {
        HStack(spacing: 6) {
            Text(store.autoSwitchDisplayName(for: identifier))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                store.unbindAutoSwitchAppIdentifier(identifier, from: stateCode)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surfaceAlt.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.border.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private func autoAppDragCard(for app: FrontmostApplicationSnapshot) -> some View {
        let boundState = store.autoSwitchBoundState(for: app)

        return HStack(spacing: 8) {
            appIcon(for: app)

            Text(app.localizedName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(app.localizedName)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(boundState == nil ? theme.surface : theme.accentSoft.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(boundState == nil ? theme.border.opacity(0.92) : theme.accentPrimary.opacity(0.34), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            presentAutoAppBindingMenu(for: app, boundState: boundState)
        }
        .onDrag {
            NSItemProvider(object: app.stableIdentifier as NSString)
        }
    }

    private func presentAutoAppBindingMenu(for app: FrontmostApplicationSnapshot, boundState: StateDefinition?) {
        let menu = NSMenu()

        for state in store.states {
            let title = boundState?.code == state.code ? "\(state.label) ✓" : state.label
            menu.addItem(
                AutoAppBindingMenuItem(title: title) {
                    store.bindAutoSwitchAppIdentifier(app.stableIdentifier, to: state.code)
                }
            )
        }

        if let boundState {
            menu.addItem(.separator())
            menu.addItem(
                AutoAppBindingMenuItem(title: "解绑 \(boundState.label)") {
                    store.unbindAutoSwitchAppIdentifier(app.stableIdentifier, from: boundState.code)
                }
            )
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func appIcon(for app: FrontmostApplicationSnapshot) -> some View {
        Group {
            if let path = app.bundleURLPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func handleAutoAppDrop(_ providers: [NSItemProvider], to state: StateDefinition) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? NSString else {
                return
            }
            let appIdentifier = String(identifier)

            DispatchQueue.main.async {
                store.bindAutoSwitchAppIdentifier(appIdentifier, to: state.code)
            }
        }

        return true
    }

    private var notificationPermissionLabel: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional:
            return "已允许"
        case .notDetermined:
            return "未请求"
        case .denied:
            return "未允许"
        case .ephemeral:
            return "临时允许"
        @unknown default:
            return "未知"
        }
    }

    private func reminderRow(for state: StateDefinition) -> some View {
        let rule = store.reminderRule(for: state.code)

        return HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: state.colorHex))
                .frame(width: 10, height: 10)

            Text(state.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 0)

            minuteAdjuster(
                value: rule.thresholdMinutes,
                enabled: rule.isEnabled,
                decrement: {
                    store.setReminderThreshold(for: state.code, minutes: rule.thresholdMinutes - 5)
                },
                increment: {
                    store.setReminderThreshold(for: state.code, minutes: rule.thresholdMinutes + 5)
                }
            )

            switchControl(
                Binding(
                    get: { store.reminderRule(for: state.code).isEnabled },
                    set: { store.setReminderRuleEnabled(for: state.code, enabled: $0) }
                ),
                size: .mini
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                )
        )
    }

    private func autoRuleRow(for state: StateDefinition) -> some View {
        let rule = store.autoSwitchRule(for: state.code)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: state.colorHex))
                    .frame(width: 10, height: 10)

                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                switchControl(
                    Binding(
                        get: { store.autoSwitchRule(for: state.code).isEnabled },
                        set: { store.setAutoSwitchRuleEnabled(for: state.code, enabled: $0) }
                    ),
                    size: .mini
                )
            }

            IMETextField(
                placeholder: "App 名称或 Bundle ID",
                text: Binding(
                    get: { store.autoSwitchBindingText(for: state.code) },
                    set: { store.setAutoSwitchAppBindingText(for: state.code, text: $0) }
                ),
                font: .systemFont(ofSize: 12.5, weight: .medium),
                textColor: NSColor(hex: theme.palette.textHex) ?? .labelColor,
                placeholderColor: NSColor(hex: theme.palette.textDimHex) ?? .placeholderTextColor
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.surfaceAlt.opacity(rule.isEnabled ? 0.94 : 0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.border.opacity(0.9), lineWidth: 1)
                    )
            )
            .opacity(rule.isEnabled ? 1 : 0.64)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                )
        )
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                )
        )
    }

    private func minuteAdjuster(
        value: Int,
        enabled: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            tinyIconButton(symbol: "minus", enabled: enabled, action: decrement)
            Text("\(value)m")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(enabled ? theme.text : theme.textDim)
                .frame(minWidth: 44)
            tinyIconButton(symbol: "plus", enabled: enabled, action: increment)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surfaceAlt.opacity(enabled ? 0.94 : 0.74))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.border.opacity(0.92), lineWidth: 1)
                )
        )
        .opacity(enabled ? 1 : 0.58)
    }

    private func secondAdjuster(
        value: Int,
        enabled: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            tinyIconButton(symbol: "minus", enabled: enabled, action: decrement)
            Text("\(value)s")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(enabled ? theme.text : theme.textDim)
                .frame(minWidth: 44)
            tinyIconButton(symbol: "plus", enabled: enabled, action: increment)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surfaceAlt.opacity(enabled ? 0.94 : 0.74))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.border.opacity(0.92), lineWidth: 1)
                )
        )
        .opacity(enabled ? 1 : 0.58)
    }

    private func tinyIconButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(enabled ? theme.textMuted : theme.textDim)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func managerRow(for state: StateDefinition) -> some View {
        let isEditing = editingStateCode == state.code

        return HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: state.colorHex))
                .frame(width: 10, height: 10)

            if isEditing {
                IMETextField(
                    placeholder: state.label,
                    text: $editingStateName,
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: NSColor(hex: theme.palette.textHex) ?? .labelColor,
                    placeholderColor: NSColor(hex: theme.palette.textDimHex) ?? .placeholderTextColor,
                    onSubmit: { saveEditing(for: state) }
                )
            } else {
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isEditing {
                iconButton(symbol: "checkmark", foreground: theme.ink, background: theme.accentSoft.opacity(0.18)) {
                    saveEditing(for: state)
                }

                iconButton(symbol: "xmark", foreground: theme.textMuted, background: theme.surface) {
                    cancelEditing()
                }
            } else {
                iconButton(symbol: "pencil", foreground: theme.ink, background: theme.surface) {
                    editingStateCode = state.code
                    editingStateName = state.label
                }

                iconButton(symbol: "trash", foreground: theme.textMuted, background: theme.surface) {
                    pendingDeleteState = state
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                )
        )
    }

    private func saveEditing(for state: StateDefinition) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        store.renameState(code: state.code, to: editingStateName)
        cancelEditing()
    }

    private func submitDraftState() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async {
            store.addState()
        }
    }

    private func cancelEditing() {
        editingStateCode = nil
        editingStateName = ""
    }

    private func exportRecords(scope: RecordRangeScope) {
        guard let urls = store.exportAll(scope: scope) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for rawValue in candidates {
            guard let url = URL(string: rawValue) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.panel.opacity(theme.style.id == .glass ? 0.92 : 0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.border.opacity(0.88), lineWidth: 1)
                )
        )
    }

    private func iconButton(symbol: String, foreground: Color, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(theme.border.opacity(0.95), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

}

private struct AutoFeedbackPreviewCard: View {
    let kind: AutoFeedbackPreviewKind
    let theme: AppTheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            preview(at: context.date.timeIntervalSinceReferenceDate)
                .frame(maxWidth: .infinity, minHeight: 74)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.surfaceAlt.opacity(0.76))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(theme.accentPrimary.opacity(0.28), lineWidth: 1)
                        )
                )
        }
    }

    @ViewBuilder
    private func preview(at time: TimeInterval) -> some View {
        switch kind {
        case .beaconBubble:
            beaconBubblePreview(time)
        case .systemNotification:
            systemNotificationPreview(time)
        }
    }

    private func beaconBubblePreview(_ time: TimeInterval) -> some View {
        let progress = CGFloat((time * 0.82).truncatingRemainder(dividingBy: 1))
        let entrance = min(progress / 0.34, 1)
        let settle = CGFloat(sin(Double(min(progress, 0.5) / 0.5) * .pi)) * 0.03

        return HStack(spacing: 10) {
            miniBeacon

            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.accentPrimary)

                Text("看消息 · 飞书")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.panel.opacity(0.96))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.border.opacity(0.92), lineWidth: 1)
                    )
            )
            .opacity(Double(entrance))
            .offset(x: (1 - entrance) * -8)
            .scaleEffect(0.96 + entrance * 0.04 + settle, anchor: .leading)

            Spacer(minLength: 0)
        }
    }

    private func systemNotificationPreview(_ time: TimeInterval) -> some View {
        let pulse = 0.98 + 0.02 * CGFloat((sin(time * 3.4) + 1) / 2)

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accentSoft.opacity(0.9), theme.accentPrimary.opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.ink)
                )
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("FocusNow")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.textDim)

                Text("已切换到 看消息 · 飞书")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.panel.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.border.opacity(0.92), lineWidth: 1)
                )
                .shadow(color: theme.ink.opacity(0.1), radius: 14, y: 6)
        )
        .scaleEffect(pulse)
    }

    private var miniBeacon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(theme.border.opacity(0.92), lineWidth: 1)
                )
                .shadow(color: theme.ink.opacity(0.08), radius: 8, y: 3)

            Circle()
                .fill(theme.accentPrimary)
                .frame(width: 10, height: 10)
        }
        .frame(width: 34, height: 34)
    }
}

private enum FocusSwitchSize {
    case regular
    case compact
    case mini

    var width: CGFloat {
        switch self {
        case .regular:
            return 64
        case .compact:
            return 54
        case .mini:
            return 34
        }
    }

    var height: CGFloat {
        switch self {
        case .regular:
            return 30
        case .compact:
            return 26
        case .mini:
            return 20
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .regular:
            return 11
        case .compact:
            return 10
        case .mini:
            return 0
        }
    }

    var segmentWidth: CGFloat {
        showsLabels ? (width - 5) / 2 : height - 6
    }

    var segmentHeight: CGFloat {
        showsLabels ? height - 5 : height - 6
    }

    var segmentOffset: CGFloat {
        showsLabels ? segmentWidth / 2 : (width - segmentWidth - 6) / 2
    }

    var showsLabels: Bool {
        self != .mini
    }
}

private final class AutoAppBindingMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
        target = self
        action = #selector(run)
    }

    @objc private func run() {
        handler()
    }
}

private struct FocusSwitchControl: View {
    @Binding var isOn: Bool
    let theme: AppTheme
    let size: FocusSwitchSize

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(trackFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(trackStroke, lineWidth: 1)
                    )

                Capsule(style: .continuous)
                    .fill(segmentFill)
                    .frame(width: size.segmentWidth, height: size.segmentHeight)
                    .shadow(color: theme.ink.opacity(isOn ? 0.12 : 0.06), radius: 4, y: 1)
                    .offset(x: isOn ? size.segmentOffset : -size.segmentOffset)

                if size.showsLabels {
                    HStack(spacing: 0) {
                        Text("关")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(isOn ? theme.textDim : theme.ink)

                        Text("开")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(isOn ? Color.white.opacity(0.96) : theme.textDim)
                    }
                    .font(.system(size: size.fontSize, weight: .bold))
                    .padding(.horizontal, 4)
                } else {
                    Circle()
                        .fill(isOn ? Color.white.opacity(0.94) : theme.textDim.opacity(0.74))
                        .frame(width: 5, height: 5)
                        .offset(x: isOn ? size.segmentOffset : -size.segmentOffset)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "已开启" : "已关闭")
    }

    private var trackFill: Color {
        isOn ? theme.accentSoft.opacity(0.24) : theme.surfaceAlt.opacity(0.84)
    }

    private var trackStroke: Color {
        isOn ? theme.accentPrimary.opacity(0.46) : theme.border.opacity(0.95)
    }

    private var segmentFill: Color {
        isOn ? theme.accentPrimary : theme.surface
    }
}
