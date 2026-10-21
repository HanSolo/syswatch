//
//  ProcessSampler.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import Darwin



/// One process as reported to consumers.
nonisolated struct ProcessUsage: Codable, Sendable, Equatable {
    let pid         : Int32
    let name        : String
    let cpuPercent  : Double // Percent of ONE core, so a process using three cores fully shows about 300.
    let memoryBytes : UInt64 // Physical footprint, the figure Activity Monitor shows in its Memory column.
}

nonisolated struct TopProcesses: Codable, Sendable, Equatable {
    var byCPU    : [ProcessUsage] = []
    var byMemory : [ProcessUsage] = []

    static let empty = TopProcesses()

    var isEmpty: Bool { byCPU.isEmpty && byMemory.isEmpty }
}

// Finds the processes using the most CPU and memory, via libproc.
//
// This walks every process, so it is an actor: it runs off the main actor, and the
// monitor only calls it every few ticks. CPU load is the delta of each process's
// cumulative CPU time between two calls, so the first call reports no CPU ranking.
//
// Inside the App Sandbox, macOS may refuse to hand out information about other
// processes. The sampler then returns an empty or partial list and prints one warning.
actor ProcessSampler {
    
    private struct Sample {
        let pid       : Int32
        let cpuTimeNs : UInt64
        let footprint : UInt64
    }

    
    private let timebase         : mach_timebase_info_data_t
    private var previousCPUTime  : [Int32: UInt64] = [:]
    private var previousUptimeNs : UInt64?
    private var didWarn          : Bool            = false

    
    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = info
    }

    
    func sample(count: Int) -> TopProcesses {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let pids  = listPIDs()

        var samples : [Sample] = []
        samples.reserveCapacity(pids.count)
        var failures = 0

        for pid in pids {
            var usage  = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { raw in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, raw)
                }
            }
            guard result == 0 else {
                failures += 1
                continue
            }
            samples.append(Sample(pid: pid, cpuTimeNs: nanoseconds(usage.ri_user_time &+ usage.ri_system_time), footprint: usage.ri_phys_footprint))
        }
        warnIfUnreadable(total: pids.count, failures: failures)

        // CPU percent per process from the delta since the previous call.
        var cpuPercent: [Int32: Double] = [:]
        if let previousUptimeNs, nowNs > previousUptimeNs {
            let elapsedNs = Double(nowNs - previousUptimeNs)
            for sample in samples {
                if let old = previousCPUTime[sample.pid], sample.cpuTimeNs >= old {
                    cpuPercent[sample.pid] = Double(sample.cpuTimeNs - old) / elapsedNs * 100
                }
            }
        }
        previousCPUTime = Dictionary(
            samples.map { ($0.pid, $0.cpuTimeNs) },
            uniquingKeysWith: { _, latest in latest }
        )
        previousUptimeNs = nowNs

        let topCPU = samples
            .filter { (cpuPercent[$0.pid] ?? 0) > 0 }
            .sorted { (cpuPercent[$0.pid] ?? 0) > (cpuPercent[$1.pid] ?? 0) }
            .prefix(count)
            .map { usage(for: $0, cpu: cpuPercent[$0.pid] ?? 0) }

        let topMemory = samples
            .sorted { $0.footprint > $1.footprint }
            .prefix(count)
            .map { usage(for: $0, cpu: cpuPercent[$0.pid] ?? 0) }

        return TopProcesses(byCPU: Array(topCPU), byMemory: Array(topMemory))
    }

    // MARK: - Helpers

    private func listPIDs() -> [Int32] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }

        // Extra room in case processes start between the two calls.
        var pids = [Int32](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<Int32>.size + 64)
        let bytes = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size)
        )
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    private func nanoseconds(_ ticks: UInt64) -> UInt64 {
        guard timebase.denom != 0 else { return ticks }
        return ticks &* UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private func usage(for sample: Sample, cpu: Double) -> ProcessUsage {
        var buffer = [CChar](repeating: 0, count: 64)
        let length = proc_name(sample.pid, &buffer, UInt32(buffer.count))
        let name: String
        if length > 0 {
            let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            name = String(decoding: bytes, as: UTF8.self)
        } else {
            name = "pid \(sample.pid)"
        }
        return ProcessUsage(pid: sample.pid, name: name, cpuPercent: cpu, memoryBytes: sample.footprint)
    }

    private func warnIfUnreadable(total: Int, failures: Int) {
        guard !didWarn, total == 0 || failures * 2 > total else { return }
        didWarn = true
        print("ProcessSampler: could not read \(failures) of \(total) processes. The App Sandbox probably blocks process information, so the top-process list will be incomplete or empty.")
    }
}
