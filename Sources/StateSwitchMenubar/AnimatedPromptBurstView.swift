import SwiftUI

struct PromptBurstPayload {
    let centerText: String
    let particles: [String]
}

struct AnimatedPromptBurstView: View {
    let payload: PromptBurstPayload
    let theme: AppTheme
    @State private var progress: CGFloat = 0

    var body: some View {
        let exit = exitProgress(from: progress, start: 0.58)

        ZStack {
            burstBackdrop(exit: exit)

            ForEach(Array(payload.particles.enumerated()), id: \.offset) { index, word in
                particle(word: word, index: index)
            }

            ZStack {
                AccentControlView(
                    theme: theme,
                    frameSize: 140,
                    showsHalo: true,
                    usesArmedGradient: true,
                    pulseScale: 1.02 + 0.14 * progress + 0.08 * exit,
                    outerOpacity: Double(1 - 0.12 * exit)
                )
                .scaleEffect(0.94 + 0.12 * progress + 0.08 * exit)
                .opacity(Double(1 - 0.24 * exit))

                Text(payload.centerText)
                    .font(.custom(theme.style.centerFontName, size: theme.style.id == .editorial ? 40 : 34))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.ink)
                    .lineSpacing(theme.style.id == .editorial ? 0 : 4)
                    .shadow(color: Color.white.opacity(0.24), radius: 10, y: 0)
                    .shadow(color: theme.accentSoft.opacity(0.4), radius: 18, y: 0)
                    .padding(.horizontal, 12)
                    .scaleEffect(centerScale)
                    .opacity(Double(max(0, 1 - exit * 1.24)))
                    .offset(y: -4 * progress)
                    .blur(radius: 3.6 * exit)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .onAppear {
            startAnimation()
        }
    }

    private var centerScale: CGFloat {
        switch theme.style.id {
        case .brush:
            return 0.82 + 0.22 * progress + 0.24 * exitProgress(from: progress, start: 0.58)
        case .editorial:
            return 0.88 + 0.18 * progress
        case .signal:
            return 0.8 + 0.24 * progress
        case .candy:
            return 0.78 + 0.28 * progress
        case .stamp:
            return 0.86 + 0.18 * progress
        case .glass:
            return 0.9 + 0.14 * progress
        case .classic:
            return 0.84 + 0.18 * progress
        }
    }

    private func particle(word: String, index: Int) -> some View {
        let offset = particleOffset(for: index, total: max(payload.particles.count, 1))
        let localProgress = stagedProgress(for: index)
        let exit = exitProgress(from: localProgress, start: 0.62)
        let opacity = max(0, sin(Double(localProgress * .pi))) * Double(1 - exit)
        let fontSize = particleFontSize(for: index)
        let rotation = particleRotation(for: index, localProgress: localProgress)
        let particleFont = index.isMultiple(of: 2) ? theme.style.particlePrimaryFontName : theme.style.particleSecondaryFontName
        let particleColor = index.isMultiple(of: 2) ? theme.accentSecondary : theme.accentPrimary

        return Text(word)
            .font(.custom(particleFont, size: fontSize))
            .foregroundStyle(particleColor)
            .opacity(opacity)
            .shadow(color: Color.white.opacity(0.18), radius: 6, y: 0)
            .shadow(color: particleColor.opacity(0.26), radius: 12, y: 0)
            .scaleEffect(0.64 + 0.98 * localProgress + 0.12 * exit)
            .rotationEffect(.degrees(rotation))
            .offset(x: offset.width * localProgress, y: offset.height * localProgress - 6 * localProgress)
            .blur(radius: 2.4 * exit)
    }

    private func particleFontSize(for index: Int) -> CGFloat {
        switch theme.style.id {
        case .editorial:
            return 18 + CGFloat(index % 2) * 3
        case .signal:
            return 15 + CGFloat(index % 2) * 2
        case .candy:
            return 19 + CGFloat(index % 3) * 2
        case .stamp:
            return 17 + CGFloat(index % 3)
        case .glass:
            return 16 + CGFloat(index % 2) * 2
        default:
            return 17 + CGFloat(index % 3) * 2
        }
    }

    private func particleRotation(for index: Int, localProgress: CGFloat) -> Double {
        switch theme.style.id {
        case .editorial:
            return Double(-10 + index * 3) * Double(localProgress)
        case .signal:
            return Double(index.isMultiple(of: 2) ? -4 : 4) * Double(localProgress)
        case .stamp:
            return Double(index.isMultiple(of: 2) ? -8 : 8) * Double(localProgress)
        case .glass:
            return Double(index.isMultiple(of: 2) ? -6 : 6) * Double(localProgress)
        default:
            return Double(index.isMultiple(of: 2) ? 1 : -1) * Double(14 * localProgress)
        }
    }

    private func particleOffset(for index: Int, total: Int) -> CGSize {
        let angle = CGFloat(index) / CGFloat(total) * .pi * 2 - .pi / 2

        switch theme.style.id {
        case .classic:
            return CGSize(width: cos(angle) * 132, height: sin(angle) * 96)
        case .brush:
            return CGSize(width: cos(angle) * 142, height: sin(angle) * 108)
        case .editorial:
            return CGSize(width: -152 + CGFloat(index) * 54, height: -98 + CGFloat(index) * 30)
        case .signal:
            let grid = [
                CGSize(width: -132, height: -22),
                CGSize(width: 0, height: -108),
                CGSize(width: 132, height: -22),
                CGSize(width: -96, height: 88),
                CGSize(width: 0, height: 122),
                CGSize(width: 96, height: 88),
            ]
            return grid[index % grid.count]
        case .candy:
            return CGSize(width: cos(angle) * (116 + CGFloat(index % 2) * 22), height: sin(angle) * (90 + CGFloat(index % 3) * 14))
        case .stamp:
            let cross = [
                CGSize(width: 0, height: -112),
                CGSize(width: 132, height: -20),
                CGSize(width: 96, height: 96),
                CGSize(width: 0, height: 122),
                CGSize(width: -96, height: 96),
                CGSize(width: -132, height: -20),
            ]
            return cross[index % cross.count]
        case .glass:
            let arc = [
                CGSize(width: -118, height: -60),
                CGSize(width: 0, height: -114),
                CGSize(width: 118, height: -60),
                CGSize(width: -92, height: 88),
                CGSize(width: 0, height: 114),
                CGSize(width: 92, height: 88),
            ]
            return arc[index % arc.count]
        }
    }

    private func stagedProgress(for index: Int) -> CGFloat {
        let delay = CGFloat(index) * 0.055
        let normalized = (progress - delay) / max(0.25, 1 - delay)
        return min(max(normalized, 0), 1)
    }

    private func exitProgress(from value: CGFloat, start: CGFloat) -> CGFloat {
        guard value > start else {
            return 0
        }
        let normalized = (value - start) / max(0.001, 1 - start)
        return min(max(normalized, 0), 1)
    }

    @ViewBuilder
    private func burstBackdrop(exit: CGFloat) -> some View {
        Circle()
            .fill(theme.accentSoft.opacity(0.18 * (1 - exit)))
            .frame(width: 142 + progress * 82, height: 142 + progress * 82)
            .blur(radius: 18)
            .scaleEffect(0.82 + 0.24 * progress)

        Circle()
            .stroke(theme.accentPrimary.opacity(0.36 * (1 - exit)), lineWidth: 1.6)
            .frame(width: 124 + progress * 94, height: 124 + progress * 94)
            .scaleEffect(0.9 + 0.16 * progress)

        Circle()
            .stroke(Color.white.opacity(0.22 * (1 - exit)), lineWidth: 1)
            .frame(width: 96 + progress * 54, height: 96 + progress * 54)
    }

    private func startAnimation() {
        progress = 0
        withAnimation(.easeOut(duration: 1.22)) {
            progress = 1
        }
    }
}
