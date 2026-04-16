import AppKit
import SwiftUI

enum AppearanceStyleID: String, Codable, CaseIterable, Identifiable {
    case classic
    case brush
    case editorial
    case signal
    case candy
    case stamp
    case glass

    var id: String { rawValue }
}

enum AppearancePaletteID: String, Codable, CaseIterable, Identifiable {
    case classic
    case amber
    case jade
    case berry
    case slate
    case ocean

    var id: String { rawValue }
}

struct AppearanceSelection: Codable, Equatable {
    var styleID: AppearanceStyleID = .classic
    var paletteID: AppearancePaletteID = .classic
    var beaconAnchor = BeaconAnchor()

    init(
        styleID: AppearanceStyleID = .classic,
        paletteID: AppearancePaletteID = .classic,
        beaconAnchor: BeaconAnchor = BeaconAnchor()
    ) {
        self.styleID = styleID
        self.paletteID = paletteID
        self.beaconAnchor = beaconAnchor
    }

    private enum CodingKeys: String, CodingKey {
        case styleID
        case paletteID
        case beaconAnchor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        styleID = try container.decodeIfPresent(AppearanceStyleID.self, forKey: .styleID) ?? .classic
        paletteID = try container.decodeIfPresent(AppearancePaletteID.self, forKey: .paletteID) ?? .classic
        beaconAnchor = try container.decodeIfPresent(BeaconAnchor.self, forKey: .beaconAnchor) ?? BeaconAnchor()
    }
}

struct BeaconAnchor: Codable, Equatable {
    var x: Double = 1
    var y: Double = 0.5

