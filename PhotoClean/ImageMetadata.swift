//
//  ImageMetadata.swift
//  PhotoClean
//
//  Created by Nirdosh on 19/04/25.
//

import Foundation

// Struct to hold relevant metadata for display
struct ImageMetadata {
    var filename: String?
    var dateTaken: Date?
    var dimensions: CGSize? // Use CGSize for width/height
    var fileSize: Int64? // Use Int64 for bytes
    var sharpnessScore: Float? // Optional as calculation might fail
    var error: String? // To store any error during extraction
}
