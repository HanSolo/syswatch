//
//  DiskSampler.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import IOKit


struct DiskReading {
    let readBytesPerSec  : Double
    let writeBytesPerSec : Double
    let usedBytes        : UInt64
    let totalBytes       : UInt64
}


final class DiskSampler {
    private var lastTotals : (read: UInt64, write: UInt64)?
    private var lastTime   : TimeInterval?

    func sample() -> DiskReading {
        let now = ProcessInfo.processInfo.systemUptime
        let totals = readTotals()
        let previousTotals = lastTotals
        let previousTime = lastTime
        if let totals {
            lastTotals = totals
            lastTime = now
        }

        var readRate = 0.0
        var writeRate = 0.0
        if let totals, let previousTotals, let previousTime, now > previousTime {
            let elapsed = now - previousTime
            // A device disappearing lowers the sum; treat that as "no I/O" instead of underflowing.
            let readDelta = totals.read >= previousTotals.read ? totals.read - previousTotals.read : 0
            let writeDelta = totals.write >= previousTotals.write ? totals.write - previousTotals.write : 0
            readRate = Double(readDelta) / elapsed
            writeRate = Double(writeDelta) / elapsed
        }

        let capacity = readCapacity()
        return DiskReading(
            readBytesPerSec: readRate,
            writeBytesPerSec: writeRate,
            usedBytes: capacity.used,
            totalBytes: capacity.total
        )
    }

    private func readTotals() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let property = IORegistryEntryCreateCFProperty(
                entry, "Statistics" as CFString, kCFAllocatorDefault, 0
            ) {
                if let stats = property.takeRetainedValue() as? [String: Any] {
                    read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                    write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (read, write)
    }

    private func readCapacity() -> (used: UInt64, total: UInt64) {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values    = try? url.resourceValues(forKeys: keys),
              let total     = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage,
              total > 0
        else { return (0, 0) }

        let used = max(Int64(total) - available, 0)
        return (UInt64(used), UInt64(total))
    }
}