    init(x: Double = 1, y: Double = 0.5) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

enum AccentShapeKind: String {
    case circle
    case blob
    case pillar
    case octagon
    case pillow
    case stamp
    case capsule
}

enum StageBackdropKind: String {
    case classic
    case brush
    case editorial
    case signal
    case candy
    case stamp
    case glass
}

struct AppearanceStylePreset: Identifiable, Equatable {
    let id: AppearanceStyleID
    let name: String
    let subtitle: String
    let note: String
    let centerFontName: String
    let particlePrimaryFontName: String
    let particleSecondaryFontName: String
    let accentShape: AccentShapeKind
    let backdropKind: StageBackdropKind
    let controlWidthRatio: CGFloat
    let controlHeightRatio: CGFloat
    let controlRotation: Double
    let haloScale: CGFloat
    let shellCornerRadius: CGFloat
    let stageCornerRadius: CGFloat
    let surfaceCornerRadius: CGFloat
    let chipCornerRadius: CGFloat
    let utilityCornerRadius: CGFloat
}

struct AppearancePalettePreset: Identifiable, Equatable {
    let id: AppearancePaletteID
    let name: String
    let note: String
    let swatches: [String]
    let chromeHex: String
    let panelHex: String
    let surfaceHex: String
    let surfaceAltHex: String
    let borderHex: String
    let textHex: String
    let textMutedHex: String
    let textDimHex: String
    let inkHex: String
    let accentPrimaryHex: String
    let accentSecondaryHex: String
    let accentSoftHex: String
}

enum ThemeCatalog {
    static let styles: [AppearanceStylePreset] = [
        AppearanceStylePreset(
            id: .classic,
            name: "默认",
            subtitle: "原版克制",
            note: "保留现在这个干净版本。",
            centerFontName: "Kaiti SC",
            particlePrimaryFontName: "Kaiti SC",
            particleSecondaryFontName: "Songti SC",
            accentShape: .circle,
            backdropKind: .classic,
            controlWidthRatio: 0.76,
            controlHeightRatio: 0.76,
            controlRotation: 0,
            haloScale: 1.18,
            shellCornerRadius: 22,
            stageCornerRadius: 22,
            surfaceCornerRadius: 15,
            chipCornerRadius: 14,
            utilityCornerRadius: 12
        ),
        AppearanceStylePreset(
            id: .brush,
            name: "行笔",
            subtitle: "手写回弹",
            note: "偏手写，边缘更松。",
            centerFontName: "Kaiti SC",
            particlePrimaryFontName: "Kaiti SC",
            particleSecondaryFontName: "Songti SC",
            accentShape: .blob,
            backdropKind: .brush,
            controlWidthRatio: 0.82,
            controlHeightRatio: 0.68,
            controlRotation: -12,
            haloScale: 1.24,
            shellCornerRadius: 24,
            stageCornerRadius: 30,
            surfaceCornerRadius: 16,
            chipCornerRadius: 16,
            utilityCornerRadius: 13
        ),
        AppearanceStylePreset(
            id: .editorial,
            name: "刊影",
            subtitle: "海报升场",
            note: "对比更强，像社论标题。",
            centerFontName: "Songti SC",
            particlePrimaryFontName: "Songti SC",
            particleSecondaryFontName: "Kaiti SC",
            accentShape: .pillar,
            backdropKind: .editorial,
            controlWidthRatio: 0.58,
            controlHeightRatio: 0.88,
            controlRotation: 0,
            haloScale: 1.16,
            shellCornerRadius: 20,
            stageCornerRadius: 18,
            surfaceCornerRadius: 14,
            chipCornerRadius: 10,
            utilityCornerRadius: 10
        ),
        AppearanceStylePreset(
            id: .signal,
            name: "信号",
            subtitle: "冷光脉冲",
            note: "更系统化，更数字。",
            centerFontName: "PingFang SC",
            particlePrimaryFontName: "PingFang SC",
            particleSecondaryFontName: "Helvetica Neue",
            accentShape: .octagon,
            backdropKind: .signal,
            controlWidthRatio: 0.68,
            controlHeightRatio: 0.68,
            controlRotation: 0,
            haloScale: 1.18,
            shellCornerRadius: 20,
            stageCornerRadius: 16,
            surfaceCornerRadius: 12,
            chipCornerRadius: 12,
            utilityCornerRadius: 10
        ),
        AppearanceStylePreset(
            id: .candy,
            name: "糖丸",
            subtitle: "软弹泡字",
            note: "更轻松，线条更圆。",
            centerFontName: "PingFang SC",
            particlePrimaryFontName: "PingFang SC",
            particleSecondaryFontName: "Kaiti SC",
            accentShape: .pillow,
            backdropKind: .candy,
            controlWidthRatio: 0.76,
            controlHeightRatio: 0.76,
            controlRotation: -8,
            haloScale: 1.22,
            shellCornerRadius: 26,
            stageCornerRadius: 30,
            surfaceCornerRadius: 18,
            chipCornerRadius: 18,
            utilityCornerRadius: 14
        ),
        AppearanceStylePreset(
            id: .stamp,
            name: "印章",
            subtitle: "重压落印",
            note: "更厚重，确认感更强。",
            centerFontName: "PingFang SC",
            particlePrimaryFontName: "Songti SC",
            particleSecondaryFontName: "PingFang SC",
            accentShape: .stamp,
            backdropKind: .stamp,
            controlWidthRatio: 0.84,
            controlHeightRatio: 0.58,
            controlRotation: 0,
            haloScale: 1.14,
            shellCornerRadius: 18,
            stageCornerRadius: 18,
            surfaceCornerRadius: 13,
            chipCornerRadius: 12,
            utilityCornerRadius: 10
        ),
        AppearanceStylePreset(
            id: .glass,
            name: "玻璃",
            subtitle: "液态浮层",
            note: "偏 iOS 材质感。",
            centerFontName: "SF Pro Display",
            particlePrimaryFontName: "SF Pro Display",
            particleSecondaryFontName: "PingFang SC",
            accentShape: .capsule,
            backdropKind: .glass,
            controlWidthRatio: 0.9,
            controlHeightRatio: 0.5,
            controlRotation: 0,
            haloScale: 1.16,
            shellCornerRadius: 24,
            stageCornerRadius: 26,
            surfaceCornerRadius: 16,
            chipCornerRadius: 16,
            utilityCornerRadius: 14
        ),
    ]

