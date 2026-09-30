//
//  BatterySampler.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import IOKit.ps


struct BatteryReading {

    let percent          : Double
    let isCharging       : Bool
    let onACPower        : Bool
    let minutesRemaining : Int?
}


final class BatterySampler {
    func sample() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }

            let percent    = min(max(Double(current) / Double(maximum) * 100, 0), 100)
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onACPower  = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let minutesKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            var minutes    = description[minutesKey] as? Int
            if let value = minutes, value < 0 { minutes = nil }   // -1 means "still calculating"
            if onACPower && !isCharging { minutes = nil }         // fully charged, nothing to estimate

            return BatteryReading(percent: percent, isCharging: isCharging, onACPower: onACPower, minutesRemaining: minutes)
        }
        return nil
    }
}
