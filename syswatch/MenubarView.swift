//
//  MenubarView.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import SwiftUI


import SwiftUI

struct MenuBarView: View {
    @ObservedObject                 var         monitor       : MetricsMonitor
    @AppStorage("showTopProcesses") private var showProcesses : Bool        = false
    @State                          private var processSort   : ProcessSort = .cpu

    var body: some View {
        let s = monitor.snapshot

        VStack(alignment: .leading, spacing: 14) {
            MetricRow(
                title      : "CPU",
                systemImage: "cpu",
                percent    : s.cpuPercent,
                detail     : cpuDetail(s)
            )
            MetricRow(
                title      : "Memory",
                systemImage: "memorychip",
                percent    : s.memoryPercent,
                detail     : memoryDetail(s)
            )
            MetricRow(
                title      : "Network",
                systemImage: "network",
                percent    : s.networkPercent,
                detail     : "↓ \(Format.rate(s.networkRxBytesPerSec))   ↑ \(Format.rate(s.networkTxBytesPerSec))"
            )
            MetricRow(
                title      : "SSD",
                systemImage: "internaldrive",
                percent    : s.diskPercent,
                detail     : "R \(Format.rate(s.diskReadBytesPerSec))   W \(Format.rate(s.diskWriteBytesPerSec))\n\(Format.file(s.diskUsedBytes)) of \(Format.file(s.diskTotalBytes)) used"
            )

            // Only shown on Macs with an internal battery.
            if let batteryPercent = s.batteryPercent {
                MetricRow(
                    title          : "Battery",
                    systemImage    : s.batteryIsCharging == true ? "battery.100.bolt" : "battery.75",
                    percent        : batteryPercent,
                    detail         : batteryDetail(s),
                    lowIsBad       : true,
                    suppressWarning: s.batteryOnACPower == true
                )
            }

            // Only offered when process sampling returned something.
            if !s.topProcesses.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $showProcesses) {
                    ProcessList(sort: $processSort, processes: s.topProcesses)
                        .padding(.top, 8)
                } label: {
                    Label("Top processes", systemImage: "list.number")
                        .font(.headline)
                }
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

    private func cpuDetail(_ s: MetricsSnapshot) -> String {
        let top = s.topProcesses.byCPU.prefix(2).map { "\($0.name) \(Int($0.cpuPercent.rounded())) %" }
        return top.isEmpty ? "Overall load, all cores" : "Top: " + top.joined(separator: ", ")
    }

    private func memoryDetail(_ s: MetricsSnapshot) -> String {
        var text = "\(Format.memory(s.memoryUsedBytes)) of \(Format.memory(s.memoryTotalBytes))"
        let top  = s.topProcesses.byMemory.prefix(2).map { "\($0.name) \(Format.memory($0.memoryBytes))" }
        if !top.isEmpty {
            text += "\nTop: " + top.joined(separator: ", ")
        }
        return text
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

private enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu    = "CPU"
    case memory = "Memory"
    var id: Self { self }
}

// The heaviest processes, sorted by CPU or by memory. CPU is shown as a share of one core, like Activity Monitor, so a busy multi-threaded process can exceed 100 %.
private struct ProcessList: View {
    @Binding var sort: ProcessSort
    let processes: TopProcesses


    private var rows: [ProcessUsage] {
        Array((sort == .cpu ? processes.byCPU : processes.byMemory).prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Sort by", selection: $sort) {
                ForEach(ProcessSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rows.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.pid) { process in
                HStack(spacing: 6) {
                    Text(process.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(process.pid)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text(sort == .cpu
                         ? "\(Int(process.cpuPercent.rounded())) %"
                         : Format.memory(process.memoryBytes))
                        .monospacedDigit()
                        .foregroundStyle(sort == .cpu && process.cpuPercent >= 100 ? Color.orange : Color.primary)
                }
                .font(.callout)
            }
            if sort == .cpu {
                Text("% of one core")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricRow: View {
    let title      : String
    let systemImage: String
    let percent    : Double
    let detail     : String
    
    var lowIsBad        : Bool = false /// For the battery: a low value is the bad case, so the colours are inverted.
    var suppressWarning : Bool = false /// Skip warning colours, e.g. a low battery that is currently charging is not a problem.
    
    private var fraction: Double { min(max(percent, 0), 100) / 100 }
    private var barColor: Color {
        if lowIsBad {
            if suppressWarning { return .green }
            switch percent {
                case ..<10 : return .red
                case ..<20 : return .yellow
                default    : return .green
            }
        }
        switch percent {
            case ..<60 : return .green
            case ..<85 : return .orange
            default    : return .red
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
