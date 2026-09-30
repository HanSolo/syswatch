//
//  MetricsMonitor.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Combine
import Foundation
import SwiftUI

/// Scaling references for the two metrics that have no natural 100%.
struct MonitorConfig {
    /// Network: combined rx + tx bytes/sec that counts as 100%. Default: 1 Gbit/s = 125 MB/s.
    var maxNetworkBytesPerSec: Double = 125_000_000
    /// Disk: combined read + write bytes/sec that counts as 100%. Default: 2 GB/s.
    var maxDiskBytesPerSec: Double = 2_000_000_000
    /// How many top processes (by CPU and by memory) to report. 0 disables process sampling.
    var topProcessCount: Int = 3
}

/// Samples all metrics once per second and publishes the latest snapshot.
/// Sampling starts at app launch (see AppDelegate), independent of whether the window is open.
///
/// The samplers are cheap (well under a millisecond each), so everything runs on the
/// main actor for simplicity. Move the sampling to a background actor if that ever changes.
@MainActor
final class MetricsMonitor: ObservableObject {
    static let shared = MetricsMonitor()

    @Published private(set) var snapshot: MetricsSnapshot = .empty

    var config = MonitorConfig()

    /// Prints one line per tick so values can be compared with Activity Monitor.
    var logToConsole = true

    /// Hook for step 3: the WebSocket broadcaster will subscribe here.
    var onSnapshot: ((MetricsSnapshot) -> Void)?

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let networkSampler = NetworkSampler()
    private let diskSampler = DiskSampler()
    private let batterySampler = BatterySampler()
    private let processSampler = ProcessSampler()

    private var topProcesses: TopProcesses = .empty
    private var processSamplingInFlight = false
    private var tickCount = 0

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        let cpuPercent = cpuSampler.sample()
        let memory = memorySampler.sample()
        let network = networkSampler.sample()
        let disk = diskSampler.sample()
        let battery = batterySampler.sample()
        refreshTopProcesses()

        let networkTotal = network.rxBytesPerSec + network.txBytesPerSec
        let diskTotal = disk.readBytesPerSec + disk.writeBytesPerSec

        let newSnapshot = MetricsSnapshot(
            timestamp: Date(),
            cpuPercent: Self.clamp(cpuPercent),
            memoryPercent: Self.clamp(memory?.percent ?? 0),
            memoryUsedBytes: memory?.usedBytes ?? 0,
            memoryTotalBytes: memory?.totalBytes ?? 0,
            networkPercent: Self.clamp(networkTotal / config.maxNetworkBytesPerSec * 100),
            networkRxBytesPerSec: network.rxBytesPerSec,
            networkTxBytesPerSec: network.txBytesPerSec,
            diskPercent: Self.clamp(diskTotal / config.maxDiskBytesPerSec * 100),
            diskReadBytesPerSec: disk.readBytesPerSec,
            diskWriteBytesPerSec: disk.writeBytesPerSec,
            diskUsedBytes: disk.usedBytes,
            diskTotalBytes: disk.totalBytes,
            batteryPercent: battery.map { Self.clamp($0.percent) },
            batteryIsCharging: battery?.isCharging,
            batteryOnACPower: battery?.onACPower,
            batteryMinutesRemaining: battery?.minutesRemaining,
            topProcesses: topProcesses
        )

        snapshot = newSnapshot
        onSnapshot?(newSnapshot)

        if logToConsole {
            var batteryText = ""
            if let percent = newSnapshot.batteryPercent {
                let state = newSnapshot.batteryIsCharging == true ? "charging"
                    : (newSnapshot.batteryOnACPower == true ? "on AC" : "on battery")
                batteryText = String(format: "  batt %.0f%% (%@)", percent, state)
            }
            var processText = ""
            if let top = newSnapshot.topProcesses.byCPU.first {
                processText = String(format: "  top %@ %.0f%%", top.name, top.cpuPercent)
            }
            print(String(
                format: "cpu %5.1f%%  mem %5.1f%% (%.2f GiB)  net rx %.2f MB/s tx %.2f MB/s  disk r %.2f MB/s w %.2f MB/s",
                newSnapshot.cpuPercent,
                newSnapshot.memoryPercent,
                Double(newSnapshot.memoryUsedBytes) / 1_073_741_824,
                newSnapshot.networkRxBytesPerSec / 1_000_000,
                newSnapshot.networkTxBytesPerSec / 1_000_000,
                newSnapshot.diskReadBytesPerSec / 1_000_000,
                newSnapshot.diskWriteBytesPerSec / 1_000_000
            ) + batteryText + processText)
        }
    }

    /// Process sampling walks every process, so it runs off the main actor (in the
    /// ProcessSampler actor) and only on every 3rd tick. Snapshots carry the latest result.
    private func refreshTopProcesses() {
        defer { tickCount += 1 }
        let count = config.topProcessCount
        guard count > 0, tickCount % 3 == 0, !processSamplingInFlight else { return }

        processSamplingInFlight = true
        Task { [weak self, processSampler] in
            let result = await processSampler.sample(count: count)
            self?.topProcesses = result
            self?.processSamplingInFlight = false
        }
    }

    private nonisolated static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
