//
//  NetworkSampler.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Darwin
import Foundation


struct NetworkReading {
    let rxBytesPerSec: Double
    let txBytesPerSec: Double
}


final class NetworkSampler {
    private typealias Counters = [String: (rx: UInt32, tx: UInt32)]

    private var lastCounters : Counters     = [:]
    private var lastTime     : TimeInterval?

    func sample() -> NetworkReading {
        let now              = ProcessInfo.processInfo.systemUptime
        let counters         = readCounters()
        let previousCounters = lastCounters
        let previousTime     = lastTime
        lastCounters = counters
        lastTime     = now

        guard let previousTime, now > previousTime else {
            return NetworkReading(rxBytesPerSec: 0, txBytesPerSec: 0)
        }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for (name, current) in counters {
            // An interface that just appeared has no baseline, so it contributes 0 this round.
            guard let old = previousCounters[name] else { continue }
            rx += UInt64(current.rx &- old.rx)
            tx += UInt64(current.tx &- old.tx)
        }

        let elapsed = now - previousTime
        return NetworkReading(
            rxBytesPerSec: Double(rx) / elapsed,
            txBytesPerSec: Double(tx) / elapsed
        )
    }

    private func readCounters() -> Counters {
        var result: Counters = [:]

        var listHead: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&listHead) == 0, let first = listHead else { return result }
        defer { freeifaddrs(listHead) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }

            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let rawData = entry.pointee.ifa_data
            else { continue }

            let flags = Int32(bitPattern: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }

            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            result[name] = (rx: data.ifi_ibytes, tx: data.ifi_obytes)
        }
        return result
    }
}
