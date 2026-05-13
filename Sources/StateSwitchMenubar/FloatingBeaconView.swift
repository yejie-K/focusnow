import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class BeaconInteractionState: ObservableObject {
    @Published private(set) var proximity: CGFloat = 0

    private let publishThreshold: CGFloat = 0.006

    func setProximity(_ value: CGFloat) {
        let next = min(max(value, 0), 1)
        let reachesBoundary = (next == 0 && proximity != 0) || (next == 1 && proximity != 1)
        guard reachesBoundary || abs(next - proximity) >= publishThreshold else {
            return
        }

        proximity = next
    }
}

struct FloatingBeaconView: View {
    @EnvironmentObject private var store: RecordStore
    @ObservedObject var beaconState: BeaconInteractionState

    private let panelSize: CGFloat = 74
    private let coreSize: CGFloat = 32
    private let ringStartSize: CGFloat = 68
    private let ringEndSize: CGFloat = 36

    private var theme: AppTheme { store.theme }
    private var proximity: CGFloat { beaconState.proximity }

    private var stateColor: Color {
        if let hex = store.currentStateDefinition?.colorHex {
            return Color(hex: hex)
        }
        return theme.accentPrimary
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: proximity < 0.12)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let countdownProgress = autoSwitchCountdownProgress(at: context.date)
            let countdownStyle = store.automationSettings.autoSwitch.countdownStyle

