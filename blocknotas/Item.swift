//
//  Item.swift
//  blocknotas
//
//  Created by Moises rojas on 1/09/26.
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
