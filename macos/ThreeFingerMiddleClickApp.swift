import AppKit
import ApplicationServices
import ServiceManagement

@_silgen_name("tmc_start") private func tmcStart() -> Int32
@_silgen_name("tmc_stop") private func tmcStop()
@_silgen_name("tmc_is_running") private func tmcIsRunning() -> Int32
@_silgen_name("tmc_active_contact_count") private func tmcActiveContactCount() -> UInt32
@_silgen_name("tmc_frame_count") private func tmcFrameCount() -> UInt64
@_silgen_name("tmc_middle_click_count") private func tmcMiddleClickCount() -> UInt64
@_silgen_name("tmc_cancel_gesture") private func tmcCancelGesture()
@_silgen_name("tmc_record_physical_middle_click") private func tmcRecordPhysicalMiddleClick()
@_silgen_name("tmc_mouse_gesture_begin") private func tmcMouseGestureBegin()
@_silgen_name("tmc_mouse_gesture_observe") private func tmcMouseGestureObserve(_ deltaX: Double, _ deltaUp: Double) -> Int32
@_silgen_name("tmc_mouse_gesture_end") private func tmcMouseGestureEnd() -> Int32
@_silgen_name("tmc_mouse_gesture_cancel") private func tmcMouseGestureCancel()

private let syntheticEventMarker: Int64 = 0x33464D43 // "3FMC"
private let centerMouseButtonNumber = Int64(CGMouseButton.center.rawValue)

