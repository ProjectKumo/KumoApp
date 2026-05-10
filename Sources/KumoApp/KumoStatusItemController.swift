import AppKit
import KumoCoreKit

@MainActor
final class KumoStatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var iconTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Kumo"
        updateStatusIcon()
        startIconObserver()
    }

    func invalidate() {
        iconTimer?.invalidate()
        iconTimer = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusIcon()
        rebuildMenu(menu)
    }

    private var store: KumoAppStore? {
        KumoAppContext.shared.store
    }

    private func startIconObserver() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusIcon()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
    }

    private func updateStatusIcon() {
        let symbolName: String
        switch store?.status.state ?? .stopped {
        case .running:
            symbolName = "cloud.fill"
        case .starting:
            symbolName = "cloud.bolt"
        case .failed:
            symbolName = "cloud.slash"
        case .stopped:
            symbolName = "cloud"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Kumo")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let store else {
            menu.addItem(disabledItem("Kumo is starting..."))
            return
        }

        addStatusItems(to: menu, store: store)
        menu.addItem(.separator())

        menu.addItem(actionItem("Open Kumo", action: #selector(openKumo), keyEquivalent: "0"))
        menu.addItem(coreToggleItem(store: store))

        menu.addItem(.separator())
        menu.addItem(modeSubmenu(store: store))
        menu.addItem(systemProxyItem(store: store))

        menu.addItem(.separator())
        menu.addItem(profilesSubmenu(store: store))
        menu.addItem(proxyGroupsSubmenu(store: store))

        menu.addItem(.separator())
        menu.addItem(actionItem("Refresh", action: #selector(refreshKumo)))
        menu.addItem(actionItem("Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(actionItem("About Kumo", action: #selector(openAbout)))

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Kumo", action: #selector(quitKumo), keyEquivalent: "q"))
    }

    private func addStatusItems(to menu: NSMenu, store: KumoAppStore) {
        menu.addItem(disabledItem("Core: \(store.status.state.rawValue.capitalized)"))
        menu.addItem(disabledItem("Profile: \(store.currentProfile?.name ?? "Default")"))
        menu.addItem(disabledItem("Mode: \(store.status.mode.displayName)"))
    }

    private func coreToggleItem(store: KumoAppStore) -> NSMenuItem {
        let title = store.status.state == .running ? "Stop Kumo" : "Start Kumo"
        let item = actionItem(title, action: #selector(toggleCore))
        item.isEnabled = !store.isLoading && store.status.state != .starting
        return item
    }

    private func modeSubmenu(store: KumoAppStore) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for mode in OutboundMode.allCases {
            let item = actionItem(mode.displayName, action: #selector(selectMode(_:)), representedObject: mode.rawValue)
            item.state = store.status.mode == mode ? .on : .off
            item.isEnabled = !store.isLoading
                && !store.isSwitchingMode
                && store.status.state == .running
                && store.status.mode != mode
            menu.addItem(item)
        }

        let item = NSMenuItem(title: "Outbound Mode (\(store.status.mode.displayName))", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func systemProxyItem(store: KumoAppStore) -> NSMenuItem {
        let item = actionItem("System Proxy", action: #selector(toggleSystemProxy))
        item.state = store.status.systemProxyEnabled ? .on : .off
        item.isEnabled = !store.isLoading && (store.status.state == .running || store.status.systemProxyEnabled)
        return item
    }

    private func profilesSubmenu(store: KumoAppStore) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if store.profiles.isEmpty {
            menu.addItem(disabledItem("No profiles"))
        } else {
            for profile in store.profiles.prefix(8) {
                let item = actionItem(profile.name, action: #selector(selectProfile(_:)), representedObject: profile.id)
                item.state = profile.isCurrent ? .on : .off
                item.isEnabled = !profile.isCurrent && !store.isLoading
                menu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func proxyGroupsSubmenu(store: KumoAppStore) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if store.proxyGroups.isEmpty {
            menu.addItem(disabledItem("No proxy groups"))
        } else {
            for group in store.proxyGroups.prefix(5) {
                let groupMenu = NSMenu()
                groupMenu.autoenablesItems = false

                for proxy in group.proxies.prefix(12) {
                    let selection = ProxySelection(groupID: group.id, proxyID: proxy.id)
                    let item = actionItem(proxy.name, action: #selector(selectProxy(_:)), representedObject: selection)
                    item.state = group.selectedProxyName == proxy.name ? .on : .off
                    item.isEnabled = group.selectedProxyName != proxy.name && !store.isLoading
                    groupMenu.addItem(item)
                }

                let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                item.submenu = groupMenu
                menu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "Proxy Groups", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        representedObject: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = representedObject
        return item
    }

    @objc private func openKumo() {
        KumoAppContext.shared.openMainWindow()
    }

    @objc private func toggleCore() {
        guard let store else { return }
        if store.status.state == .running {
            store.stopCore()
        } else {
            Task { await store.startCore() }
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = OutboundMode(rawValue: rawValue) else {
            return
        }
        Task { await store?.setMode(mode) }
    }

    @objc private func toggleSystemProxy() {
        guard let store else { return }
        store.setSystemProxyEnabled(!store.status.systemProxyEnabled)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = store?.profiles.first(where: { $0.id == id }) else {
            return
        }
        Task { await store?.selectProfile(profile) }
    }

    @objc private func selectProxy(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ProxySelection,
              let group = store?.proxyGroups.first(where: { $0.id == selection.groupID }),
              let proxy = group.proxies.first(where: { $0.id == selection.proxyID }) else {
            return
        }
        Task { await store?.selectProxy(group: group, proxy: proxy) }
    }

    @objc private func refreshKumo() {
        Task { await store?.refreshAll() }
    }

    @objc private func openSettings() {
        KumoAppContext.shared.openSettings()
    }

    @objc private func openAbout() {
        KumoAppContext.shared.openAboutWindow()
    }

    @objc private func quitKumo() {
        NSApplication.shared.terminate(nil)
    }
}

private final class ProxySelection: NSObject {
    let groupID: String
    let proxyID: String

    init(groupID: String, proxyID: String) {
        self.groupID = groupID
        self.proxyID = proxyID
    }
}
