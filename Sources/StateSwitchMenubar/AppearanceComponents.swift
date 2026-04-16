import SwiftUI

struct PresetShape: InsettableShape {
    let kind: AccentShapeKind
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch kind {
        case .circle:
            return Circle().path(in: rect)
        case .blob:
            return blobPath(in: rect)
        case .pillar:
            return RoundedRectangle(cornerRadius: rect.width * 0.26, style: .continuous).path(in: rect)
        case .octagon:
            return octagonPath(in: rect)
        case .pillow:
            return RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous).path(in: rect)
        case .stamp:
            return RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.24, style: .continuous).path(in: rect)
        case .capsule:
            return Capsule().path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    private func octagonPath(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        path.closeSubpath()
        return path
    }

    private func blobPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.30))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.10),
            control1: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.00)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.46),
            control1: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.06),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY - rect.height * 0.14),
            control1: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.maxY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.30),
            control1: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.maxY - rect.height * 0.24),
            control2: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.48)
        )
        path.closeSubpath()
        return path
    }
}

struct AccentControlView: View {
    let theme: AppTheme
    var frameSize: CGFloat
    var showsHalo: Bool = true
    var usesArmedGradient: Bool = false
    var pulseScale: CGFloat = 1
    var outerOpacity: Double = 1

    private var shape: PresetShape {
        PresetShape(kind: theme.style.accentShape)
    }

    private var controlWidth: CGFloat {
        frameSize * theme.style.controlWidthRatio
    }

    private var controlHeight: CGFloat {
        frameSize * theme.style.controlHeightRatio
    }

    var body: some View {
        ZStack {
            if showsHalo {
                shape
                    .stroke(theme.accentPrimary.opacity(theme.style.id == .signal ? 0.26 : 0.18), lineWidth: theme.style.id == .signal ? 1.2 : 1.8)
                    .frame(width: controlWidth, height: controlHeight)
                    .scaleEffect(theme.style.haloScale * pulseScale)
                    .opacity(theme.style.id == .glass ? 0.7 : 1)
            }

            shape
                .fill(usesArmedGradient ? theme.armedGradient : theme.accentGradient)
                .frame(width: controlWidth, height: controlHeight)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(theme.style.id == .signal ? 0.44 : 0.92), lineWidth: theme.style.id == .signal ? 1.1 : 1.8)
                }
                .shadow(color: theme.floatingShadow, radius: theme.style.id == .glass ? 18 : 14, y: 8)
                .overlay {
                    if theme.style.id == .glass {
                        shape
                            .fill(Color.white.opacity(0.14))
                            .frame(width: controlWidth * 0.88, height: controlHeight * 0.86)
                    }
                }

            Circle()
                .fill(theme.ink.opacity(0.88))
                .frame(width: max(12, frameSize * 0.12), height: max(12, frameSize * 0.12))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
        }
        .rotationEffect(.degrees(theme.style.controlRotation))
        .opacity(outerOpacity)
        .frame(width: frameSize, height: frameSize)
    }
}

struct StageBackdropView: View {
    let theme: AppTheme
    var compact: Bool = false

    private var glowOpacity: Double { compact ? 0.12 : 0.18 }
    private var lineOpacity: Double { compact ? 0.12 : 0.18 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                theme.stageGradient

                switch theme.style.backdropKind {
                case .classic:
                    classicBackdrop(size: size)
                case .brush:
                    brushBackdrop(size: size)
                case .editorial:
                    editorialBackdrop(size: size)
                case .signal:
                    signalBackdrop(size: size)
                case .candy:
                    candyBackdrop(size: size)
                case .stamp:
                    stampBackdrop(size: size)
                case .glass:
                    glassBackdrop(size: size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.style.stageCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.style.stageCornerRadius, style: .continuous)
                    .stroke(theme.stageStroke, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func classicBackdrop(size: CGSize) -> some View {
        Circle()
            .fill(theme.accentSoft.opacity(glowOpacity))
            .frame(width: size.width * 0.56)
            .offset(x: -size.width * 0.16, y: -size.height * 0.08)

        Circle()
            .stroke(Color.white.opacity(0.42), lineWidth: 1)
            .frame(width: size.width * 0.40)
            .offset(x: -size.width * 0.12, y: -size.height * 0.02)
    }

    @ViewBuilder
    private func brushBackdrop(size: CGSize) -> some View {
        Circle()
            .fill(theme.accentSoft.opacity(glowOpacity * 1.2))
            .frame(width: size.width * 0.48)
            .offset(x: -size.width * 0.18, y: -size.height * 0.02)

        Circle()
            .stroke(Color.white.opacity(0.34), lineWidth: 1)
            .frame(width: size.width * 0.34)
            .offset(x: -size.width * 0.22, y: -size.height * 0.04)

        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: size.width * 0.24, height: size.height * 1.2)
            .rotationEffect(.degrees(28))
            .offset(x: -size.width * 0.30)
    }

    @ViewBuilder
    private func editorialBackdrop(size: CGSize) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.64))
            .frame(width: size.width * 0.34)
            .frame(maxHeight: .infinity, alignment: .leading)
            .offset(x: -size.width * 0.33)

