//
//  WireSnapshot.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation

import Foundation

/// The JSON contract for WebSocket clients (version 1).
///
/// It is deliberately separate from `MetricsSnapshot`: the internal model can change
/// freely, while this shape is what the Java side depends on.
///
/// Example message:
/// ```json
/// {
///   "type": "snapshot",
///   "version": 1,
///   "timestamp": "2026-09-30T14:03:12Z",
///   "cpu":     { "percent": 23.4, "cores": 10 },
///   "memory":  { "percent": 61.2, "usedBytes": 10485760000, "totalBytes": 17179869184 },
///   "network": { "percent": 4.1, "rxBytesPerSec": 123456, "txBytesPerSec": 7890, "scaleMaxBytesPerSec": 125000000 },
///   "disk":    { "percent": 0.8, "readBytesPerSec": 0, "writeBytesPerSec": 52000,
///                "usedBytes": 210000000000, "totalBytes": 500000000000, "scaleMaxBytesPerSec": 2000000000 },
///   "battery": { "percent": 87, "charging": false, "onACPower": false, "minutesRemaining": 192 },
///   "topProcesses": {
///     "cpu":    [ { "pid": 4711, "name": "Xcode", "cpuPercent": 182.4, "memoryBytes": 3100000000 } ],
///     "memory": [ { "pid": 4711, "name": "Xcode", "cpuPercent": 182.4, "memoryBytes": 3100000000 } ]
///   }
/// }
/// ```
/// `topProcesses` is omitted when process sampling is off or macOS refuses to list processes;
/// it is refreshed about every 3 seconds, so consecutive snapshots may repeat it.
/// Per-process `cpuPercent` is relative to one core (maximum = cores * 100).
/// `battery` is omitted on Macs without an internal battery, and `minutesRemaining`
/// is omitted while macOS has no estimate. `scaleMaxBytesPerSec` tells the consumer what
/// 100% means for network and disk.
struct WireSnapshot: Encodable {
    struct CPU: Encodable {
        let percent: Double
        /// Logical cores. Per-process cpuPercent is relative to ONE core (max = cores * 100).
        let cores: Int
    }

    struct Memory: Encodable {
        let percent: Double
        let usedBytes: UInt64
        let totalBytes: UInt64
    }

    struct Network: Encodable {
        let percent: Double
        let rxBytesPerSec: Double
        let txBytesPerSec: Double
        let scaleMaxBytesPerSec: Double
    }

    struct Disk: Encodable {
        let percent: Double
        let readBytesPerSec: Double
        let writeBytesPerSec: Double
        let usedBytes: UInt64
        let totalBytes: UInt64
        let scaleMaxBytesPerSec: Double
    }

    struct Battery: Encodable {
        let percent: Double
        let charging: Bool
        let onACPower: Bool
        let minutesRemaining: Int?
    }

    struct ProcessEntry: Encodable {
        let pid: Int32
        let name: String
        /// Percent of one core; a process using three cores fully shows about 300.
        let cpuPercent: Double
        let memoryBytes: UInt64

        init(_ usage: ProcessUsage) {
            pid = usage.pid
            name = usage.name
            cpuPercent = WireSnapshot.round1(usage.cpuPercent)
            memoryBytes = usage.memoryBytes
        }
    }

    struct Processes: Encodable {
        let cpu: [ProcessEntry]
        let memory: [ProcessEntry]
    }

    let type = "snapshot"
    let version = 1
    let timestamp: Date
    let cpu: CPU
    let memory: Memory
    let network: Network
    let disk: Disk
    let battery: Battery?
    let topProcesses: Processes?

    init(snapshot s: MetricsSnapshot, config: MonitorConfig) {
        timestamp = s.timestamp
        cpu = CPU(
            percent: Self.round1(s.cpuPercent),
            cores: ProcessInfo.processInfo.activeProcessorCount
        )
        memory = Memory(
            percent: Self.round1(s.memoryPercent),
            usedBytes: s.memoryUsedBytes,
            totalBytes: s.memoryTotalBytes
        )
        network = Network(
            percent: Self.round1(s.networkPercent),
            rxBytesPerSec: s.networkRxBytesPerSec.rounded(),
            txBytesPerSec: s.networkTxBytesPerSec.rounded(),
            scaleMaxBytesPerSec: config.maxNetworkBytesPerSec
        )
        disk = Disk(
            percent: Self.round1(s.diskPercent),
            readBytesPerSec: s.diskReadBytesPerSec.rounded(),
            writeBytesPerSec: s.diskWriteBytesPerSec.rounded(),
            usedBytes: s.diskUsedBytes,
            totalBytes: s.diskTotalBytes,
            scaleMaxBytesPerSec: config.maxDiskBytesPerSec
        )
        if let percent = s.batteryPercent {
            battery = Battery(
                percent: Self.round1(percent),
                charging: s.batteryIsCharging ?? false,
                onACPower: s.batteryOnACPower ?? false,
                minutesRemaining: s.batteryMinutesRemaining
            )
        } else {
            battery = nil
        }

        if s.topProcesses.isEmpty {
            topProcesses = nil
        } else {
            topProcesses = Processes(
                cpu: s.topProcesses.byCPU.map { ProcessEntry($0) },
                memory: s.topProcesses.byMemory.map { ProcessEntry($0) }
            )
        }
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
