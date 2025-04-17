//
//  ImagePreviewView.swift
//  PhotoClean
//
//  Created by Nirdosh on 17/04/25.
//

import SwiftUI

struct ImagePreviewView: View {
    let imageURL: URL // The URL passed from the detail view
    
    @State private var image: UIImage? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    // Environment variable to dismiss the sheet
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView { // Embed in NavigationView for title and dismiss button
            Group { // Use Group to switch content
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5) // Make spinner larger
                } else if let img = image {
                    // --- Interactive Image View ---
                    // Replace with a proper zoomable view later if needed
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit() // Fit the whole image within the screen bounds
                        .accessibilityLabel("Full size preview of image \(imageURL.lastPathComponent)")
                    // --- End Interactive Image View ---
                    
                } else {
                    // Error display
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.orange)
                        Text("Error Loading Image")
                            .font(.title2)
                            .padding(.top, 5)
                        Text(errorMessage ?? "Could not load image data.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
            }
            .navigationTitle(imageURL.lastPathComponent) // Show filename as title
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { // Add a dismiss button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss() // Dismiss the sheet
                    }
                }
            }
            .task { // Load the full image when the view appears
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        isLoading = true
        errorMessage = nil
        image = nil // Reset image before loading
        
        // --- Load image data with access handling ---
        var imageData: Data? = nil
        var accessError = false
        var accessErrorMessage: String? = nil // More specific error tracking
        
        // Resolve bookmark and get access to parent
        guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else {
            accessErrorMessage = "Could not find folder bookmark."
            accessError = true
            print("PREVIEW ERROR: Failed to find bookmark.")
            // Proceed to finally block to set loading state
            finalizeLoad(imageData: nil, accessOrLoadError: accessErrorMessage)
            return // Exit early
        }
        
        // --- CORRECTED BOOKMARK RESOLUTION ---
        var isStale = false // Declare BEFORE do-try
        do {
            // Resolve using throwing initializer
            let resolvedFolderURL = try URL(resolvingBookmarkData: bookmarkData,
                                            options: [], // No scope option needed here
                                            relativeTo: nil,
                                            bookmarkDataIsStale: &isStale)
            
            if isStale { print("PREVIEW Warning: Bookmark was stale.") /* Handle if needed */ }
            print("PREVIEW: Resolved parent folder URL.")
            
            // Start access on parent
            if resolvedFolderURL.startAccessingSecurityScopedResource() {
                defer { resolvedFolderURL.stopAccessingSecurityScopedResource(); print("PREVIEW: Stopped parent access.") }
                print("PREVIEW: Parent access granted.")
                let specificFileURL = resolvedFolderURL.appendingPathComponent(imageURL.lastPathComponent) // Use the imageURL passed to the view
                
                // Load data using the method that worked before
                do {
                    imageData = try Data(contentsOf: specificFileURL, options: .mappedIfSafe)
                    print("PREVIEW: Image data loaded (\(imageData?.count ?? 0) bytes).")
                } catch {
                    accessErrorMessage = "Could not load image data: \(error.localizedDescription)"
                    accessError = true
                    print("PREVIEW ERROR: Failed to load Data for \(specificFileURL.lastPathComponent): \(error)")
                }
            } else {
                accessErrorMessage = "Could not get access to folder."
                accessError = true
                print("PREVIEW ERROR: Failed to start access on resolved folder URL.")
            }
        } catch {
            // Catch errors from resolving bookmark
            accessErrorMessage = "Error resolving folder access: \(error.localizedDescription)"
            accessError = true
            print("PREVIEW ERROR: Failed resolving bookmark: \(error)")
        }
        // --- END CORRECTED BOOKMARK RESOLUTION & ACCESS ---
        
        
        // --- Finalize loading state and create UIImage ---
        finalizeLoad(imageData: imageData, accessOrLoadError: accessErrorMessage)
        
    } // End loadImage
    
    // Helper function to finalize state updates on MainActor
    @MainActor
    private func finalizeLoad(imageData: Data?, accessOrLoadError: String?) {
        if let data = imageData, accessOrLoadError == nil {
            // Only try to create image if data is present and no prior errors
            self.image = UIImage(data: data)
            if self.image == nil {
                self.errorMessage = "Could not decode image data."
                print("PREVIEW ERROR: Failed to create UIImage from loaded data.")
            } else {
                self.errorMessage = nil // Clear error on success
            }
        } else {
            // Use the error message generated during access/loading
            self.errorMessage = accessOrLoadError ?? "An unknown error occurred."
            self.image = nil // Ensure image is nil on error
        }
        self.isLoading = false // Mark loading as finished
        print("PREVIEW: Finalized loading. Error: \(self.errorMessage ?? "None")")
    }
    // Preview provider for ImagePreviewView (Optional)
    struct ImagePreviewView_Previews: PreviewProvider {
        static var previews: some View {
            // Need a dummy URL for preview
            ImagePreviewView(imageURL: URL(string: "file:///dummy.jpg")!)
        }
    }
}
