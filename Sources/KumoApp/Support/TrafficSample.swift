import Foundation

/// A single throughput data point captured from mihomo's `/traffic`
/// WebSocket. The Overview Traffic card keeps a rolling buffer of these
/// samples so it can render a 60-second sparkline when expanded.
///
/// View-layer concern only — this type is intentionally not exposed from
/// `KumoCoreKit`, which keeps `TrafficSnapshot` strictly one-shot.
struct TrafficSample: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    /// Upload speed in bytes per second at the time of capture.
    let upload: Int
    /// Download speed in bytes per second at the time of capture.
    let download: Int

    var total: Int { upload + download }
}
