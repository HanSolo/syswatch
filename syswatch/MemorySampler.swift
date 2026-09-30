//
//  MemorySampler.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Darwin
import Foundation


struct MemoryReading {
    let percent    : Double
    let usedBytes  : UInt64
    let totalBytes : UInt64
}


final class MemorySampler {
    private let totalBytes = ProcessInfo.processInfo.physicalMemory

    func sample() -> MemoryReading? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        var stats  = vm_statistics64()
        var count  = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rawPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let internalPages   = UInt64(stats.internal_page_count)
        let purgeablePages  = UInt64(stats.purgeable_count)
        let appPages        = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let wiredPages      = UInt64(stats.wire_count)
        let compressedPages = UInt64(stats.compressor_page_count)

        let usedBytes       = (appPages + wiredPages + compressedPages) * UInt64(pageSize)
        let percent         = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0

        return MemoryReading(percent: percent, usedBytes: usedBytes, totalBytes: totalBytes)
    }
}