        Rectangle()
            .fill(theme.accentPrimary.opacity(0.10))
            .frame(width: 10)
            .frame(maxHeight: .infinity)
            .offset(x: size.width * 0.16)

        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color.white.opacity(0.46), lineWidth: 1)
            .frame(width: size.width * 0.32, height: size.height * 0.78)
            .rotationEffect(.degrees(7))
            .offset(x: size.width * 0.24, y: size.height * 0.02)
    }

    @ViewBuilder
    private func signalBackdrop(size: CGSize) -> some View {
        ForEach(0..<6, id: \.self) { index in
            Rectangle()
                .fill(theme.accentPrimary.opacity(index.isMultiple(of: 3) ? 0.08 : 0.04))
                .frame(height: 1)
                .offset(y: CGFloat(index) * 26 - size.height * 0.3)
        }

        ForEach(0..<5, id: \.self) { index in
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .offset(x: CGFloat(index) * 46 - size.width * 0.18)
        }

        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(theme.accentPrimary.opacity(0.16), lineWidth: 1)
            .frame(width: size.width * 0.42, height: size.height * 0.44)
            .rotationEffect(.degrees(12))
            .offset(x: size.width * 0.22, y: size.height * 0.04)

        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(theme.accentPrimary.opacity(0.12), lineWidth: 1)
            .frame(width: size.width * 0.38, height: size.height * 0.38)
            .rotationEffect(.degrees(-12))
            .offset(x: -size.width * 0.18, y: -size.height * 0.10)
    }

    @ViewBuilder
    private func candyBackdrop(size: CGSize) -> some View {
        Circle()
            .fill(theme.accentSoft.opacity(glowOpacity))
            .frame(width: size.width * 0.30)
            .offset(x: -size.width * 0.10, y: size.height * 0.10)

        Circle()
            .stroke(Color.white.opacity(0.34), lineWidth: 1)
            .frame(width: size.width * 0.24)
            .offset(x: size.width * 0.18, y: -size.height * 0.10)

        Circle()
            .fill(theme.accentPrimary.opacity(0.08))
            .frame(width: size.width * 0.20)
            .offset(x: size.width * 0.16, y: size.height * 0.18)
    }

    @ViewBuilder
    private func stampBackdrop(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: theme.style.stageCornerRadius + 8, style: .continuous)
            .stroke(Color.white.opacity(0.36), lineWidth: compact ? 8 : 14)
            .padding(compact ? 10 : 18)

        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(theme.ink.opacity(0.04), lineWidth: 1)
            .frame(width: size.width * 0.72, height: size.height * 0.48)
    }

    @ViewBuilder
    private func glassBackdrop(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .frame(width: size.width * 0.40, height: size.height * 0.42)
            .blur(radius: compact ? 0 : 0.2)
            .offset(x: -size.width * 0.14, y: -size.height * 0.12)

        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: size.width * 0.46, height: size.height * 0.46)
            .rotationEffect(.degrees(14))
            .offset(x: size.width * 0.22, y: size.height * 0.08)

        Circle()
            .fill(theme.accentSoft.opacity(lineOpacity))
            .frame(width: size.width * 0.34)
            .blur(radius: compact ? 8 : 18)
    }
}
