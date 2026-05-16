import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct ResourcesView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        KumoPage(title: "Resources") {
            Form {
                Section("Geo Data") {
                    TextField("GeoIP DAT", text: geoIPURLBinding)
                    TextField("GeoSite", text: geoSiteURLBinding)
                    TextField("MMDB", text: mmdbURLBinding)
                    TextField("ASN", text: asnURLBinding)
                    Toggle("GeoIP DAT Mode", isOn: geoDatModeBinding)
                    Toggle("Auto Update", isOn: geoAutoUpdateBinding)
                    TextField("Update Interval (hours)", value: geoUpdateIntervalBinding, format: .number)
                    Button("Update Geo Data") {
                        Task { await store.upgradeGeoData() }
                    }
                    .disabled(store.status.state != .running || store.isLoading)
                }

                Section("Proxy Providers") {
                    if store.proxyProviders.isEmpty {
                        Text(store.status.state == .running ? "No proxy providers reported by Mihomo." : "Start Kumo to inspect providers.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Update All Providers") {
                            Task { await store.updateAllProviders() }
                        }
                        ForEach(store.proxyProviders) { provider in
                            ProviderRow(title: provider.name, detail: "\(provider.vehicleType) · \(provider.proxyCount) proxies") {
                                Button("Update") {
                                    Task { await store.updateProxyProvider(provider) }
                                }
                            }
                        }
                    }
                }

                Section("Rule Providers") {
                    if store.ruleProviders.isEmpty {
                        Text(store.status.state == .running ? "No rule providers reported by Mihomo." : "Start Kumo to inspect providers.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.ruleProviders) { provider in
                            ProviderRow(title: provider.name, detail: "\(provider.vehicleType)::\(provider.behavior) · \(provider.ruleCount) rules") {
                                Button("Update") {
                                    Task { await store.updateRuleProvider(provider) }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task {
            await store.loadResources()
        }
    }

    private var runtimeSettings: CoreRuntimeSettings {
        store.status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: store.status.proxyPorts.mixedPort)
    }

    private func updateGeoData(_ edit: (inout GeoDataSettings) -> Void) {
        var settings = runtimeSettings
        edit(&settings.geoData)
        Task { await store.updateRuntimeSettings(settings) }
    }

    private var geoIPURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.geoIPURL } set: { value in updateGeoData { $0.geoIPURL = value } }
    }

    private var geoSiteURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.geoSiteURL } set: { value in updateGeoData { $0.geoSiteURL = value } }
    }

    private var mmdbURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.mmdbURL } set: { value in updateGeoData { $0.mmdbURL = value } }
    }

    private var asnURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.asnURL } set: { value in updateGeoData { $0.asnURL = value } }
    }

    private var geoDatModeBinding: Binding<Bool> {
        Binding { runtimeSettings.geoData.usesDatMode } set: { value in updateGeoData { $0.usesDatMode = value } }
    }

    private var geoAutoUpdateBinding: Binding<Bool> {
        Binding { runtimeSettings.geoData.autoUpdate } set: { value in updateGeoData { $0.autoUpdate = value } }
    }

    private var geoUpdateIntervalBinding: Binding<Int> {
        Binding { runtimeSettings.geoData.updateIntervalHours } set: { value in updateGeoData { $0.updateIntervalHours = max(1, value) } }
    }
}

