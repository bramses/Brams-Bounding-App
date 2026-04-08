//
//  Models.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import Foundation
import SwiftData
import UIKit

// Represents a single bounding box on an image
@Model
final class BoundingBox {
    var id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var extractedText: String
    var timestamp: Date
    var page: SavedPage?
    
    init(x: Double, y: Double, width: Double, height: Double, extractedText: String = "") {
        self.id = UUID()
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.extractedText = extractedText
        self.timestamp = Date()
    }
}

// Represents a saved page with its original image and extracted bounding boxes
@Model
final class SavedPage {
    var id: UUID
    var imageData: Data
    var timestamp: Date
    @Relationship(deleteRule: .cascade, inverse: \BoundingBox.page)
    var boundingBoxes: [BoundingBox]
    
    init(imageData: Data) {
        self.id = UUID()
        self.imageData = imageData
        self.timestamp = Date()
        self.boundingBoxes = []
    }
    
    var image: UIImage? {
        UIImage(data: imageData)
    }
}