    static let palettes: [AppearancePalettePreset] = [
        AppearancePalettePreset(
            id: .classic,
            name: "原版奶油",
            note: "现在这套中性色。",
            swatches: ["#d89b4d", "#76b59d", "#d3dae3"],
            chromeHex: "#edf1f5",
            panelHex: "#f8f4ec",
            surfaceHex: "#ffffff",
            surfaceAltHex: "#eef2f6",
            borderHex: "#d3dae3",
            textHex: "#18212b",
            textMutedHex: "#415161",
            textDimHex: "#748395",
            inkHex: "#0f1720",
            accentPrimaryHex: "#d89b4d",
            accentSecondaryHex: "#76b59d",
            accentSoftHex: "#eef2f6"
        ),
        AppearancePalettePreset(
            id: .amber,
            name: "琥珀暖墨",
            note: "暖白、琥珀、赤陶。",
            swatches: ["#f3be6d", "#eb7b42", "#c44637"],
            chromeHex: "#f5efe6",
            panelHex: "#f8f1e7",
            surfaceHex: "#fffdfa",
            surfaceAltHex: "#f4eadb",
            borderHex: "#e1d5c1",
            textHex: "#211d1a",
            textMutedHex: "#625446",
            textDimHex: "#907f70",
            inkHex: "#1b1612",
            accentPrimaryHex: "#eb7b42",
            accentSecondaryHex: "#c44637",
            accentSoftHex: "#f3be6d"
        ),
        AppearancePalettePreset(
            id: .jade,
            name: "雾玉冷山",
            note: "冷灰绿和浅雾青。",
            swatches: ["#c5ebe1", "#5db0a1", "#1d6662"],
            chromeHex: "#edf3f0",
            panelHex: "#eff7f3",
            surfaceHex: "#fbfefd",
            surfaceAltHex: "#e1efea",
            borderHex: "#cbddd6",
            textHex: "#17211f",
            textMutedHex: "#45605a",
            textDimHex: "#748a84",
            inkHex: "#11201c",
            accentPrimaryHex: "#4aa99b",
            accentSecondaryHex: "#1f7068",
            accentSoftHex: "#bfe7d8"
        ),
        AppearancePalettePreset(
            id: .berry,
            name: "莓夜霞光",
            note: "浅粉雾底配浆果红。",
            swatches: ["#ffd2cc", "#ef7d82", "#be4669"],
            chromeHex: "#f7eeef",
            panelHex: "#fbf1f2",
            surfaceHex: "#fffdfd",
            surfaceAltHex: "#f7e4e7",
            borderHex: "#e7cfd7",
            textHex: "#25171d",
            textMutedHex: "#6d4b56",
            textDimHex: "#957480",
            inkHex: "#1f1218",
            accentPrimaryHex: "#ef7d82",
            accentSecondaryHex: "#be4669",
            accentSoftHex: "#ffd2cc"
        ),
        AppearancePalettePreset(
            id: .slate,
            name: "石墨冷银",
            note: "冷灰、银白、深炭。",
            swatches: ["#cfd6de", "#6f8396", "#1f2831"],
            chromeHex: "#eef1f4",
            panelHex: "#f5f7f9",
            surfaceHex: "#ffffff",
            surfaceAltHex: "#e7edf3",
            borderHex: "#d4dde6",
            textHex: "#182028",
            textMutedHex: "#495764",
            textDimHex: "#7b8897",
            inkHex: "#121a22",
            accentPrimaryHex: "#7b8fa3",
            accentSecondaryHex: "#27313a",
            accentSoftHex: "#d7dee6"
        ),
        AppearancePalettePreset(
            id: .ocean,
            name: "深海电蓝",
            note: "更冷、更锐。",
            swatches: ["#9ce8ff", "#3caed7", "#114e78"],
            chromeHex: "#edf5f8",
            panelHex: "#eff8fb",
            surfaceHex: "#fbfeff",
            surfaceAltHex: "#e0eef5",
            borderHex: "#cae0ea",
            textHex: "#13212b",
            textMutedHex: "#456272",
            textDimHex: "#7591a2",
            inkHex: "#0f1720",
            accentPrimaryHex: "#3caed7",
            accentSecondaryHex: "#15597f",
            accentSoftHex: "#98e4f7"
        ),
    ]

    static func style(for id: AppearanceStyleID) -> AppearanceStylePreset {
        styles.first(where: { $0.id == id }) ?? styles[0]
    }

    static func palette(for id: AppearancePaletteID) -> AppearancePalettePreset {
        palettes.first(where: { $0.id == id }) ?? palettes[0]
    }

    static func theme(styleID: AppearanceStyleID, paletteID: AppearancePaletteID) -> AppTheme {
        AppTheme(style: style(for: styleID), palette: palette(for: paletteID))
    }
}

struct AppTheme {
    let style: AppearanceStylePreset
    let palette: AppearancePalettePreset

