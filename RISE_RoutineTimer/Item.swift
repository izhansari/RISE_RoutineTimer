//
//  Item.swift
//  RISE_RoutineTimer
//
//  Created by Izhan S Ansari on 5/13/26.
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
