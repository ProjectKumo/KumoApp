import Foundation

extension KumoController {
    func runtimePatch(for settings: CoreRuntimeSettings) -> [String: Any] {
        var patch: [String: Any] = [
            "mixed-port": settings.mixedPort,
            "allow-lan": settings.allowLAN,
            "log-level": settings.logLevel,
            "ipv6": settings.ipv6,
            "find-process-mode": settings.findProcessMode,
            "geodata-mode": settings.geoData.usesDatMode,
            "geo-auto-update": settings.geoData.autoUpdate,
            "geo-update-interval": settings.geoData.updateIntervalHours,
            "geox-url": [
                "geoip": settings.geoData.geoIPURL,
                "geosite": settings.geoData.geoSiteURL,
                "mmdb": settings.geoData.mmdbURL,
                "asn": settings.geoData.asnURL
            ]
        ]
        if let tun = settings.tun {
            patch["tun"] = tunPatch(for: tun)
        }
        if let dns = settings.dns, dns.isEnabled {
            patch["dns"] = dnsPatch(for: dns)
        }
        if let sniffer = settings.sniffer, sniffer.isEnabled {
            patch["sniffer"] = snifferPatch(for: sniffer)
        }
        if let dns = settings.dns, !dns.hosts.isEmpty {
            patch["hosts"] = dns.hosts.mapValues { value -> Any in
                switch value {
                case .single(let s): return s
                case .multiple(let arr): return arr
                }
            }
        }
        return patch
    }

    func tunPatch(for tun: TunSettings) -> [String: Any] {
        var patch: [String: Any] = [
            "enable": tun.isEnabled,
            "stack": tun.stack,
            "auto-route": tun.autoRoute,
            "auto-redirect": tun.autoRedirect,
            "auto-detect-interface": tun.autoDetectInterface,
            "strict-route": tun.strictRoute,
            "disable-icmp-forwarding": tun.disableICMPForwarding,
            "dns-hijack": tun.dnsHijack,
            "mtu": tun.mtu
        ]
        if !tun.routeExcludeAddress.isEmpty {
            patch["route-exclude-address"] = tun.routeExcludeAddress
        }
        if let device = tun.device, device.hasPrefix("utun") {
            patch["device"] = device
        }
        return patch
    }

    func dnsPatch(for dns: DnsSettings) -> [String: Any] {
        var patch: [String: Any] = [
            "enable": dns.isEnabled,
            "ipv6": dns.ipv6,
            "enhanced-mode": dns.enhancedMode,
            "fake-ip-range": dns.fakeIPRange,
            "use-hosts": dns.useHosts,
            "use-system-hosts": dns.useSystemHosts,
            "respect-rules": dns.respectRules
        ]
        if !dns.listen.isEmpty {
            patch["listen"] = dns.listen
        }
        patch["ipv6-timeout"] = dns.ipv6Timeout
        patch["prefer-h3"] = dns.preferH3
        if !dns.fakeIPRange6.isEmpty {
            patch["fake-ip-range6"] = dns.fakeIPRange6
        }
        if !dns.fakeIPFilter.isEmpty {
            patch["fake-ip-filter"] = dns.fakeIPFilter
        }
        if !dns.fakeIPFilterMode.isEmpty {
            patch["fake-ip-filter-mode"] = dns.fakeIPFilterMode
        }
        if !dns.defaultNameserver.isEmpty {
            patch["default-nameserver"] = dns.defaultNameserver
        }
        if !dns.nameserver.isEmpty {
            patch["nameserver"] = dns.nameserver
        }
        if !dns.fallback.isEmpty {
            patch["fallback"] = dns.fallback
        }
        if !dns.fallbackFilter.isEmpty {
            patch["fallback-filter"] = dns.fallbackFilter.mapValues { value -> Any in
                switch value {
                case .bool(let b): return b
                case .single(let s): return s
                case .multiple(let arr): return arr
                }
            }
        }
        if !dns.proxyServerNameserver.isEmpty {
            patch["proxy-server-nameserver"] = dns.proxyServerNameserver
        }
        if !dns.directNameserver.isEmpty {
            patch["direct-nameserver"] = dns.directNameserver
        }
        patch["direct-nameserver-follow-policy"] = dns.directNameserverFollowPolicy
        if !dns.nameserverPolicy.isEmpty {
            patch["nameserver-policy"] = dns.nameserverPolicy.mapValues { value -> Any in
                switch value {
                case .single(let s): return s
                case .multiple(let arr): return arr
                }
            }
        }
        if !dns.proxyServerNameserverPolicy.isEmpty {
            patch["proxy-server-nameserver-policy"] = dns.proxyServerNameserverPolicy.mapValues { value -> Any in
                switch value {
                case .single(let s): return s
                case .multiple(let arr): return arr
                }
            }
        }
        if !dns.cacheAlgorithm.isEmpty {
            patch["cache-algorithm"] = dns.cacheAlgorithm
        }
        return patch
    }

