//
//  CPUSampler.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import Darwin


final class CPUSampler {
    
    private struct Ticks {
        var user   : UInt32
        var system : UInt32
        var idle   : UInt32
        var nice   : UInt32
    }

    private var previous: Ticks?


    func sample() -> Double {
        guard let current = readTicks() else { return 0 }
        let old = previous
        previous = current
        guard let old else { return 0 }

        // Counters are 32-bit and wrap, so use wrapping subtraction.
        let user   = Double(current.user &- old.user)
        let system = Double(current.system &- old.system)
        let nice   = Double(current.nice &- old.nice)
        let idle   = Double(current.idle &- old.idle)

        let busy   = user + system + nice
        let total  = busy + idle
        guard total > 0 else { return 0 }
        return busy / total * 100
    }

    private func readTicks() -> Ticks? {
        var info  = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rawPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // Index order: 0 = user, 1 = system, 2 = idle, 3 = nice
        return Ticks(
            user   : info.cpu_ticks.0,
            system : info.cpu_ticks.1,
            idle   : info.cpu_ticks.2,
            nice   : info.cpu_ticks.3
        )
    }
}