private func inputEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    return delegate.handleInputEvent(type: type, event: event)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let enabledKey = "enabled"
    private let showDockIconKey = "showDockIcon"
    private let mouseMissionControlKey = "mouseMiddleSwipeMissionControl"
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var mouseMissionControlItem: NSMenuItem!
    private var dockIconItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var statusLineItem: NSMenuItem!
    private var mainWindow: NSWindow!
    private var windowStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var diagnosticsLabel: NSTextField!
    private var enabledCheckbox: NSButton!
    private var mouseMissionControlCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var inputEventTap: CFMachPort?
    private var inputEventRunLoopSource: CFRunLoopSource?
    private var convertingPhysicalClick = false
    private var trackingMiddleGesture = false
    private var middleGestureClickState: Int64 = 1
    private var middleGestureEventNumber: Int64 = 0
    private var trackpadStartResult: Int32 = 0
    private var diagnosticsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
        if UserDefaults.standard.object(forKey: mouseMissionControlKey) == nil {
            UserDefaults.standard.set(true, forKey: mouseMissionControlKey)
        }

        configureWindow()
        configureMenu()
        applyDockIconVisibility()
        requestAccessibilityPermissionIfNeeded()

        applyEnabledState(showError: false)
        configureInputEventTapIfPossible()
        diagnosticsTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(refreshDiagnostics),
            userInfo: nil,
            repeats: true
        )
        refreshDiagnostics()
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        diagnosticsTimer?.invalidate()
        tearDownInputEventTap()
        tmcStop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = nil
            button.title = "3F"
            button.toolTip = "3F"
            button.setAccessibilityLabel("3F")
        }

        let menu = NSMenu(title: "3F")
        let openItem = NSMenuItem(title: "Open Status Window", action: #selector(showMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        mouseMissionControlItem = NSMenuItem(
            title: "Middle-button swipe: Mission Control",
            action: #selector(toggleMouseMissionControl),
            keyEquivalent: ""
        )
        mouseMissionControlItem.target = self
        menu.addItem(mouseMissionControlItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        dockIconItem = NSMenuItem(title: "Show Dock Icon", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockIconItem.target = self
        menu.addItem(dockIconItem)

        menu.addItem(.separator())
        statusLineItem = NSMenuItem(title: "Status: Starting…", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateMouseMissionControlControls()
        updateLaunchAtLoginItem()
        updateDockIconItem()
    }

    private func configureWindow() {
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "3F"
        mainWindow.isReleasedWhenClosed = false
        mainWindow.center()

        let titleLabel = NSTextField(labelWithString: "3F")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: "Three-finger trackpad taps become middle clicks. Hold the mouse middle button and move up to open Mission Control."
        )
        descriptionLabel.textColor = .secondaryLabelColor

        windowStatusLabel = NSTextField(labelWithString: "Status: Starting…")
        windowStatusLabel.font = .systemFont(ofSize: 14, weight: .medium)

        accessibilityStatusLabel = NSTextField(labelWithString: "Accessibility: Checking…")
        diagnosticsLabel = NSTextField(labelWithString: "Input frames: 0 · Middle clicks: 0")
        diagnosticsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        diagnosticsLabel.textColor = .secondaryLabelColor

        enabledCheckbox = NSButton(
            checkboxWithTitle: "Enabled",
            target: self,
            action: #selector(toggleEnabledFromWindow)
        )
        mouseMissionControlCheckbox = NSButton(
            checkboxWithTitle: "Middle-button swipe: Mission Control",
            target: self,
            action: #selector(toggleMouseMissionControlFromWindow)
        )
        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch at Login",
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )

        let permissionButton = NSButton(
            title: "Open Accessibility Settings",
            target: self,
            action: #selector(openAccessibilitySettings)
        )
        permissionButton.bezelStyle = .rounded

        let helpLabel = NSTextField(
            wrappingLabelWithString: "The app keeps running after this window is closed. Use the 3F item in the upper-right menu bar, or click the Dock icon to reopen this window."
        )
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.font = .systemFont(ofSize: 12)

        let stack = NSStackView(views: [
            titleLabel,
            descriptionLabel,
            windowStatusLabel,
            accessibilityStatusLabel,
            diagnosticsLabel,
            enabledCheckbox,
            mouseMissionControlCheckbox,
            launchAtLoginCheckbox,
            permissionButton,
            helpLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        mainWindow.contentView = contentView

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
        ])
    }

    @objc private func showMainWindow() {
        refreshDiagnostics()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureInputEventTapIfPossible() {
        guard inputEventTap == nil,
              isEnabled,
              AXIsProcessTrusted(),
              tmcIsRunning() == 1 || isMouseMissionControlEnabled
        else { return }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: inputEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        inputEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        inputEventRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Do not keep a global event filter installed while the feature is off.
    // Besides minimizing the app's input scope, this prevents stale conversion
    // state from surviving an enable/disable cycle.
    private func tearDownInputEventTap() {
        convertingPhysicalClick = false
        cancelMiddleGesture()
        if let tap = inputEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = inputEventRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        inputEventRunLoopSource = nil
        inputEventTap = nil
    }

    fileprivate func handleInputEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = inputEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            convertingPhysicalClick = false
            cancelMiddleGesture()
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown,
           tmcIsRunning() == 1,
           tmcActiveContactCount() == 3 {
            convertingPhysicalClick = true
            tmcCancelGesture()
            postPhysicalMiddleEvent(.otherMouseDown, from: event)
            return nil
        }

        if convertingPhysicalClick && type == .leftMouseDragged {
            return nil
        }

        if convertingPhysicalClick && type == .leftMouseUp {
            postPhysicalMiddleEvent(.otherMouseUp, from: event)
            convertingPhysicalClick = false
            tmcRecordPhysicalMiddleClick()
            return nil
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        if isEnabled,
           isMouseMissionControlEnabled,
           buttonNumber == centerMouseButtonNumber {
            if type == .otherMouseDown {
                trackingMiddleGesture = true
                middleGestureClickState = event.getIntegerValueField(.mouseEventClickState)
                middleGestureEventNumber = event.getIntegerValueField(.mouseEventNumber)
                tmcMouseGestureBegin()
                return nil
            }

            if trackingMiddleGesture && type == .otherMouseDragged {
                let deltaX = Double(event.getIntegerValueField(.mouseEventDeltaX))
                let deltaUp = -Double(event.getIntegerValueField(.mouseEventDeltaY))
                if tmcMouseGestureObserve(deltaX, deltaUp) == 1 {
                    triggerMissionControl()
                }
                return nil
            }

            if trackingMiddleGesture && type == .otherMouseUp {
                let shouldReplayClick = tmcMouseGestureEnd() == 1
                trackingMiddleGesture = false
                if shouldReplayClick {
                    postPhysicalMiddleEvent(
                        .otherMouseDown,
                        from: event,
                        clickState: middleGestureClickState,
                        eventNumber: middleGestureEventNumber
                    )
                    postPhysicalMiddleEvent(
                        .otherMouseUp,
                        from: event,
                        clickState: middleGestureClickState,
                        eventNumber: middleGestureEventNumber
                    )
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func cancelMiddleGesture() {
        trackingMiddleGesture = false
        tmcMouseGestureCancel()
    }

    private func postPhysicalMiddleEvent(
        _ type: CGEventType,
        from event: CGEvent,
        clickState: Int64? = nil,
        eventNumber: Int64? = nil
    ) {
        guard let middleEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: event.location,
            mouseButton: .center
        ) else { return }
        middleEvent.flags = event.flags
        middleEvent.setIntegerValueField(
            .mouseEventClickState,
            value: clickState ?? event.getIntegerValueField(.mouseEventClickState)
        )
        middleEvent.setIntegerValueField(
            .mouseEventNumber,
            value: eventNumber ?? event.getIntegerValueField(.mouseEventNumber)
        )
        middleEvent.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        middleEvent.post(tap: .cghidEventTap)
    }

    private func triggerMissionControl() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.exposelauncher"
            ) else {
                self.postMissionControlShortcut()
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration
            ) { _, error in
                if error != nil {
                    self.postMissionControlShortcut()
                }
            }
        }
    }

    private func postMissionControlShortcut() {
        let upArrowKeyCode: CGKeyCode = 126
        for keyDown in [true, false] {
            guard let keyEvent = CGEvent(
                keyboardEventSource: nil,
                virtualKey: upArrowKeyCode,
                keyDown: keyDown
            ) else { continue }
            keyEvent.flags = .maskControl
            keyEvent.post(tap: .cghidEventTap)
        }
    }

    @objc private func refreshDiagnostics() {
        let accessibilityAllowed = AXIsProcessTrusted()
        let frameCount = tmcFrameCount()
        let activeContacts = tmcActiveContactCount()
        let middleClickCount = tmcMiddleClickCount()
        accessibilityStatusLabel.stringValue = accessibilityAllowed
            ? "Accessibility: Allowed"
            : "Accessibility: Required"
        diagnosticsLabel.stringValue = "Input frames: \(frameCount) · Active fingers: \(activeContacts) · Middle clicks: \(middleClickCount)"
        UserDefaults.standard.set(accessibilityAllowed, forKey: "diagnosticAccessibilityAllowed")
        UserDefaults.standard.set(frameCount, forKey: "diagnosticFrameCount")
        UserDefaults.standard.set(activeContacts, forKey: "diagnosticActiveContacts")
        UserDefaults.standard.set(middleClickCount, forKey: "diagnosticMiddleClickCount")

        if let tap = inputEventTap,
           !accessibilityAllowed || !CGEvent.tapIsEnabled(tap: tap) {
            tearDownInputEventTap()
        }

        if accessibilityAllowed,
           isEnabled,
           inputEventTap == nil,
           tmcIsRunning() == 1 || isMouseMissionControlEnabled {
            configureInputEventTapIfPossible()
        }
        updateOperationalStatus()
    }

    @objc private func toggleEnabled() {
        UserDefaults.standard.set(!isEnabled, forKey: enabledKey)
        applyEnabledState(showError: true)
    }

    @objc private func toggleEnabledFromWindow() {
        UserDefaults.standard.set(enabledCheckbox.state == .on, forKey: enabledKey)
        applyEnabledState(showError: true)
    }

    @objc private func toggleMouseMissionControl() {
        UserDefaults.standard.set(!isMouseMissionControlEnabled, forKey: mouseMissionControlKey)
        applyMouseMissionControlSetting()
    }

    @objc private func toggleMouseMissionControlFromWindow() {
        UserDefaults.standard.set(
            mouseMissionControlCheckbox.state == .on,
            forKey: mouseMissionControlKey
        )
        applyMouseMissionControlSetting()
    }

    private func applyMouseMissionControlSetting() {
        tearDownInputEventTap()
        updateMouseMissionControlControls()
        if isEnabled {
            configureInputEventTapIfPossible()
        }
        updateOperationalStatus()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            statusLineItem.title = "Status: Login item failed"
            presentError("Could not update the login-item setting: \(error.localizedDescription)")
        }
        updateLaunchAtLoginItem()
    }

    @objc private func toggleDockIcon() {
        UserDefaults.standard.set(!showDockIcon, forKey: showDockIconKey)
        applyDockIconVisibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    private var isMouseMissionControlEnabled: Bool {
        UserDefaults.standard.bool(forKey: mouseMissionControlKey)
    }

    private var isInputEventTapActive: Bool {
        guard let tap = inputEventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private var showDockIcon: Bool {
        UserDefaults.standard.bool(forKey: showDockIconKey)
    }

    private func applyDockIconVisibility() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        updateDockIconItem()
    }

    private func updateDockIconItem() {
        dockIconItem?.state = showDockIcon ? .on : .off
    }

    private func applyEnabledState(showError: Bool) {
        if !isEnabled {
            tearDownInputEventTap()
            tmcStop()
            updateEnabledItem(running: false)
            updateMouseMissionControlControls()
            updateStatus("Disabled")
            return
        }

        trackpadStartResult = tmcStart()
        UserDefaults.standard.set(trackpadStartResult, forKey: "diagnosticStartResult")
        configureInputEventTapIfPossible()
        updateMouseMissionControlControls()
        updateOperationalStatus()

        let anyFeatureRunning = tmcIsRunning() == 1
            || (isMouseMissionControlEnabled && isInputEventTapActive)
        if showError && !anyFeatureRunning && trackpadStartResult != 1 {
            presentError(statusDescription(for: trackpadStartResult))
        }
    }

    private func updateOperationalStatus() {
        guard isEnabled else { return }

        let accessibilityAllowed = AXIsProcessTrusted()
        let trackpadRunning = tmcIsRunning() == 1
        let mouseGestureRunning = isMouseMissionControlEnabled && isInputEventTapActive
        updateEnabledItem(
            running: (trackpadRunning && accessibilityAllowed) || mouseGestureRunning
        )

        if !accessibilityAllowed {
            let suffix = trackpadRunning ? "" : " · Trackpad unavailable"
            updateStatus("Accessibility required\(suffix)")
        } else if trackpadRunning {
            updateStatus("Running")
        } else if mouseGestureRunning {
            updateStatus("Mouse gesture active · Trackpad unavailable")
        } else {
            updateStatus(statusDescription(for: trackpadStartResult))
        }
    }

    private func updateEnabledItem(running: Bool) {
        enabledItem.state = isEnabled ? .on : .off
        enabledCheckbox.state = isEnabled ? .on : .off
        statusItem.button?.appearsDisabled = !running
    }

    private func updateMouseMissionControlControls() {
        let state: NSControl.StateValue = isMouseMissionControlEnabled ? .on : .off
        mouseMissionControlItem?.state = state
        mouseMissionControlCheckbox?.state = state
        mouseMissionControlItem?.isEnabled = isEnabled
        mouseMissionControlCheckbox?.isEnabled = isEnabled
    }

    private func updateStatus(_ status: String) {
        let text = "Status: \(status)"
        statusLineItem.title = text
        windowStatusLabel.stringValue = text
    }

    private func updateLaunchAtLoginItem() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginItem.isEnabled = false
            return
        }
        let state: NSControl.StateValue = SMAppService.mainApp.status == .enabled ? .on : .off
        launchAtLoginItem.state = state
        launchAtLoginCheckbox.state = state
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func statusDescription(for code: Int32) -> String {
        switch code {
        case -1: return "Multitouch framework unavailable"
        case -2: return "Multitouch symbols unavailable"
        case -3: return "No default trackpad found"
        case -4: return "Could not start trackpad listener"
        case -5: return "Could not register trackpad listener"
        default: return "Engine error (\(code))"
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "3F"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@main
enum ThreeFMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