            ZStack {
                rippleField(time: time)
                beaconCore()
                countdownProgressIndicator(style: countdownStyle, progress: countdownProgress)
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

    private func beaconCore() -> some View {
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

    private func autoSwitchCountdownProgress(at date: Date) -> CGFloat? {
        guard store.automationSettings.autoSwitch.isEnabled,
              store.automationSettings.autoSwitch.countdownStyle != .off,
              let candidate = store.autoSwitchCandidate else {
            return nil
        }

        let settleSeconds = max(store.automationSettings.autoSwitch.settleSeconds, 1)
        let elapsed = date.timeIntervalSince(candidate.firstSeenAt)
        return min(max(CGFloat(elapsed / Double(settleSeconds)), 0), 1)
    }

    @ViewBuilder
    private func countdownProgressIndicator(style: AutoSwitchCountdownStyle, progress: CGFloat?) -> some View {
        if progress != nil {
            switch style {
            case .bar:
                if let candidate = store.autoSwitchCandidate {
                    SmoothCountdownBarView(
                        candidate: candidate,
                        settleSeconds: store.automationSettings.autoSwitch.settleSeconds,
                        theme: theme
                    )
                }
            case .ring:
                if let candidate = store.autoSwitchCandidate {
                    SmoothCountdownRingView(
                        candidate: candidate,
                        settleSeconds: store.automationSettings.autoSwitch.settleSeconds,
                        theme: theme
                    )
                }
            case .fill:
                if let candidate = store.autoSwitchCandidate {
                    SmoothCountdownFillView(
                        candidate: candidate,
                        settleSeconds: store.automationSettings.autoSwitch.settleSeconds,
                        theme: theme,
                        size: coreSize
                    )
                }
            case .off:
                EmptyView()
            }
        }
    }

}

private struct SmoothCountdownBarView: View {
    let candidate: AutoSwitchCandidate
    let settleSeconds: Int
    let theme: AppTheme

    var body: some View {
        LayerBackedCountdownBar(
            candidateID: candidate.id,
            firstSeenAt: candidate.firstSeenAt,
            settleSeconds: settleSeconds,
            trackHex: theme.palette.inkHex,
            accentStartHex: theme.palette.accentSecondaryHex,
            accentEndHex: theme.palette.accentPrimaryHex
        )
        .frame(width: 34, height: 3.5)
        .offset(y: 24)
    }
}

private struct SmoothCountdownFillView: View {
    let candidate: AutoSwitchCandidate
    let settleSeconds: Int
    let theme: AppTheme
    let size: CGFloat

    var body: some View {
        LayerBackedWaveFill(
            candidateID: candidate.id,
            firstSeenAt: candidate.firstSeenAt,
            settleSeconds: settleSeconds,
            backgroundHex: theme.palette.inkHex,
            accentStartHex: theme.palette.accentSecondaryHex,
            accentEndHex: theme.palette.accentPrimaryHex,
            size: size
        )
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

private struct SmoothCountdownRingView: View {
    let candidate: AutoSwitchCandidate
    let settleSeconds: Int
    let theme: AppTheme

    var body: some View {
        LayerBackedCountdownRing(
            candidateID: candidate.id,
            firstSeenAt: candidate.firstSeenAt,
            settleSeconds: settleSeconds,
            trackHex: theme.palette.inkHex,
            accentStartHex: theme.palette.accentSecondaryHex,
            accentEndHex: theme.palette.accentPrimaryHex
        )
        .frame(width: 44, height: 44)
    }
}

private struct LayerBackedCountdownRing: NSViewRepresentable {
    let candidateID: String
    let firstSeenAt: Date
    let settleSeconds: Int
    let trackHex: String
    let accentStartHex: String
    let accentEndHex: String

    func makeNSView(context: Context) -> CountdownRingLayerView {
        CountdownRingLayerView()
    }

    func updateNSView(_ nsView: CountdownRingLayerView, context: Context) {
        nsView.configure(
            candidateID: candidateID,
            firstSeenAt: firstSeenAt,
            settleSeconds: settleSeconds,
            trackColor: NSColor(hex: trackHex) ?? .black,
            accentStart: NSColor(hex: accentStartHex) ?? .systemTeal,
            accentEnd: NSColor(hex: accentEndHex) ?? .systemOrange
        )
    }
}

private struct LayerBackedCountdownBar: NSViewRepresentable {
    let candidateID: String
    let firstSeenAt: Date
    let settleSeconds: Int
    let trackHex: String
    let accentStartHex: String
    let accentEndHex: String

    func makeNSView(context: Context) -> CountdownBarLayerView {
        CountdownBarLayerView()
    }

    func updateNSView(_ nsView: CountdownBarLayerView, context: Context) {
        nsView.configure(
            candidateID: candidateID,
            firstSeenAt: firstSeenAt,
            settleSeconds: settleSeconds,
            trackColor: NSColor(hex: trackHex) ?? .black,
            accentStart: NSColor(hex: accentStartHex) ?? .systemTeal,
            accentEnd: NSColor(hex: accentEndHex) ?? .systemOrange
        )
    }
}

private struct LayerBackedWaveFill: NSViewRepresentable {
    let candidateID: String
    let firstSeenAt: Date
    let settleSeconds: Int
    let backgroundHex: String
    let accentStartHex: String
    let accentEndHex: String
    let size: CGFloat

    func makeNSView(context: Context) -> WaveFillLayerView {
        WaveFillLayerView()
    }

    func updateNSView(_ nsView: WaveFillLayerView, context: Context) {
        nsView.configure(
            candidateID: candidateID,
            firstSeenAt: firstSeenAt,
            settleSeconds: settleSeconds,
            backgroundColor: NSColor(hex: backgroundHex) ?? .black,
            accentStart: NSColor(hex: accentStartHex) ?? .systemTeal,
            accentEnd: NSColor(hex: accentEndHex) ?? .systemOrange
        )
    }
}

@MainActor
private final class CountdownRingLayerView: NSView {
    private let trackLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let progressMaskLayer = CAShapeLayer()
    private var animationKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    func configure(
        candidateID: String,
        firstSeenAt: Date,
        settleSeconds: Int,
        trackColor: NSColor,
        accentStart: NSColor,
        accentEnd: NSColor
    ) {
        trackLayer.strokeColor = trackColor.withAlphaComponent(0.08).cgColor
        gradientLayer.colors = [
            accentStart.cgColor,
            accentEnd.cgColor
        ]
        updatePaths()

        let nextAnimationKey = "\(candidateID)|\(settleSeconds)"
        guard nextAnimationKey != animationKey else {
            return
        }

        animationKey = nextAnimationKey
        animateStroke(firstSeenAt: firstSeenAt, settleSeconds: settleSeconds)
    }

    private func setupLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.lineWidth = 2
        trackLayer.lineCap = .round

        progressMaskLayer.fillColor = NSColor.clear.cgColor
        progressMaskLayer.strokeColor = NSColor.black.cgColor
        progressMaskLayer.lineWidth = 2.2
        progressMaskLayer.lineCap = .round
        progressMaskLayer.strokeEnd = 0

        gradientLayer.startPoint = CGPoint(x: 0.15, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.85, y: 1)
        gradientLayer.mask = progressMaskLayer
        gradientLayer.shadowColor = NSColor(hex: "#3caed7")?.cgColor ?? NSColor.systemBlue.cgColor
        gradientLayer.shadowOpacity = 0.16
        gradientLayer.shadowRadius = 5
        gradientLayer.shadowOffset = CGSize(width: 0, height: -1)

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(gradientLayer)
    }

    private func updatePaths() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        trackLayer.contentsScale = scale
        gradientLayer.contentsScale = scale
        progressMaskLayer.contentsScale = scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let lineWidth: CGFloat = 2.2
        let radius = max(0, min(bounds.width, bounds.height) / 2 - lineWidth / 2 - 0.5)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: false
        )

        trackLayer.frame = bounds
        trackLayer.path = path
        gradientLayer.frame = bounds
        progressMaskLayer.frame = bounds
        progressMaskLayer.path = path

        CATransaction.commit()
    }

    private func animateStroke(firstSeenAt: Date, settleSeconds: Int) {
        let total = max(Double(settleSeconds), 0.001)
        let elapsed = max(0, Date().timeIntervalSince(firstSeenAt))
        let currentProgress = min(max(CGFloat(elapsed / total), 0), 1)
        let remaining = max(0, total - elapsed)

        progressMaskLayer.removeAnimation(forKey: "strokeEnd")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressMaskLayer.strokeEnd = currentProgress
        CATransaction.commit()

        guard remaining > 0.02, currentProgress < 1 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressMaskLayer.strokeEnd = 1
            CATransaction.commit()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressMaskLayer.strokeEnd = 1
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = currentProgress
        animation.toValue = 1
        animation.duration = remaining
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        progressMaskLayer.add(animation, forKey: "strokeEnd")
    }
}

@MainActor
private final class CountdownBarLayerView: NSView {
    private let trackLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let progressLayer = CALayer()
    private var animationKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func layout() {
        super.layout()
        updateFrames()
    }

