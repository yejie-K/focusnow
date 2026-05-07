import AppKit
import SwiftUI

struct ExportCircleButton: View {
    let theme: AppTheme
    var size: CGFloat = 28
    let export: (RecordRangeScope) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            ExportMenuPresenter.present(export: export)
        } label: {
            ZStack {
                Circle()
                    .fill(theme.surface.opacity(theme.style.id == .glass ? 0.72 : 0.94))
                    .overlay(
                        Circle()
                            .stroke(isHovered ? theme.accentPrimary.opacity(0.42) : theme.border.opacity(0.92), lineWidth: 1)
                    )

                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.system(size: 11.2, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? theme.ink : theme.textMuted)
                    .offset(y: -0.4)

                Circle()
                    .fill((isHovered ? theme.ink : theme.textMuted).opacity(0.72))
                    .frame(width: 4, height: 4)
                    .overlay(
                        Circle()
                            .stroke(theme.surface.opacity(0.9), lineWidth: 0.6)
                    )
                    .offset(x: 8.2, y: -8.2)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .scaleEffect(isHovered ? 1.04 : 1)
        .clipShape(Circle())
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.82)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("导出")
    }
}

struct ChromeCircleButton: View {
    let symbol: String
    let theme: AppTheme
    var size: CGFloat = 28
    var iconSize: CGFloat = 12
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isHovered ? theme.ink : theme.textMuted)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(theme.surface.opacity(theme.style.id == .glass ? 0.72 : 0.94))
                        .overlay(
                            Circle()
                                .stroke(isHovered ? theme.accentPrimary.opacity(0.42) : theme.border.opacity(0.92), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .scaleEffect(isHovered ? 1.04 : 1)
        .clipShape(Circle())
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.84)) {
                isHovered = hovering
            }
        }
    }
}

@MainActor
private final class ExportMenuPresenter: NSObject {
    private static var retainedPresenter: ExportMenuPresenter?

    private let export: (RecordRangeScope) -> Void

    private init(export: @escaping (RecordRangeScope) -> Void) {
        self.export = export
    }

    static func present(export: @escaping (RecordRangeScope) -> Void) {
        let presenter = ExportMenuPresenter(export: export)
        retainedPresenter = presenter

        let menu = NSMenu()
        menu.addItem(presenter.item(title: "导出今天", scope: .today))
        menu.addItem(presenter.item(title: "导出全部", scope: .all))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

        retainedPresenter = nil
    }

    private func item(title: String, scope: RecordRangeScope) -> NSMenuItem {
        let item = ExportMenuItem(title: title, scope: scope, handler: export)
        return item
    }
}

private final class ExportMenuItem: NSMenuItem {
    private let scope: RecordRangeScope
    private let handler: (RecordRangeScope) -> Void

    init(title: String, scope: RecordRangeScope, handler: @escaping (RecordRangeScope) -> Void) {
        self.scope = scope
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        scope = .all
        handler = { _ in }
        super.init(coder: coder)
        target = self
        action = #selector(run)
    }

    @objc private func run() {
        handler(scope)
    }
}
