//
//  DuplicateGroup.swift
//  PhotoClean
//
//  Created by Nirdosh on 17/04/25.
//

import Foundation // For UUID and URL

// Data structure for a group of duplicate/similar photos
struct DuplicateGroup: Identifiable, Hashable {
    let id = UUID() // For Identifiable conformance in SwiftUI lists
    let urls: [URL] // Original URLs in the group
    var bestURL: URL? = nil // Suggested best URL based on quality
    let isExact: Bool // True for exact, False for near-duplicate

    // Minimal Hashable conformance based on ID is usually sufficient for ForEach
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Minimal Equatable conformance (needed for Hashable)
    static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        lhs.id == rhs.id
    }
}
