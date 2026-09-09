//
//  CodexDataApp.swift
//  CodexData
//
import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class CodexDataAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = CodexStore()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var shortDataRow: QuotaMenuRowView?
    private var longDataRow: QuotaMenuRowView?
    private var launchAtLoginToggleView: StayOpenToggleView?
    private var titleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let shortPercentKey = "showShortPercent"
    private let longPercentKey = "showLongPercent"
    private let shortCountdownKey = "showShortCountdown"
    private let longCountdownKey = "showLongCountdown"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            shortPercentKey: true,
            longPercentKey: true,
            shortCountdownKey: false,
            longCountdownKey: false
        ])

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.menu = makeMenu()

        store.$windows
            .combineLatest(store.$connectionState)
            .sink { [weak self] _, _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        titleTimer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(statusTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )

        updateStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        titleTimer?.invalidate()
        titleTimer = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let heading = NSMenuItem(title: "CODEX / PULSE", action: nil, keyEquivalent: "")
        menu.addItem(heading)

        let status = NSMenuItem(title: AppText.connecting, action: nil, keyEquivalent: "")
        statusMenuItem = status
        menu.addItem(status)

        let launchAtLogin = makeLaunchAtLoginToggle()
        launchAtLoginToggleView = launchAtLogin.view as? StayOpenToggleView
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())

        let shortDataRow = QuotaMenuRowView(kind: .primary)
        let shortData = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortData.view = shortDataRow
        self.shortDataRow = shortDataRow
        menu.addItem(shortData)

        let longDataRow = QuotaMenuRowView(kind: .secondary)
        let longData = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        longData.view = longDataRow
        self.longDataRow = longDataRow
        menu.addItem(longData)
        menu.addItem(.separator())

        menu.addItem(makeToggle(title: AppText.shortPercent, key: shortPercentKey))
        menu.addItem(makeToggle(title: AppText.longPercent, key: longPercentKey))
        menu.addItem(makeToggle(title: AppText.shortCountdown, key: shortCountdownKey))
        menu.addItem(makeToggle(title: AppText.longCountdown, key: longCountdownKey))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: AppText.quit, action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        return menu
    }

    private func makeToggle(title: String, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let view = StayOpenToggleView(
            title: title,
            isOn: UserDefaults.standard.bool(forKey: key)
        ) { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: key)
            self?.updateStatusItem()
        }
        item.view = view
        return item
    }

    private func makeLaunchAtLoginToggle() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let view = StayOpenToggleView(
            title: AppText.launchAtLogin,
            isOn: isLaunchAtLoginEnabled()
        ) { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }
        item.view = view
        return item
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Codex Pulse launch-at-login update failed: %@", error.localizedDescription)
        }

        launchAtLoginToggleView?.setOn(isLaunchAtLoginEnabled())
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @objc private func statusTimerFired(_ timer: Timer) {
        updateStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginToggleView?.setOn(isLaunchAtLoginEnabled())
        updateStatusItem()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            (menuItem.view as? HoveringMenuView)?.setHighlighted(menuItem === item)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let now = Date()
        let short = store.windows.first { $0.kind == .primary }
        let long = store.windows.first { $0.kind == .secondary }

        let text = MenuBarFormatting.statusText(
            windows: store.windows,
            showShortPercent: UserDefaults.standard.bool(forKey: shortPercentKey),
            showLongPercent: UserDefaults.standard.bool(forKey: longPercentKey),
            showShortCountdown: UserDefaults.standard.bool(forKey: shortCountdownKey),
            showLongCountdown: UserDefaults.standard.bool(forKey: longCountdownKey),
            now: now
        )

        shortDataRow?.update(window: short, now: now)
        longDataRow?.update(window: long, now: now)

        let statusFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        button.title = ""
        button.attributedTitle = text.map { MenuBarFormatting.attributedText($0, font: statusFont) }
            ?? NSAttributedString(string: "")
        button.font = statusFont
        if text == nil {
            button.image = NSImage(
                systemSymbolName: "waveform.path.ecg",
                accessibilityDescription: AppText.codexPulseAccessibility
            )
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }

        statusMenuItem?.title = AppText.statusTitle(for: store.connectionState)
        button.needsDisplay = true
        button.displayIfNeeded()
        shortDataRow?.needsDisplay = true
        shortDataRow?.displayIfNeeded()
        longDataRow?.needsDisplay = true
        longDataRow?.displayIfNeeded()
    }
}

class HoveringMenuView: NSView {
    private let selectionView = NSVisualEffectView()
    private(set) var isHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selectionView.material = .selection
        selectionView.blendingMode = .withinWindow
        selectionView.state = .active
        selectionView.isEmphasized = true
        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 6
        selectionView.layer?.masksToBounds = true
        selectionView.isHidden = true
        addSubview(selectionView, positioned: .below, relativeTo: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        selectionView.frame = bounds.insetBy(dx: 4, dy: 1)
    }