    func snifferPatch(for sniffer: SnifferSettings) -> [String: Any] {
        var patch: [String: Any] = [
            "enable": sniffer.isEnabled,
            "parse-pure-ip": sniffer.parsePureIP,
            "force-dns-mapping": sniffer.forceDNSMapping,
            "override-destination": sniffer.overrideDestination
        ]
        if !sniffer.httpPorts.isEmpty || !sniffer.tlsPorts.isEmpty || !sniffer.quicPorts.isEmpty || sniffer.httpOverrideDestination {
            var sniff: [String: [String: Any]] = [:]
            if !sniffer.httpPorts.isEmpty || sniffer.httpOverrideDestination {
                var http: [String: Any] = [:]
                if !sniffer.httpPorts.isEmpty {
                    http["ports"] = sniffer.httpPorts
                }
                if sniffer.httpOverrideDestination {
                    http["override-destination"] = true
                }
                sniff["HTTP"] = http
            }
            if !sniffer.tlsPorts.isEmpty {
                sniff["TLS"] = ["ports": sniffer.tlsPorts]
            }
            if !sniffer.quicPorts.isEmpty {
                sniff["QUIC"] = ["ports": sniffer.quicPorts]
            }
            patch["sniff"] = sniff
        }
        if !sniffer.skipDomain.isEmpty {
            patch["skip-domain"] = sniffer.skipDomain
        }
        if !sniffer.forceDomain.isEmpty {
            patch["force-domain"] = sniffer.forceDomain
        }
        if !sniffer.skipDstAddress.isEmpty {
            patch["skip-dst-address"] = sniffer.skipDstAddress
        }
        if !sniffer.skipSrcAddress.isEmpty {
            patch["skip-src-address"] = sniffer.skipSrcAddress
        }
        return patch
    }

    func normalizedDnsSettings(_ settings: DnsSettings) -> DnsSettings {
        var settings = settings
        settings.enhancedMode = ["fake-ip", "redir-host", "normal"].contains(settings.enhancedMode)
            ? settings.enhancedMode
            : "fake-ip"
        settings.listen = settings.listen.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.fakeIPRange = settings.fakeIPRange.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.fakeIPRange6 = settings.fakeIPRange6.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.fakeIPFilter = normalizedList(settings.fakeIPFilter)
        settings.fakeIPFilterMode = settings.fakeIPFilterMode.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultNameserver = normalizedList(settings.defaultNameserver)
        settings.nameserver = normalizedList(settings.nameserver)
        settings.fallback = normalizedList(settings.fallback)
        settings.proxyServerNameserver = normalizedList(settings.proxyServerNameserver)
        settings.directNameserver = normalizedList(settings.directNameserver)
        settings.fallbackFilter = settings.fallbackFilter.mapValues { value in
            switch value {
            case .bool(let b):
                return .bool(b)
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(normalizedList(arr))
            }
        }
        settings.nameserverPolicy = settings.nameserverPolicy.mapValues { value in
            switch value {
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(normalizedList(arr))
            }
        }
        settings.proxyServerNameserverPolicy = settings.proxyServerNameserverPolicy.mapValues { value in
            switch value {
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(normalizedList(arr))
            }
        }
        settings.hosts = settings.hosts.mapValues { value in
            switch value {
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(normalizedList(arr))
            }
        }
        settings.cacheAlgorithm = settings.cacheAlgorithm.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings
    }

    func normalizedSnifferSettings(_ settings: SnifferSettings) -> SnifferSettings {
        var settings = settings
        settings.httpPorts = settings.httpPorts.filter { $0 > 0 && $0 <= 65535 }
        settings.tlsPorts = settings.tlsPorts.filter { $0 > 0 && $0 <= 65535 }
        settings.quicPorts = settings.quicPorts.filter { $0 > 0 && $0 <= 65535 }
        settings.skipDomain = normalizedList(settings.skipDomain)
        settings.forceDomain = normalizedList(settings.forceDomain)
        settings.skipDstAddress = normalizedList(settings.skipDstAddress)
        settings.skipSrcAddress = normalizedList(settings.skipSrcAddress)
        return settings
    }

    func normalizedTunSettings(_ settings: TunSettings) -> TunSettings {
        var settings = settings
        settings.mtu = max(576, min(9000, settings.mtu))
        settings.stack = ["mixed", "gvisor", "system"].contains(settings.stack) ? settings.stack : "mixed"
        settings.dnsHijack = normalizedList(settings.dnsHijack)
        settings.routeExcludeAddress = normalizedList(settings.routeExcludeAddress)
        settings.device = settings.device?.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings
    }

    func normalizedList(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
