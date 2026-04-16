import SwiftUI
import AppKit

struct SettingsView: View {
    enum Presentation {
        case window
        case embedded
    }

    enum Page: String, CaseIterable, Identifiable {
        case color = "color"
        case add = "Add"
        case export = "Export"

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: RecordStore
    @State private var editingStateCode: String?
    @State private var editingStateName = ""
    @State private var pendingDeleteState: StateDefinition?
    @State private var activePage: Page = .color
    @State private var exportScope: RecordRangeScope = .today
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
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.system(size: presentation == .window ? 26 : 22, weight: .bold))
                .foregroundStyle(theme.ink)
        }
    }

    private var pageSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases) { page in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        activePage = page
                    }
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

    @ViewBuilder
    private var activePageView: some View {
        switch activePage {
        case .color:
            paletteSection
        case .add:
            tagSection
        case .export:
            exportSection
        }
    }

    private var styleSection: some View {
        sectionCard {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(ThemeCatalog.styles) { style in
                    let previewTheme = ThemeCatalog.theme(styleID: style.id, paletteID: store.appearanceSelection.paletteID)
                    Button {
                        store.setAppearanceStyle(style.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                StageBackdropView(theme: previewTheme, compact: true)
                                AccentControlView(theme: previewTheme, frameSize: 62, showsHalo: true)
                            }
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(style.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                    if store.appearanceSelection.styleID == style.id {
                                        Circle()
                                            .fill(theme.accentPrimary)
                                            .frame(width: 7, height: 7)
                                    }
                                }

                                Text(style.subtitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textMuted)

                                Text(style.note)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.textDim)
                                    .lineLimit(2)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(theme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(
                                            store.appearanceSelection.styleID == style.id ? theme.accentPrimary.opacity(0.6) : theme.border.opacity(0.92),
                                            lineWidth: store.appearanceSelection.styleID == style.id ? 1.4 : 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
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
                    TextField("新标签", text: $store.draftStateName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
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

                    Button(action: store.addState) {
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

    private var exportSection: some View {
        sectionCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(RecordRangeScope.allCases) { scope in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                exportScope = scope
                            }
                        } label: {
                            Text(scope.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(exportScope == scope ? theme.ink : theme.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(exportScope == scope ? theme.accentSoft.opacity(0.28) : theme.surface)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(
                                                    exportScope == scope ? theme.accentPrimary.opacity(0.52) : theme.border.opacity(0.92),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }

                Button(action: exportRecords) {
                    Text("导出\(exportScope.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.surfaceAlt.opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(theme.border.opacity(0.95), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func managerRow(for state: StateDefinition) -> some View {
        let isEditing = editingStateCode == state.code

        return HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: state.colorHex))
                .frame(width: 10, height: 10)

            if isEditing {
                TextField("", text: $editingStateName, prompt: Text(state.label).foregroundColor(theme.textDim))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                    .onSubmit {
                        saveEditing(for: state)
                    }
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
        store.renameState(code: state.code, to: editingStateName)
        cancelEditing()
    }

    private func cancelEditing() {
        editingStateCode = nil
        editingStateName = ""
    }

    private func exportRecords() {
        guard let urls = store.exportAll(scope: exportScope) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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
