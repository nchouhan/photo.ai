//
//  ImageHasher.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//

import Foundation
import UIKit // To get UIImage and CGImage capabilities easily
import CryptoKit // For SHA256 hashing
import CoreGraphics // For CGImage handling
import ImageIO // For more efficient image loading options

enum ImageHasher {

    // Generates a SHA-256 hash string from the pixel data of an image at a given URL.
    // Returns nil if the image cannot be read or processed.
    static func generatePixelHash(for imageURL: URL) -> String? {
        print("HASHER: Attempting hash for \(imageURL.lastPathComponent)")
        // Ensure we can access the file pointed to by the security-scoped URL
        guard imageURL.startAccessingSecurityScopedResource() else {
            print("Error: Could not start accessing security-scoped resource for hashing: \(imageURL.lastPathComponent)")
            // Don't stop accessing here if we failed to start
            return nil
        }
        // Ensure we stop accessing it when we're done
        defer { imageURL.stopAccessingSecurityScopedResource() }

        // --- Method using ImageIO for potentially better memory efficiency ---
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("HASHER ERROR: Could not create CGImage for \(imageURL.lastPathComponent)")
            return nil
        }
        print("HASHER: Got CGImage for \(imageURL.lastPathComponent)")

        // --- Alternative Method using UIImage (simpler, potentially more memory) ---
        // guard let image = UIImage(contentsOfFile: imageURL.path), // Use path for UIImage initializer
        //       let cgImage = image.cgImage else {
        //     print("Error: Could not load UIImage or get CGImage from URL: \(imageURL.lastPathComponent)")
        //     return nil
        // }
        // --- End Alternative ---


        // Get the pixel data provider
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else {
            print("HASHER ERROR: Could not get pixel data for \(imageURL.lastPathComponent)")
            return nil
        }
        let dataLength = CFDataGetLength(pixelData)
        print("HASHER: Got pixel data (\(dataLength) bytes) for \(imageURL.lastPathComponent)")
        // Calculate the SHA-256 hash of the pixel data
        let hash = SHA256.hash(data: pixelData as Data) // Cast CFData to Data
        let hexString = hash.hexString // Use extension if you added it
        print("HASHER: Calculated hash for \(imageURL.lastPathComponent)")
        // Convert the hash Digest to a hexadecimal string representation
        return hexString
    }
    
    // NEW function: Hashes raw Data
    static func generatePixelHash(from data: Data) -> String? {
        // Create CGImageSource from Data
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("HASHER ERROR (Data): Could not create CGImage from data.")
            return nil
        }
        print("HASHER (Data): Got CGImage.")

        // Get pixel data
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else {
            print("HASHER ERROR (Data): Could not get pixel data from CGImage.")
            return nil
        }
        let dataLength = CFDataGetLength(pixelData)
        print("HASHER (Data): Got pixel data (\(dataLength) bytes).")

        // Calculate hash
        let hash = SHA256.hash(data: pixelData as Data)
        let hexString = hash.hexString
        print("HASHER (Data): Calculated hash.")

        return hexString
    }
}

// Optional Extension to make Digest to Hex String conversion reusable
extension Digest {
    var hexString: String {
        return self.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// Example usage of extension:
// let hash = SHA256.hash(data: someData)
// let hexHashString = hash.hexString
