import SwiftUI

struct FloatingBeaconView: View {
    @EnvironmentObject private var store: RecordStore

    private let panelSize: CGFloat = 74
    private let coreSize: CGFloat = 32
    private let ringStartSize: CGFloat = 68
    private let ringEndSize: CGFloat = 36

    private var theme: AppTheme { store.theme }
    private var proximity: CGFloat { min(max(store.beaconProximity, 0), 1) }

    private var stateColor: Color {
        if let hex = store.currentStateDefinition?.colorHex {
            return Color(hex: hex)
        }
        return theme.accentPrimary
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: proximity < 0.12)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            ZStack {
                rippleField(time: time)
                beaconCore
            }
            .frame(width: panelSize, height: panelSize)
            .compositingGroup()
        }
    }

    @ViewBuilder
    private func rippleField(time: TimeInterval) -> some View {
        ForEach(0..<3, id: \.self) { index in
            let intensity = ringIntensity(for: index)
            if intensity > 0.001 {
                rippleRing(index: index, time: time, intensity: intensity)
            }
        }
    }

    private var beaconCore: some View {
        let shellFill = theme.surface.mixed(with: theme.chrome, amount: 0.78)
        let innerTint = theme.surface.mixed(with: theme.panel, amount: 0.86)
        let shellStroke = theme.border.mixed(with: theme.surface, amount: 0.48)
        let accentStroke = theme.accentPrimary.mixed(with: theme.border, amount: 0.24)
        let lift = 1 + proximity * 0.045

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(shellFill.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.86),
                                    innerTint.opacity(0.16)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(shellStroke.opacity(0.96), lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accentStroke.opacity(0.12 + proximity * 0.18), lineWidth: 1)
                        .padding(0.5)
                }
                .shadow(color: theme.ink.opacity(0.10 + proximity * 0.08), radius: 12 + proximity * 6, y: 6)

            AccentControlView(
                theme: theme,
                frameSize: 20,
                showsHalo: false,
                usesArmedGradient: store.isArmed
            )
            .scaleEffect(0.94 + proximity * 0.06)

            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.94), lineWidth: 0.8)
                }
                .offset(x: 10, y: 10)
        }
        .frame(width: coreSize, height: coreSize)
        .scaleEffect(lift)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: proximity)
    }

    private func ringIntensity(for index: Int) -> CGFloat {
        let thresholds: [CGFloat] = [0.12, 0.42, 0.72]
        let ramp: CGFloat = 0.18
        let normalized = (proximity - thresholds[index]) / ramp
        return min(max(normalized, 0), 1)
    }

    private func rippleRing(index: Int, time: TimeInterval, intensity: CGFloat) -> some View {
        let phaseOffset = Double(index) * 0.23
        let speed = 0.52 + Double(proximity) * 0.56
        let phase = (time * speed + phaseOffset).truncatingRemainder(dividingBy: 1)
        let progress = CGFloat(phase)
        let envelope = CGFloat(max(0, sin(Double(progress) * .pi)))
        let sizeSpan = ringStartSize - ringEndSize - CGFloat(index) * 2.4
        let size = ringStartSize - progress * sizeSpan
        let lineWidth = 1.3 - CGFloat(index) * 0.14 + proximity * 0.16
        let alpha = Double((0.16 + proximity * 0.34) * intensity * envelope)
        let tint = index == 0
            ? theme.accentPrimary
            : theme.accentSecondary.mixed(with: theme.accentPrimary, amount: 0.46)

        return Circle()
            .stroke(tint.opacity(alpha), lineWidth: lineWidth)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(alpha * 0.36), lineWidth: max(0.6, lineWidth * 0.52))
                    .padding(1.2)
            }
            .blur(radius: (1 - progress) * 0.45)
    }
}