    func configure(
        candidateID: String,
        firstSeenAt: Date,
        settleSeconds: Int,
        trackColor: NSColor,
        accentStart: NSColor,
        accentEnd: NSColor
    ) {
        trackLayer.backgroundColor = trackColor.withAlphaComponent(0.08).cgColor
        gradientLayer.colors = [
            accentStart.withAlphaComponent(0.72).cgColor,
            accentEnd.withAlphaComponent(0.92).cgColor
        ]
        gradientLayer.shadowColor = accentEnd.cgColor
        updateFrames()

        let nextAnimationKey = "\(candidateID)|\(settleSeconds)"
        guard nextAnimationKey != animationKey else {
            return
        }

        animationKey = nextAnimationKey
        animateWidth(firstSeenAt: firstSeenAt, settleSeconds: settleSeconds)
    }

    private func setupLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        trackLayer.masksToBounds = true
        trackLayer.cornerCurve = .continuous

        progressLayer.masksToBounds = true
        progressLayer.cornerCurve = .continuous

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.shadowOpacity = 0.18
        gradientLayer.shadowRadius = 4
        gradientLayer.shadowOffset = CGSize(width: 0, height: -1)

        progressLayer.addSublayer(gradientLayer)
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(progressLayer)
    }

    private func updateFrames() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        trackLayer.contentsScale = scale
        progressLayer.contentsScale = scale
        gradientLayer.contentsScale = scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let cornerRadius = bounds.height / 2
        trackLayer.frame = bounds
        trackLayer.cornerRadius = cornerRadius
        progressLayer.cornerRadius = cornerRadius
        gradientLayer.frame = CGRect(origin: .zero, size: bounds.size)

        CATransaction.commit()
    }

    private func animateWidth(firstSeenAt: Date, settleSeconds: Int) {
        let total = max(Double(settleSeconds), 0.001)
        let elapsed = max(0, Date().timeIntervalSince(firstSeenAt))
        let currentProgress = min(max(CGFloat(elapsed / total), 0), 1)
        let remaining = max(0, total - elapsed)
        let currentWidth = max(3, bounds.width * currentProgress)
        let targetWidth = bounds.width

        progressLayer.removeAnimation(forKey: "bounds.size.width")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.frame = CGRect(x: 0, y: 0, width: currentWidth, height: bounds.height)
        CATransaction.commit()

        guard remaining > 0.02, currentProgress < 1 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.frame = bounds
            CATransaction.commit()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.frame = bounds
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = currentWidth
        animation.toValue = targetWidth
        animation.duration = remaining
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(animation, forKey: "bounds.size.width")
    }
}

@MainActor
private final class WaveFillLayerView: NSView {
    private struct WaveMetrics {
        let amplitude: CGFloat
        let wavelength: CGFloat
        let shapeWidth: CGFloat
        let shapeHeight: CGFloat
    }

