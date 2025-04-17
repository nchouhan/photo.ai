//
//  DocumentPicker.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers // Needed for UTType.folder

// SwiftUI view that wraps UIDocumentPickerViewController
struct DocumentPicker: UIViewControllerRepresentable {

    // Binding to pass the selected folder URL back to the ContentView
    @Binding var selectedFolderURL: URL?
    // Binding to pass the list of image URLs back
    @Binding var imageFileURLs: [URL]
    // Binding to potentially show errors
    @Binding var errorMessage: String?

    // Creates the UIKit view controller instance
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Request access to folders (directories)
        // For iOS 14+ we use UTType.folder
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        picker.delegate = context.coordinator // Set the delegate to handle callbacks
        return picker
    }

    // Updates the view controller (not needed for this simple case)
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No update needed here
    }

    // Creates the Coordinator class to handle delegate methods
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator Class
    // Acts as the delegate for UIDocumentPickerViewController
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        // Delegate method called when the user selects a folder (or cancels)
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { /* ... error handling ... */ return }
            print("Coordinator: Received URL: \(url.path)")

            Task { // Delayed Task
                print("Coordinator: Waiting for delay before access attempt...")
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

                print("Coordinator: Attempting initial access (after delay)...")
                guard url.startAccessingSecurityScopedResource() else {
                    // ... (Handle access failure as before: print, update parent, return) ...
                    print("Coordinator ERROR: Failed initial access AFTER DELAY to \(url.lastPathComponent).")
                    await MainActor.run {
                        self.parent.errorMessage = "Could not access folder '\(url.lastPathComponent)'. Please check permissions or try selecting again."
                        self.parent.selectedFolderURL = nil
                        self.parent.imageFileURLs = []
                    }
                    return // Exit Task
                }

                // --- Access Succeeded ---
                print("Coordinator: Initial access GRANTED (after delay).")
                defer {
                    url.stopAccessingSecurityScopedResource()
                    print("Coordinator: Stopped initial access (after successful grant).")
                }

                // --- Save Bookmark Data (iOS Style - AFTER getting access) ---
                do {
                    let bookmarkData = try url.bookmarkData(options: [], // No scope option needed here
                                                           includingResourceValuesForKeys: nil,
                                                           relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: "selectedFolderBookmark")
                    UserDefaults.standard.set(url.lastPathComponent, forKey: "selectedFolderName") // Save name
                    print("Coordinator: Bookmark data saved successfully.")
                } catch {
                    print("Coordinator ERROR: Failed to create bookmark data: \(error)")
                    // Decide if this is critical. Maybe just warn the user?
                    // Or update the error message on the parent view?
                     await MainActor.run {
                          self.parent.errorMessage = "Could access folder, but failed to save permission for next time."
                     }
                     // Clear any potentially old/invalid bookmark
                     UserDefaults.standard.removeObject(forKey: "selectedFolderBookmark")
                     UserDefaults.standard.removeObject(forKey: "selectedFolderName")
                     // Continue with file listing anyway for this session...
                }
                // --- End Bookmark Saving ---

                // Update parent URL for display (on main thread)
                await MainActor.run {
                     self.parent.selectedFolderURL = url
                     self.parent.errorMessage = nil // Clear error if bookmark failed but access worked
                }

                // Find files
                print("Coordinator: Proceeding to findImageFiles...")
                self.findImageFiles(at: url)

            } // End of Task
            print("Coordinator: Delegate method finished (Task scheduled).")
        }

        // Delegate method called if the user cancels the picker
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Document picker was cancelled.")
            // Optionally reset state or show a message, but often just closing is fine
            parent.errorMessage = nil // Clear any previous error
        }

        // --- File Enumeration Logic ---

        // Recursively finds image files in the given directory URL
        private func findImageFiles(at directoryURL: URL) {
            var foundImageURLs: [URL] = []
            parent.errorMessage = nil // Clear previous errors

            // Define the image types we're interested in using UTTypes (more robust)
            let imageTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .gif, .bmp] // Add more if needed

            // Use FileManager to enumerate directory contents
            let fileManager = FileManager.default
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .contentTypeKey] // Properties to fetch
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

            guard let enumerator = fileManager.enumerator(at: directoryURL,
                                                          includingPropertiesForKeys: resourceKeys,
                                                          options: options,
                                                          errorHandler: { url, error -> Bool in
                // Handle errors during enumeration (e.g., permission issues on subfolders)
                print("Error enumerating \(url.path): \(error.localizedDescription)")
                // Update the error message binding to inform the user
                // Dispatch to main queue for UI updates
                DispatchQueue.main.async {
                    self.parent.errorMessage = "Error scanning folder: \(error.localizedDescription)"
                }
                return true // Continue enumeration even if one file fails
            }) else {
                print("Failed to create file enumerator for \(directoryURL.path)")
                DispatchQueue.main.async {
                     self.parent.errorMessage = "Could not read contents of the folder."
                }
                return
            }

            // Iterate through the enumerated files/directories
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))

                    // Skip directories
                    if resourceValues.isDirectory == true {
                        continue
                    }

                    // Check if the file's content type conforms to any known image type
                    if let contentType = resourceValues.contentType, imageTypes.contains(where: { contentType.conforms(to: $0) }) {
                        foundImageURLs.append(fileURL)
                    }
                    // Fallback check using path extension if content type fails (less reliable)
                    // else {
                    //     let pathExtension = fileURL.pathExtension.lowercased()
                    //     let imageExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp"]
                    //     if imageExtensions.contains(pathExtension) {
                    //          foundImageURLs.append(fileURL)
                    //     }
                    // }

                } catch {
                    print("Error getting resource values for \(fileURL.path): \(error)")
                    // Don't necessarily stop the whole process, but log the error
                }
            }

            // Update the parent view's state with the found image URLs
            // Ensure UI updates happen on the main thread
            DispatchQueue.main.async {
                self.parent.imageFileURLs = foundImageURLs
                if foundImageURLs.isEmpty && self.parent.errorMessage == nil {
                    // Only show this message if no other error occurred
                    self.parent.errorMessage = "No image files found in the selected folder or its subfolders."
                }
                print("Found \(foundImageURLs.count) image files.")
            }
        }
    }
}
