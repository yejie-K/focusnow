import SwiftUI

struct FlipClockView: View {
    let date: Date
    let theme: AppTheme

    private var symbols: [String] {
        Self.timeFormatter.string(from: date).map(String.init)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                if symbol == ":" {
                    Text(symbol)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 6)
                        .offset(y: -1)
                } else {
                    FlipDigitCard(value: symbol, theme: theme)
                }
            }
        }
        .accessibilityLabel(Self.accessibilityFormatter.string(from: date))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    private static let accessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH 点 mm 分 ss 秒"
        formatter.timeZone = .current
        return formatter
    }()
}

private struct FlipDigitCard: View {
    let value: String
    let theme: AppTheme

    @State private var displayedValue: String
    @State private var previousValue: String
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 90
    @State private var isAnimating = false
    @State private var animationToken = UUID()

    init(value: String, theme: AppTheme) {
        self.value = value
        self.theme = theme
        _displayedValue = State(initialValue: value)
        _previousValue = State(initialValue: value)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private let cardWidth: CGFloat = 25
    private let cardHeight: CGFloat = 34
    private let halfHeight: CGFloat = 17

    var body: some View {
        ZStack {
            staticCard(
                topValue: displayedValue,
                bottomValue: isAnimating ? previousValue : displayedValue
            )

            if isAnimating {
                DigitHalfFace(value: previousValue, theme: theme, isTop: true)
                    .rotation3DEffect(
                        .degrees(topAngle),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .bottom,
                        perspective: 0.6
                    )
                    .frame(height: halfHeight, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .zIndex(2)

                DigitHalfFace(value: displayedValue, theme: theme, isTop: false)
                    .rotation3DEffect(
                        .degrees(bottomAngle),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .top,
                        perspective: 0.6
                    )
                    .frame(height: halfHeight, alignment: .bottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipped()
                    .zIndex(1)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(cardShape)
        .compositingGroup()
        .onChange(of: value) { newValue in
            triggerFlip(to: newValue)
        }
    }

    @ViewBuilder
    private func staticCard(topValue: String, bottomValue: String) -> some View {
        VStack(spacing: 0) {
            DigitHalfFace(value: topValue, theme: theme, isTop: true)
            DigitHalfFace(value: bottomValue, theme: theme, isTop: false)
        }
        .background(
            cardShape
                .fill(theme.surface)
                .overlay(
                    cardShape
                        .stroke(theme.border.opacity(0.92), lineWidth: 1)
                )
        )
        .overlay(alignment: .center) {
            Rectangle()
                .fill(theme.ink.opacity(0.06))
                .frame(height: 1)
        }
        .shadow(color: theme.ink.opacity(0.05), radius: 6, y: 2)
        .clipShape(cardShape)
    }

    private func triggerFlip(to newValue: String) {
        guard newValue != displayedValue else {
            return
        }

        let token = UUID()
        animationToken = token
        previousValue = displayedValue
        displayedValue = newValue
        isAnimating = true
        topAngle = 0
        bottomAngle = 90

        withAnimation(.timingCurve(0.22, 0.86, 0.34, 1, duration: 0.24)) {
            topAngle = -90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard animationToken == token else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
                bottomAngle = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard animationToken == token else { return }
            isAnimating = false
            topAngle = 0
            bottomAngle = 90
        }
    }
}

private struct DigitHalfFace: View {
    let value: String
    let theme: AppTheme
    let isTop: Bool

    private let cardHeight: CGFloat = 34
    private let halfHeight: CGFloat = 17

    var body: some View {
        ZStack(alignment: isTop ? .top : .bottom) {
            Rectangle()
                .fill(isTop ? theme.surface : theme.surfaceAlt.opacity(0.92))

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight)
                .offset(y: isTop ? halfHeight / 2 : -halfHeight / 2)
        }
        .overlay(alignment: isTop ? .bottom : .top) {
            LinearGradient(
                colors: isTop
                    ? [Color.clear, theme.ink.opacity(0.06)]
                    : [theme.ink.opacity(0.08), Color.clear],
                startPoint: isTop ? .top : .bottom,
                endPoint: isTop ? .bottom : .top
            )
            .frame(height: 7)
        }
        .frame(height: halfHeight)
        .clipped()
    }
}