    var chrome: Color { Color(hex: palette.chromeHex) }
    var panel: Color { Color(hex: palette.panelHex) }
    var surface: Color { Color(hex: palette.surfaceHex) }
    var surfaceAlt: Color { Color(hex: palette.surfaceAltHex) }
    var border: Color { Color(hex: palette.borderHex) }
    var text: Color { Color(hex: palette.textHex) }
    var textMuted: Color { Color(hex: palette.textMutedHex) }
    var textDim: Color { Color(hex: palette.textDimHex) }
    var ink: Color { Color(hex: palette.inkHex) }
    var accentPrimary: Color { Color(hex: palette.accentPrimaryHex) }
    var accentSecondary: Color { Color(hex: palette.accentSecondaryHex) }
    var accentSoft: Color { Color(hex: palette.accentSoftHex) }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentSoft, accentPrimary, accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var armedGradient: LinearGradient {
        LinearGradient(
            colors: [accentSoft.opacity(0.88), accentSecondary, accentPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var shellGradient: LinearGradient {
        LinearGradient(
            colors: [chrome.opacity(0.98), panel.opacity(0.98)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var stageGradient: LinearGradient {
        LinearGradient(
            colors: [surface.opacity(0.96), accentSoft.opacity(0.22), panel.opacity(0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var stageStroke: Color {
        border.opacity(style.id == .signal ? 0.72 : 0.92)
    }

    var floatingShadow: Color {
        accentSecondary.opacity(style.id == .glass ? 0.16 : 0.22)
    }

    func stateEdge(_ hex: String) -> Color {
        let base = NSColor(hex: hex) ?? .systemBlue
        let background = NSColor(hex: palette.surfaceHex) ?? .white
        return Color(nsColor: base.mixed(with: background, ratio: 0.44))
    }

    func stateFill(_ hex: String, enabled: Bool, selected: Bool) -> Color {
        let base = NSColor(hex: hex) ?? .systemBlue
        let surface = NSColor(hex: palette.surfaceHex) ?? .white
        let panel = NSColor(hex: palette.panelHex) ?? .white
        if enabled {
            return Color(nsColor: base.mixed(with: surface, ratio: 0.22))
        }
        if selected {
            return Color(nsColor: base.mixed(with: surface, ratio: 0.15))
        }
        return Color(nsColor: base.mixed(with: panel, ratio: 0.08))
    }

    func stateText(on hex: String, enabled: Bool, selected: Bool) -> Color {
        if !enabled && !selected {
            return textDim
        }

        let base = NSColor(hex: hex) ?? .systemBlue
        let background: NSColor
        let surface = NSColor(hex: palette.surfaceHex) ?? .white
        if enabled {
            background = base.mixed(with: surface, ratio: 0.22)
        } else {
            background = base.mixed(with: surface, ratio: 0.15)
        }

        let light = NSColor(hex: palette.textHex) ?? .black
        let dark = NSColor(hex: palette.inkHex) ?? .black
        let chosen = background.contrastRatio(to: light) >= background.contrastRatio(to: dark) ? light : dark
        return Color(nsColor: chosen)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .systemBlue)
    }

    func mixed(with other: Color, amount: CGFloat) -> Color {
        let left = NSColor(self)
        let right = NSColor(other)
        return Color(nsColor: left.mixed(with: right, ratio: amount))
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func mixed(with other: NSColor, ratio: CGFloat) -> NSColor {
        let clamped = max(0, min(1, ratio))
        let a = usingColorSpace(.deviceRGB) ?? self
        let b = other.usingColorSpace(.deviceRGB) ?? other

        return NSColor(
            red: a.redComponent * clamped + b.redComponent * (1 - clamped),
            green: a.greenComponent * clamped + b.greenComponent * (1 - clamped),
            blue: a.blueComponent * clamped + b.blueComponent * (1 - clamped),
            alpha: 1
        )
    }

    func contrastRatio(to other: NSColor) -> CGFloat {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: CGFloat {
        let rgb = usingColorSpace(.deviceRGB) ?? self
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { channel -> CGFloat in
            if channel <= 0.03928 {
                return channel / 12.92
            }
            return pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
