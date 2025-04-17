//
//  ThumbnailLoader.swift
//  PhotoClean
//
//  Created by Nirdosh on 17/04/25.
//

import Foundation
import UIKit

enum ThumbnailLoader {

    // Specifies the desired size for the thumbnail.
    static let thumbnailSize = CGSize(width: 100, height: 100) // Adjust as needed for UI

    // Asynchronously generates a thumbnail for the image at the given URL.
    // Returns nil if loading fails or the URL is invalid.
    // IMPORTANT: Assumes necessary file access permissions are already granted
    //            (e.g., parent folder scope is active when this is called,
    //             or bookmark needs resolving *before* calling this).
    static func generateThumbnail(for accessibleFileURL: URL) async -> UIImage? {
        var imageData: Data?
            do {
                // Load data first (might respect parent scope better)
                imageData = try Data(contentsOf: accessibleFileURL, options: .mappedIfSafe)
                 print("THUMBNAIL: Loaded data (\(imageData?.count ?? 0) bytes) for \(accessibleFileURL.lastPathComponent)")
            } catch {
                print("THUMBNAIL ERROR: Failed to load Data for \(accessibleFileURL.lastPathComponent): \(error)")
                return nil
            }

            guard let data = imageData, let fullImage = UIImage(data: data) else {
                 print("THUMBNAIL ERROR: Failed to create UIImage from loaded Data for \(accessibleFileURL.lastPathComponent)")
                 return nil
            }

        // 2. Now call the async thumbnail preparation method.
        do {
            let thumbnail = try await fullImage.preparingThumbnail(of: thumbnailSize)
            // print("THUMBNAIL: Generated for \(fileURL.lastPathComponent)") // Debug
            return thumbnail // Stop access is handled by defer
        } catch {
            print("THUMBNAIL ERROR: preparingThumbnail failed for \(accessibleFileURL.lastPathComponent): \(error)")
            return nil // Stop access is handled by defer
        }
    }
}