    func setHighlighted(_ highlighted: Bool) {
        isHighlighted = highlighted
        selectionView.isHidden = !highlighted
        highlightDidChange()
    }

    func highlightDidChange() {
        needsDisplay = true
    }

}

final class StayOpenToggleView: HoveringMenuView {
    private let title: String
    private var isOn: Bool
    private let onToggle: (Bool) -> Void
    private let titleField = NSTextField(labelWithString: "")
    private let checkmarkView = NSImageView()

    init(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        self.title = title
        self.isOn = isOn
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        autoresizingMask = [.width]

        titleField.stringValue = title
        titleField.font = NSFont.menuFont(ofSize: 0)
        titleField.textColor = .labelColor
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isSelectable = false

        if let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已启用") {
            check.isTemplate = true
            checkmarkView.image = check
            checkmarkView.contentTintColor = .labelColor
            checkmarkView.imageScaling = .scaleProportionallyDown
        }
        checkmarkView.isHidden = !isOn

        addSubview(titleField)
        addSubview(checkmarkView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let rowHeight: CGFloat = 18
        let y = (bounds.height - rowHeight) / 2
        let leftPadding: CGFloat = 14
        let rightPadding: CGFloat = 12
        let checkmarkWidth: CGFloat = 14
        let gap: CGFloat = 8
        let checkmarkX = bounds.width - rightPadding - checkmarkWidth

        titleField.frame = NSRect(
            x: leftPadding,
            y: y,
            width: max(0, checkmarkX - gap - leftPadding),
            height: rowHeight
        )
        checkmarkView.frame = NSRect(x: checkmarkX, y: y + 1, width: checkmarkWidth, height: rowHeight - 2)
    }

    override func highlightDidChange() {
        super.highlightDidChange()
        let color = isHighlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        titleField.textColor = color
        checkmarkView.contentTintColor = color
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        checkmarkView.isHidden = !isOn
        highlightDidChange()
        needsDisplay = true
        displayIfNeeded()
        checkmarkView.displayIfNeeded()
        onToggle(isOn)
    }

    override func mouseUp(with event: NSEvent) {}

    func setOn(_ enabled: Bool) {
        isOn = enabled
        checkmarkView.isHidden = !enabled
        highlightDidChange()
        needsDisplay = true
        displayIfNeeded()
        checkmarkView.displayIfNeeded()
    }
}

final class QuotaMenuRowView: HoveringMenuView {
    private let kind: QuotaWindow.Kind
    private let percentField = NSTextField(labelWithString: "")
    private let timerImageView = NSImageView()
    private let countdownField = NSTextField(labelWithString: "")

    init(kind: QuotaWindow.Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        autoresizingMask = [.width]

        let menuFont = NSFont.menuFont(ofSize: 0)
        percentField.font = menuFont
        percentField.textColor = .labelColor
        countdownField.font = NSFont.monospacedDigitSystemFont(ofSize: menuFont.pointSize, weight: .regular)
        countdownField.textColor = .labelColor
        countdownField.alignment = .right

        if let symbol = NSImage(systemSymbolName: "clock", accessibilityDescription: AppText.countdownAccessibility) {
            symbol.isTemplate = true
            timerImageView.image = symbol
            timerImageView.contentTintColor = .labelColor
            timerImageView.imageScaling = .scaleProportionallyDown
        }

        addSubview(percentField)
        addSubview(timerImageView)
        addSubview(countdownField)
        update(window: nil, now: Date())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func highlightDidChange() {
        super.highlightDidChange()
        let color = isHighlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        percentField.textColor = color
        countdownField.textColor = color
        timerImageView.contentTintColor = color
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let rowHeight: CGFloat = 18
        let y = (bounds.height - rowHeight) / 2
        let rightPadding: CGFloat = 12
        let countdownWidth: CGFloat = 48
        let iconWidth: CGFloat = 16
        let gap: CGFloat = 5
        let countdownX = bounds.width - rightPadding - countdownWidth
        let iconX = countdownX - gap - iconWidth

        percentField.frame = NSRect(x: 14, y: y, width: max(0, iconX - 26), height: rowHeight)
        timerImageView.frame = NSRect(x: iconX, y: y + 1, width: iconWidth, height: rowHeight - 2)
        countdownField.frame = NSRect(x: countdownX, y: y, width: countdownWidth, height: rowHeight)
    }

    func update(window: QuotaWindow?, now: Date) {
        percentField.stringValue = MenuBarFormatting.percentText(kind: kind, window: window)
        countdownField.stringValue = MenuBarFormatting.countdownText(window: window, now: now)
    }
}

@main
struct CodexDataApp: App {
    @NSApplicationDelegateAdaptor(CodexDataAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
