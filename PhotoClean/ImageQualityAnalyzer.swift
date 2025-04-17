//
//  ImageQualityAnalyzer.swift
//  PhotoClean
//
//  Created by Nirdosh on 16/04/25.
//

import Foundation
import UIKit
import CoreImage // For filters like CILaplacian
import Accelerate // For vImage variance calculation (more efficient)




enum ImageQualityAnalyzer {

    // Shared CIContext for efficiency
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    // Calculates sharpness score based on average edge intensity using CIEdges.
    // Higher score = more prominent edges = potentially sharper.
    static func calculateSharpnessScore(from data: Data) -> Float? {

        // 1. Create CIImage using ImageIO for robustness (as determined earlier)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            print("QUALITY (Edges): Failed to create CGImage using ImageIO.")
            return nil
        }
        let ciImage = CIImage(cgImage: cgImage)
        print("QUALITY (Edges): Created CIImage from CGImage. Extent: \(ciImage.extent)")

        // Check for valid extent right after creation
        let imageExtent = ciImage.extent
        guard !imageExtent.isInfinite, !imageExtent.isEmpty else {
            print("QUALITY (Edges): Invalid CIImage extent: \(imageExtent).")
            return nil
        }

        // 2. Apply CIEdges filter
        print("QUALITY (Edges): Attempting to create CIEdges filter...")
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            print("QUALITY (Edges): Failed to create CIEdges filter.") // If this fails, CI is very broken
            return nil
        }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        // edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey) // Optional: Adjust intensity if needed

        guard let edgeOutputImage = edgeFilter.outputImage else {
            print("QUALITY (Edges): Failed to get output image from CIEdges filter.")
            return nil
        }
        print("QUALITY (Edges): Successfully created CIEdges output.")

        // 3. Calculate average brightness of the edge output image
        // Use the extent of the *edge output*, which might differ slightly if clamps occur
        guard let edgeExtent = edgeOutputImage.extent.isInfinite ? nil : edgeOutputImage.extent, !edgeExtent.isEmpty else {
            print("QUALITY (Edges): Invalid extent for edge output: \(edgeOutputImage.extent)")
            return nil
        }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else {
            print("QUALITY (Edges): Failed to create CIAreaAverage filter.")
            return nil
        }

        let extentVector = CIVector(x: edgeExtent.origin.x, y: edgeExtent.origin.y, z: edgeExtent.size.width, w: edgeExtent.size.height)
        avgFilter.setValue(edgeOutputImage, forKey: kCIInputImageKey) // Input is edge output
        avgFilter.setValue(extentVector, forKey: kCIInputExtentKey)

        guard let averageOutputImage = avgFilter.outputImage else {
            print("QUALITY (Edges): Failed to get output image from AreaAverage filter.")
            return nil
        }

        // 4. Render the 1x1 average output image and extract the pixel value
        var avgPixel: [UInt8] = [0, 0, 0, 0] // RGBA buffer for output
        let outputRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        // Use the original image's colorspace if available, otherwise default RGB
        let outputColorSpace = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        ciContext.render(averageOutputImage,
                         toBitmap: &avgPixel,
                         rowBytes: 4,
                         bounds: outputRect,
                         format: .RGBA8,
                         colorSpace: outputColorSpace)

        // CIEdges output is grayscale (R=G=B). We take one channel (e.g., Red)
        // as the average edge intensity.
        let averageEdgeIntensity = Float(avgPixel[0]) / 255.0 // Normalize to 0.0-1.0

        print("QUALITY (Edges): Calculated average edge intensity (sharpness proxy): \(averageEdgeIntensity)")
        return averageEdgeIntensity
    }
}
