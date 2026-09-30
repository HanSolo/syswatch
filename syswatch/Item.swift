//
//  Item.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
