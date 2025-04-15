//
//  VisionService.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//

import Foundation
import Vision
import UIKit // For UIImage/CGImage conversion if needed, though Vision often works directly
import CoreImage // For CIContext potentially
import ImageIO // For efficient loading

enum VisionService {

    // Shared request handler options - potentially reusable
    private static let requestHandlerOptions: [VNImageOption: Any] = [:] // Add options if needed

    // Generates a feature print for a given image Data.
    // Returns VNFeaturePrintObservation or nil on failure.
    static func generateFeaturePrint(from data: Data) async -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest() // Create the request

        // Create a request handler with the image data
        // Using Data is generally efficient here
        let handler = VNImageRequestHandler(data: data, options: requestHandlerOptions)

        do {
            // Perform the request synchronously on the handler
            // Since this whole function will be called within a background Task, sync execution here is okay.
            try handler.perform([request])

            // Get the results
            guard let results = request.results,
                  let featurePrint = results.first else {
                print("VISION SERVICE: Failed to get feature print results.")
                return nil
            }
            // The feature print data is within featurePrint.data
            // The element count is featurePrint.elementCount
            // The distance calculation is done using computeDistance(_:to:)
            // print("VISION SERVICE: Generated feature print with \(featurePrint.elementCount) elements.") // Debug
            return featurePrint

        } catch {
            print("VISION SERVICE: Failed to perform Vision request: \(error)")
            return nil
        }
    }

    // Calculates the distance between two feature prints. Lower distance = more similar.
    // Returns Float? - nil if comparison fails.
    static func calculateDistance(between print1: VNFeaturePrintObservation, and print2: VNFeaturePrintObservation) -> Float? {
        do {
            var distance: Float = 0.0 // Needs to be initialized
            try print1.computeDistance(&distance, to: print2)
            // print("VISION SERVICE: Distance = \(distance)") // Debug
            return distance
        } catch {
            print("VISION SERVICE: Failed to compute distance: \(error)")
            return nil
        }
    }
}