    private enum AnimationKey {
        static let fillRise = "fillRise"
        static let waveDrift = "waveDrift"
    }

    private let backgroundLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let waveMaskLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private var requestedAnimationKey = ""
    private var activeAnimationKey = ""
    private var firstSeenAt = Date()
    private var settleSeconds = 1
    private var waveDriftWavelength: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopLayerAnimations()
        } else {
            updateLayerGeometry()
            restartFillAnimationIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
        restartFillAnimationIfNeeded()
    }

    func configure(
        candidateID: String,
        firstSeenAt: Date,
        settleSeconds: Int,
        backgroundColor: NSColor,
        accentStart: NSColor,
        accentEnd: NSColor
    ) {
        self.firstSeenAt = firstSeenAt
        self.settleSeconds = max(settleSeconds, 1)
        requestedAnimationKey = "\(candidateID)|\(settleSeconds)|\(firstSeenAt.timeIntervalSinceReferenceDate)"
        backgroundLayer.fillColor = backgroundColor.withAlphaComponent(0.13).cgColor
        gradientLayer.colors = [
            accentStart.withAlphaComponent(0.52).cgColor,
            accentEnd.withAlphaComponent(0.66).cgColor
        ]
        highlightLayer.strokeColor = NSColor.white.withAlphaComponent(0.38).cgColor
        updateLayerGeometry()
        restartFillAnimationIfNeeded()
    }

    private func setupLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        backgroundLayer.fillColor = NSColor.black.withAlphaComponent(0.13).cgColor

        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.mask = waveMaskLayer

        waveMaskLayer.fillColor = NSColor.black.cgColor
        waveMaskLayer.anchorPoint = CGPoint(x: 0, y: 0)

        highlightLayer.fillColor = NSColor.clear.cgColor
        highlightLayer.lineWidth = 1
        highlightLayer.lineCap = .round
        highlightLayer.lineJoin = .round
        highlightLayer.opacity = 0.82
        highlightLayer.anchorPoint = CGPoint(x: 0, y: 0)

        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(highlightLayer)
    }

    private func currentProgress() -> CGFloat {
        let total = max(Double(settleSeconds), 0.001)
        let elapsed = max(0, Date().timeIntervalSince(firstSeenAt))
        return min(max(CGFloat(elapsed / total), 0), 1)
    }

    private func remainingDuration() -> CFTimeInterval {
        let total = max(Double(settleSeconds), 0.001)
        let elapsed = max(0, Date().timeIntervalSince(firstSeenAt))
        return max(0, total - elapsed)
    }

    private func currentMetrics() -> WaveMetrics? {
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let amplitude = min(2.7, max(1.8, bounds.height * 0.08))
        let wavelength = max(bounds.width * 0.9, 18)
        return WaveMetrics(
            amplitude: amplitude,
            wavelength: wavelength,
            shapeWidth: bounds.width + wavelength * 2,
            shapeHeight: bounds.height + amplitude * 3
        )
    }

    private func updateLayerGeometry() {
        guard let metrics = currentMetrics() else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        backgroundLayer.contentsScale = scale
        gradientLayer.contentsScale = scale
        waveMaskLayer.contentsScale = scale
        highlightLayer.contentsScale = scale

        layer?.frame = bounds
        backgroundLayer.frame = bounds
        gradientLayer.frame = bounds
        waveMaskLayer.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: metrics.shapeWidth, height: metrics.shapeHeight)
        )
        highlightLayer.bounds = waveMaskLayer.bounds

        let roundedPath = CGPath(
            roundedRect: bounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        backgroundLayer.path = roundedPath

        let paths = makeWavePaths(metrics: metrics)
        waveMaskLayer.path = paths.fill
        highlightLayer.path = paths.highlight

        if activeAnimationKey.isEmpty {
            let originY = waveOriginY(for: currentProgress(), amplitude: metrics.amplitude)
            waveMaskLayer.position = CGPoint(x: 0, y: originY)
            highlightLayer.position = CGPoint(x: 0, y: originY)
        }

        CATransaction.commit()
    }

    private func makeWavePaths(metrics: WaveMetrics) -> (fill: CGPath, highlight: CGPath) {
        let centerY = metrics.amplitude
        let step = max(1.4, metrics.wavelength / 18)

        let fillPath = CGMutablePath()
        fillPath.move(to: CGPoint(x: 0, y: metrics.shapeHeight))
        fillPath.addLine(to: CGPoint(x: 0, y: centerY))

        let highlightPath = CGMutablePath()
        var didMove = false
        var x: CGFloat = 0
        while x <= metrics.shapeWidth + step {
            let y = waveY(at: x, metrics: metrics, centerY: centerY)
            let point = CGPoint(x: x, y: y)
            fillPath.addLine(to: point)
            if didMove {
                highlightPath.addLine(to: point)
            } else {
                highlightPath.move(to: point)
                didMove = true
            }
            x += step
        }

        fillPath.addLine(to: CGPoint(x: metrics.shapeWidth, y: metrics.shapeHeight))
        fillPath.closeSubpath()

        return (fillPath, highlightPath)
    }

    private func waveY(at x: CGFloat, metrics: WaveMetrics, centerY: CGFloat) -> CGFloat {
        let phase = x / metrics.wavelength * .pi * 2
        let primary = sin(phase) * 0.68
        let secondary = sin(phase * 2 + 0.9) * 0.22
        return centerY + metrics.amplitude * (primary + secondary)
    }

    private func waveOriginY(for progress: CGFloat, amplitude: CGFloat) -> CGFloat {
        bounds.height * (1 - progress) - amplitude
    }

    private func restartFillAnimationIfNeeded() {
        guard !requestedAnimationKey.isEmpty,
              requestedAnimationKey != activeAnimationKey,
              let metrics = currentMetrics() else {
            startWaveDriftIfNeeded()
            return
        }

        waveMaskLayer.removeAnimation(forKey: AnimationKey.fillRise)
        highlightLayer.removeAnimation(forKey: AnimationKey.fillRise)

        let progress = currentProgress()
        let startY = waveOriginY(for: progress, amplitude: metrics.amplitude)
        let endY = waveOriginY(for: 1, amplitude: metrics.amplitude)
        let remaining = remainingDuration()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waveMaskLayer.position = CGPoint(x: 0, y: endY)
        highlightLayer.position = CGPoint(x: 0, y: endY)
        CATransaction.commit()

        if remaining > 0.02, progress < 1 {
            addFillAnimation(from: startY, to: endY, duration: remaining, layer: waveMaskLayer)
            addFillAnimation(from: startY, to: endY, duration: remaining, layer: highlightLayer)
            startWaveDriftIfNeeded()
        } else {
            stopWaveDrift()
        }

        activeAnimationKey = requestedAnimationKey
    }

    private func addFillAnimation(from startY: CGFloat, to endY: CGFloat, duration: CFTimeInterval, layer: CALayer) {
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.fromValue = startY
        animation.toValue = endY
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: AnimationKey.fillRise)
    }

    private func startWaveDriftIfNeeded() {
        guard !requestedAnimationKey.isEmpty,
              let metrics = currentMetrics(),
              currentProgress() < 1 else {
            stopWaveDrift()
            return
        }

        guard waveMaskLayer.animation(forKey: AnimationKey.waveDrift) == nil
                || abs(waveDriftWavelength - metrics.wavelength) > 0.5 else {
            return
        }

        stopWaveDrift()
        waveMaskLayer.add(waveDriftAnimation(wavelength: metrics.wavelength), forKey: AnimationKey.waveDrift)
        highlightLayer.add(waveDriftAnimation(wavelength: metrics.wavelength), forKey: AnimationKey.waveDrift)
        waveDriftWavelength = metrics.wavelength
    }

    private func waveDriftAnimation(wavelength: CGFloat) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -wavelength
        animation.duration = 1.9
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
    }

    private func stopWaveDrift() {
        waveMaskLayer.removeAnimation(forKey: AnimationKey.waveDrift)
        highlightLayer.removeAnimation(forKey: AnimationKey.waveDrift)
        waveDriftWavelength = 0
    }

    private func stopLayerAnimations() {
        waveMaskLayer.removeAnimation(forKey: AnimationKey.fillRise)
        highlightLayer.removeAnimation(forKey: AnimationKey.fillRise)
        stopWaveDrift()
        activeAnimationKey = ""
    }
}

struct AutoSwitchFeedbackBubbleView: View {
    let event: AutoSwitchFeedbackEvent
    let theme: AppTheme

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(theme.accentSoft.opacity(0.24))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Auto")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)

                Text(event.displayLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 194, height: 42)
        .background(
            Capsule(style: .continuous)
                .fill(theme.panel.opacity(0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.border.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: theme.ink.opacity(0.12), radius: 14, y: 6)
        )
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .leading)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                appeared = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) {
                withAnimation(.easeOut(duration: 0.32)) {
                    appeared = false
                }
            }
        }
    }
}
