//
//  MetricsSnapshot.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation

/// One point-in-time reading of all four metrics.
/// Percent values are 0...100. Raw values are included so consumers
/// (for example the Java agent later on) can do their own scaling.
///
/// NOTE: This shape is provisional. It becomes the WebSocket JSON contract in step 3.
struct MetricsSnapshot: Codable, Equatable, Sendable {
    var timestamp: Date

    var cpuPercent: Double

    var memoryPercent: Double
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64

    var networkPercent: Double
    var networkRxBytesPerSec: Double
    var networkTxBytesPerSec: Double

    var diskPercent: Double
    var diskReadBytesPerSec: Double
    var diskWriteBytesPerSec: Double
    var diskUsedBytes: UInt64
    var diskTotalBytes: UInt64

    /// Battery fields are nil on Macs without an internal battery.
    /// With the synthesized Codable conformance, nil values are omitted from the JSON.
    var batteryPercent: Double? = nil
    var batteryIsCharging: Bool? = nil
    var batteryOnACPower: Bool? = nil
    var batteryMinutesRemaining: Int? = nil

    static let empty = MetricsSnapshot(
        timestamp: .distantPast,
        cpuPercent: 0,
        memoryPercent: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: 0,
        networkPercent: 0,
        networkRxBytesPerSec: 0,
        networkTxBytesPerSec: 0,
        diskPercent: 0,
        diskReadBytesPerSec: 0,
        diskWriteBytesPerSec: 0,
        diskUsedBytes: 0,
        diskTotalBytes: 0
    )
}
