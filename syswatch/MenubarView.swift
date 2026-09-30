//
//  MenubarView.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import SwiftUI


struct MenuBarView: View {
    @ObservedObject var monitor: MetricsMonitor

    var body: some View {
        let s = monitor.snapshot

        VStack(alignment: .leading, spacing: 14) {
            MetricRow(
                title: "CPU",
                systemImage: "cpu",
                percent: s.cpuPercent,
                detail: "Overall load, all cores"
            )
            MetricRow(
                title: "Memory",
                systemImage: "memorychip",
                percent: s.memoryPercent,
                detail: "\(Format.memory(s.memoryUsedBytes)) of \(Format.memory(s.memoryTotalBytes))"
            )
            MetricRow(
                title: "Network",
                systemImage: "network",
                percent: s.networkPercent,
                detail: "↓ \(Format.rate(s.networkRxBytesPerSec))   ↑ \(Format.rate(s.networkTxBytesPerSec))"
            )
            MetricRow(
                title: "SSD",
                systemImage: "internaldrive",
                percent: s.diskPercent,
                detail: "R \(Format.rate(s.diskReadBytesPerSec))   W \(Format.rate(s.diskWriteBytesPerSec))"
                    + "\n\(Format.file(s.diskUsedBytes)) of \(Format.file(s.diskTotalBytes)) used"
            )

            // Only shown on Macs with an internal battery.
            if let batteryPercent = s.batteryPercent {
                MetricRow(
                    title: "Battery",
                    systemImage: s.batteryIsCharging == true ? "battery.100.bolt" : "battery.75",
                    percent: batteryPercent,
                    detail: batteryDetail(s),
                    lowIsBad: true,
                    suppressWarning: s.batteryOnACPower == true
                )
            }

            Divider()

            HStack {
                Text("Network scale: \(Format.rate(monitor.config.maxNetworkBytesPerSec)) = 100%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func batteryDetail(_ s: MetricsSnapshot) -> String {
        let minutes = s.batteryMinutesRemaining.map(Format.duration)
        if s.batteryIsCharging == true {
            return minutes.map { "Charging, \($0) to full" } ?? "Charging"
        }
        if s.batteryOnACPower == true {
            return (s.batteryPercent ?? 0) >= 99 ? "Plugged in, fully charged" : "Plugged in, not charging"
        }
        return minutes.map { "On battery, \($0) left" } ?? "On battery"
    }
}

private struct MetricRow: View {
    let title: String
    let systemImage: String
    let percent: Double
    let detail: String
    /// For the battery: a low value is the bad case, so the colours are inverted.
    var lowIsBad = false
    /// Skip warning colours, e.g. a low battery that is currently charging is not a problem.
    var suppressWarning = false

    private var fraction: Double { min(max(percent, 0), 100) / 100 }

    private var barColor: Color {
        if lowIsBad {
            if suppressWarning { return .green }
            switch percent {
            case ..<10: return .red
            case ..<20: return .yellow
            default: return .green
            }
        }
        switch percent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Text("\(Int(percent.rounded())) %")
                    .font(.headline)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.3), value: fraction)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private enum Format {
    nonisolated static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    nonisolated static func file(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    nonisolated static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    nonisolated static func rate(_ bytesPerSec: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file) + "/s"
    }
}
