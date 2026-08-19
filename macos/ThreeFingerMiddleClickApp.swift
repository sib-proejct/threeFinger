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

private func physicalClickEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    return delegate.handlePhysicalClickEvent(type: type, event: event)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let enabledKey = "enabled"
    private let showDockIconKey = "showDockIcon"
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var dockIconItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var statusLineItem: NSMenuItem!
    private var mainWindow: NSWindow!
    private var windowStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var diagnosticsLabel: NSTextField!
    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var physicalClickTap: CFMachPort?
    private var physicalClickRunLoopSource: CFRunLoopSource?
    private var convertingPhysicalClick = false
    private var diagnosticsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureWindow()
        configureMenu()
        applyDockIconVisibility()
        requestAccessibilityPermissionIfNeeded()

        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
        applyEnabledState(showError: false)
        configurePhysicalClickTapIfPossible()
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
        tearDownPhysicalClickTap()
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
        updateLaunchAtLoginItem()
        updateDockIconItem()
    }

    private func configureWindow() {
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "3F"
        mainWindow.isReleasedWhenClosed = false
        mainWindow.center()

        let titleLabel = NSTextField(labelWithString: "3F")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Three-finger trackpad taps are converted into middle mouse clicks.")
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

    private func configurePhysicalClickTapIfPossible() {
        guard physicalClickTap == nil,
              isEnabled,
              tmcIsRunning() == 1,
              AXIsProcessTrusted()
        else { return }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: physicalClickEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        physicalClickTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        physicalClickRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Do not keep a global event filter installed while the feature is off.
    // Besides minimizing the app's input scope, this prevents stale conversion
    // state from surviving an enable/disable cycle.
    private func tearDownPhysicalClickTap() {
        convertingPhysicalClick = false
        if let tap = physicalClickTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = physicalClickRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        physicalClickRunLoopSource = nil
        physicalClickTap = nil
    }

    fileprivate func handlePhysicalClickEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = physicalClickTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            convertingPhysicalClick = false
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

        return Unmanaged.passUnretained(event)
    }

    private func postPhysicalMiddleEvent(_ type: CGEventType, from event: CGEvent) {
        guard let middleEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: event.location,
            mouseButton: .center
        ) else { return }
        middleEvent.flags = event.flags
        middleEvent.post(tap: .cghidEventTap)
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

        if accessibilityAllowed && isEnabled && tmcIsRunning() == 1 && physicalClickTap == nil {
            configurePhysicalClickTapIfPossible()
        }
    }

    @objc private func toggleEnabled() {
        UserDefaults.standard.set(!isEnabled, forKey: enabledKey)
        applyEnabledState(showError: true)
    }

    @objc private func toggleEnabledFromWindow() {
        UserDefaults.standard.set(enabledCheckbox.state == .on, forKey: enabledKey)
        applyEnabledState(showError: true)
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
            tearDownPhysicalClickTap()
            tmcStop()
            updateEnabledItem(running: false)
            updateStatus("Disabled")
            return
        }

        let result = tmcStart()
        UserDefaults.standard.set(result, forKey: "diagnosticStartResult")
        let running = result == 1 && tmcIsRunning() == 1
        updateEnabledItem(running: running)
        if running {
            updateStatus("Running")
            configurePhysicalClickTapIfPossible()
        } else {
            tearDownPhysicalClickTap()
            updateStatus(statusDescription(for: result))
            if showError {
                presentError(statusDescription(for: result))
            }
        }
    }

    private func updateEnabledItem(running: Bool) {
        enabledItem.state = isEnabled ? .on : .off
        enabledCheckbox.state = isEnabled ? .on : .off
        statusItem.button?.appearsDisabled = !running
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
