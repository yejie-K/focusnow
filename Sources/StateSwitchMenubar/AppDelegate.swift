import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    let store = RecordStore()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var beaconWindows: [NSPanel] = []
    private var settingsWindow: NSWindow?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var dismissTask: DispatchWorkItem?
    private var lastTriggerDate = Date.distantPast
    private var isDraggingBeacon = false
    private var cancellables = Set<AnyCancellable>()

    private enum HoverBeacon {
        static let panelSize = NSSize(width: 74, height: 74)
        static let coreSize: CGFloat = 32
        static let margin: CGFloat = 16
        static let triggerRadius: CGFloat = 22
        static let dismissDelay: TimeInterval = 0.22
        static let retriggerDelay: TimeInterval = 0.32
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: 30)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "状态记录"
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 348, height: 432)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(store)
        )

        self.statusItem = statusItem
        self.popover = popover

        configureNotifications()
        configureAutoSwitchMonitoring()
        bindThemeUpdates()
        refreshStatusItemArtwork()
        configureBeaconWindows()
        startMouseMonitoring()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc
    private func togglePopover() {
        guard let statusButton = statusItem?.button,
              let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func popoverDidClose(_ notification: Notification) {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let snooze = UNNotificationAction(
            identifier: ReminderNotificationDescriptor.snoozeActionID,
            title: "稍后提醒"
        )
        let rest = UNNotificationAction(
            identifier: ReminderNotificationDescriptor.restActionID,
            title: "切到休息恢复"
        )
        let category = UNNotificationCategory(
            identifier: ReminderNotificationDescriptor.categoryID,
            actions: [snooze, rest],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func configureAutoSwitchMonitoring() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            let localizedName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            let bundleIdentifier = app.bundleIdentifier
            let bundleURLPath = app.bundleURL?.path

            Task { @MainActor [weak self] in
                self?.store.observeFrontmostApplication(
                    localizedName: localizedName,
                    bundleIdentifier: bundleIdentifier,
                    bundleURLPath: bundleURLPath
                )
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            observeFrontmostApplication(app)
        }
        refreshRunningApplications()

        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.refreshRunningApplications()
                self?.store.evaluateAutoSwitch(now: now)
            }
            .store(in: &cancellables)
    }

    private func observeFrontmostApplication(_ app: NSRunningApplication) {
        store.observeFrontmostApplication(
            localizedName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier,
            bundleURLPath: app.bundleURL?.path
        )
    }

    private func refreshRunningApplications() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> FrontmostApplicationSnapshot? in
                guard let localizedName = app.localizedName ?? app.bundleIdentifier else {
                    return nil
                }
                return FrontmostApplicationSnapshot(
                    localizedName: localizedName,
                    bundleIdentifier: app.bundleIdentifier,
                    bundleURLPath: app.bundleURL?.path
                )
            }
        store.observeRunningApplications(apps)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }

        let segmentKey = response.notification.request.content.userInfo[ReminderNotificationDescriptor.segmentKeyUserInfoKey] as? String
        guard let segmentKey else {
            return
        }

        switch response.actionIdentifier {
        case ReminderNotificationDescriptor.snoozeActionID:
            Task { @MainActor [weak self] in
                self?.store.snoozeReminder(segmentKey: segmentKey)
            }
        case ReminderNotificationDescriptor.restActionID:
            Task { @MainActor [weak self] in
                self?.store.switchToRestFromReminder(segmentKey: segmentKey)
            }
        default:
            break
        }
    }

    private func bindThemeUpdates() {
        store.$appearanceSelection
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItemArtwork()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItemArtwork() {
        guard let button = statusItem?.button else {
            return
        }
        button.image = StatusItemArtwork.makeImage(theme: store.theme)
    }

    func showSettingsWindow() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        DispatchQueue.main.async {
            self.popover?.performClose(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.level = .floating
            window.center()
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func terminateApp() {
        settingsWindow?.orderOut(nil)
        beaconWindows.forEach { $0.orderOut(nil) }
        popover?.performClose(nil)
        NSApp.terminate(nil)
    }

    @objc
    private func handleScreenParametersDidChange() {
        configureBeaconWindows()
    }

    private func configureBeaconWindows() {
        beaconWindows.forEach { $0.orderOut(nil) }
        beaconWindows.removeAll()

        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: HoverBeacon.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = makeBeaconHostingView(for: panel)

            positionBeaconWindow(panel, on: screen)
            panel.orderFrontRegardless()
            beaconWindows.append(panel)
        }
    }

    private func positionBeaconWindow(_ beaconWindow: NSPanel, on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        beaconWindow.setFrameOrigin(beaconOrigin(in: visibleFrame))
    }

    private func startMouseMonitoring() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.handleMouseMove(location: NSEvent.mouseLocation)
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMove(location: NSEvent.mouseLocation)
            return event
        }
    }

    private func handleMouseMove(location: NSPoint) {
        guard let popover else {
            return
        }

        store.beaconProximity = proximity(for: location)
        if isDraggingBeacon {
            return
        }

        let hoveredBeacon = beaconWindow(near: location)
        let insidePopover = isLocationInsidePopover(location)

        if let hoveredBeacon {
            dismissTask?.cancel()
            dismissTask = nil

            let enoughTimePassed = Date().timeIntervalSince(lastTriggerDate) > HoverBeacon.retriggerDelay
            if !popover.isShown && enoughTimePassed, let contentView = hoveredBeacon.contentView {
                lastTriggerDate = Date()
                popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minX)
            }
            return
        }

        guard popover.isShown, !insidePopover else {
            return
        }

        dismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.beaconWindow(near: NSEvent.mouseLocation) == nil && !self.isLocationInsidePopover(NSEvent.mouseLocation) {
                self.popover?.performClose(nil)
            }
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + HoverBeacon.dismissDelay, execute: task)
    }

    private func beaconWindow(near location: NSPoint) -> NSPanel? {
        beaconWindows.first { isLocation(location, near: $0) }
    }

    private func proximity(for location: NSPoint) -> CGFloat {
        guard !beaconWindows.isEmpty else {
            return 0
        }

        let nearestDistance = beaconWindows
            .map { beaconWindow -> CGFloat in
                let frame = beaconWindow.frame
                let center = NSPoint(x: frame.midX, y: frame.midY)
                let deltaX = location.x - center.x
                let deltaY = location.y - center.y
                return sqrt(deltaX * deltaX + deltaY * deltaY)
            }
            .min() ?? .greatestFiniteMagnitude

        let normalized = max(0, 1 - nearestDistance / HoverBeacon.triggerRadius)
        return pow(normalized, 1.2)
    }

    private func isLocation(_ location: NSPoint, near beaconWindow: NSPanel) -> Bool {
        let frame = beaconWindow.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        return distance <= HoverBeacon.triggerRadius
    }

    private func isLocationInsidePopover(_ location: NSPoint) -> Bool {
        guard let popoverWindow = popover?.contentViewController?.view.window else {
            return false
        }
        return popoverWindow.frame.contains(location)
    }

    private func makeBeaconHostingView(for panel: NSPanel) -> NSView {
        let hostingView = DraggableBeaconHostingView(
            rootView: FloatingBeaconView()
                .environmentObject(store)
        )

        hostingView.onDragBegan = { [weak self] in
            self?.beginBeaconDrag()
        }

        hostingView.onDragChanged = { [weak self, weak panel] origin in
            self?.updateDraggedBeacon(panel, proposedOrigin: origin)
        }

        hostingView.onDragEnded = { [weak self, weak panel] in
            self?.finishBeaconDrag(panel)
        }

        return hostingView
    }

    private func beginBeaconDrag() {
        dismissTask?.cancel()
        dismissTask = nil
        isDraggingBeacon = true
        lastTriggerDate = Date()
        store.beaconProximity = 1
        popover?.performClose(nil)
    }

    private func updateDraggedBeacon(_ panel: NSPanel?, proposedOrigin: NSPoint) {
        guard let panel, let screen = screen(for: panel) else {
            return
        }

        panel.setFrameOrigin(clampedBeaconOrigin(for: proposedOrigin, in: screen.visibleFrame))
    }

    private func finishBeaconDrag(_ panel: NSPanel?) {
        defer {
            isDraggingBeacon = false
            lastTriggerDate = Date()
            store.beaconProximity = proximity(for: NSEvent.mouseLocation)
        }

        guard let panel, let screen = screen(for: panel) else {
            return
        }

        let clampedOrigin = clampedBeaconOrigin(for: panel.frame.origin, in: screen.visibleFrame)
        panel.setFrameOrigin(clampedOrigin)

        let anchor = normalizedBeaconAnchor(for: panel.frame, in: screen.visibleFrame)
        store.setBeaconAnchor(x: anchor.x, y: anchor.y)
        repositionBeaconWindows(excluding: panel)
    }

    private func repositionBeaconWindows(excluding draggedPanel: NSPanel? = nil) {
        for beaconWindow in beaconWindows where beaconWindow !== draggedPanel {
            guard let screen = screen(for: beaconWindow) else {
                continue
            }
            positionBeaconWindow(beaconWindow, on: screen)
        }
    }

    private func beaconOrigin(in visibleFrame: NSRect) -> NSPoint {
        let ranges = beaconCenterRanges(in: visibleFrame)
        let anchor = store.appearanceSelection.beaconAnchor
        let centerX = interpolatedValue(in: ranges.x, progress: CGFloat(anchor.x))
        let centerY = interpolatedValue(in: ranges.y, progress: CGFloat(anchor.y))

        return NSPoint(
            x: centerX - HoverBeacon.panelSize.width / 2,
            y: centerY - HoverBeacon.panelSize.height / 2
        )
    }

    private func clampedBeaconOrigin(for proposedOrigin: NSPoint, in visibleFrame: NSRect) -> NSPoint {
        let ranges = beaconCenterRanges(in: visibleFrame)
        let proposedCenter = NSPoint(
            x: proposedOrigin.x + HoverBeacon.panelSize.width / 2,
            y: proposedOrigin.y + HoverBeacon.panelSize.height / 2
        )

        let centerX = min(max(proposedCenter.x, ranges.x.lowerBound), ranges.x.upperBound)
        let centerY = min(max(proposedCenter.y, ranges.y.lowerBound), ranges.y.upperBound)

        return NSPoint(
            x: centerX - HoverBeacon.panelSize.width / 2,
            y: centerY - HoverBeacon.panelSize.height / 2
        )
    }

    private func normalizedBeaconAnchor(for frame: NSRect, in visibleFrame: NSRect) -> BeaconAnchor {
        let ranges = beaconCenterRanges(in: visibleFrame)
        return BeaconAnchor(
            x: Double(normalizedValue(frame.midX, in: ranges.x)),
            y: Double(normalizedValue(frame.midY, in: ranges.y))
        )
    }

    private func beaconCenterRanges(in visibleFrame: NSRect) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let minCenterX = visibleFrame.minX + HoverBeacon.margin + HoverBeacon.coreSize / 2
        let maxCenterX = visibleFrame.maxX - HoverBeacon.margin - HoverBeacon.coreSize / 2
        let minCenterY = visibleFrame.minY + HoverBeacon.panelSize.height / 2
        let maxCenterY = visibleFrame.maxY - HoverBeacon.panelSize.height / 2

        let xRange: ClosedRange<CGFloat> = minCenterX <= maxCenterX
            ? minCenterX...maxCenterX
            : visibleFrame.midX...visibleFrame.midX
        let yRange: ClosedRange<CGFloat> = minCenterY <= maxCenterY
            ? minCenterY...maxCenterY
            : visibleFrame.midY...visibleFrame.midY

        return (xRange, yRange)
    }

    private func interpolatedValue(in range: ClosedRange<CGFloat>, progress: CGFloat) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(max(progress, 0), 1)
    }

    private func normalizedValue(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else {
            return 0.5
        }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func screen(for panel: NSPanel) -> NSScreen? {
        if let screen = panel.screen {
            return screen
        }

        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.min { left, right in
            let leftCenter = NSPoint(x: left.frame.midX, y: left.frame.midY)
            let rightCenter = NSPoint(x: right.frame.midX, y: right.frame.midY)
            return distanceSquared(from: center, to: leftCenter) < distanceSquared(from: center, to: rightCenter)
        }
    }

    private func distanceSquared(from: NSPoint, to: NSPoint) -> CGFloat {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return dx * dx + dy * dy
    }

    private func makeSettingsWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(store)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()
        window.contentViewController = hostingController
        window.delegate = self
        return window
    }
}
