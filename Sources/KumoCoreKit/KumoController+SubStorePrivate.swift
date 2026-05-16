import Foundation

extension KumoController {
    @discardableResult
    func startSubStoreServices(status: SubStoreStatus, restartBackend: Bool = false) async throws -> SubStoreStatus {
        var nextStatus = subStoreManager.resourcesInstalled() ? status : try subStoreManager.prepareResources()
        nextStatus.isEnabled = status.isEnabled
        nextStatus.usesCustomBackend = status.usesCustomBackend
        nextStatus.customBackendURL = status.customBackendURL
        nextStatus.allowsLAN = status.allowsLAN
        nextStatus.usesProxy = status.usesProxy
        nextStatus.syncCron = status.syncCron
        nextStatus.downloadCron = status.downloadCron
        nextStatus.uploadCron = status.uploadCron
        let allowLAN = status.allowsLAN
        let backendPort = try await SubStorePortAllocator.availablePort(
            startingAt: status.backendPort ?? 38324,
            allowLAN: allowLAN
        )

        nextStatus.backendPort = backendPort
        nextStatus.host = allowLAN ? "0.0.0.0" : "127.0.0.1"
        try subStoreManager.updateStatus(nextStatus)

        let plan = try subStoreManager.launchPlan(
            for: nextStatus,
            mixedPort: try? self.status().proxyPorts.mixedPort
        )

        if restartBackend {
            try await subStoreSupervisor.restart(plan: plan)
        } else {
            try await subStoreSupervisor.start(plan: plan)
        }

        return nextStatus
    }

    func subStoreProfileDownloadURL(path subStorePath: String, useProxy: Bool) throws -> URL {
        let status = try subStoreManager.status()
        let baseURL: URL
        if let absoluteURL = URL(string: subStorePath), absoluteURL.scheme != nil {
            baseURL = absoluteURL
        } else if let backendURL = subStoreManager.backendURL(for: status),
                  let relativeURL = URL(string: subStorePath, relativeTo: backendURL)?.absoluteURL {
            baseURL = relativeURL
        } else {
            throw KumoError.invalidArguments("Sub-Store backend is not configured.")
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw KumoError.invalidArguments("Enter a valid Sub-Store path.")
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { ["target", "noCache", "proxy"].contains($0.name) }
        queryItems.append(URLQueryItem(name: "target", value: "ClashMeta"))
        queryItems.append(URLQueryItem(name: "noCache", value: "true"))

        let mixedPort = (try? self.status().proxyPorts.mixedPort) ?? 0
        if useProxy, mixedPort > 0 {
            queryItems.append(URLQueryItem(name: "proxy", value: "http://127.0.0.1:\(mixedPort)"))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw KumoError.invalidArguments("Enter a valid Sub-Store path.")
        }
        return url
    }

    func subStoreDisplayName(for path: String) -> String {
        URL(string: path)?.lastPathComponent.removingPercentEncoding ?? "Sub-Store Profile"
    }
}
