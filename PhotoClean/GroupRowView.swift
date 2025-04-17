//
//  GroupRowView.swift
//  PhotoClean
//
//  Created by Nirdosh on 17/04/25.
//

import Foundation
import SwiftUI

struct GroupRowView: View {
    // The group data for this row
    let group: DuplicateGroup

    // State variable to hold the loaded thumbnail
    @State private var thumbnail: UIImage? = nil
    // State to track if loading failed
    @State private var failedToLoad = false

    var body: some View {
        HStack(spacing: 12) { // Add spacing between elements
            // Thumbnail View
            Group { // Group helps apply modifiers conditionally
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill() // Fill the frame, cropping if needed
                        .frame(width: 60, height: 60) // Fixed size for consistency
                        .clipShape(RoundedRectangle(cornerRadius: 8)) // Nice rounded corners
                        .overlay( // Add subtle border
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                } else if failedToLoad {
                     // Placeholder for failed load
                     Image(systemName: "photo.fill") // Or "exclamationmark.triangle.fill"
                         .resizable()
                         .scaledToFit()
                         .frame(width: 60, height: 60)
                         .foregroundColor(.secondary)
                         .background(Color.gray.opacity(0.1))
                         .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Placeholder while loading
                    ProgressView() // Show spinner
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }


            // Text Information
            VStack(alignment: .leading) {
                Text(groupTypeLabel) // e.g., "Exact Duplicates" or "Near Duplicates"
                    .font(.headline)
                    .foregroundColor(group.isExact ? .green : .blue) // Match colors from summary

                Text("\(group.urls.count) photos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Optionally show the filename of the 'best' photo
                if let bestURL = group.bestURL {
                     Text("Best: \(bestURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1) // Prevent long filenames taking too much space
                        .truncationMode(.middle)
                } else {
                    // Should not happen if Phase 5 worked, but handle anyway
                     Text("Best: (Not determined)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer() // Pushes content to the left

            // Navigation indicator (chevron)
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .padding(.leading, 5)

        } // End HStack
        .padding(.vertical, 6) // Add padding top/bottom for spacing between rows
        .task { // Use .task modifier to load thumbnail asynchronously when view appears
             await loadThumbnail()
        }
        // Optional: Add a tap gesture or NavigationLink later for Phase 7
    }

    // Helper computed property for label
    private var groupTypeLabel: String {
        group.isExact ? "Exact Duplicates" : "Near Duplicates"
    }

    // Async function to load the thumbnail
    @MainActor
    private func loadThumbnail() async {
        guard thumbnail == nil, let bestURL = group.bestURL else {
            if group.bestURL == nil { failedToLoad = true }
            return
        }

        print("ROW (\(group.id)): Loading thumbnail for \(bestURL.lastPathComponent)")
        var urlToLoad: URL? = nil
        var thumbnailLoaded = false // Flag to track success

        // 1. Get access via bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
            do {
                var isStale = false
                // --- CORRECTED RESOLUTION ---
                // Call the throwing initializer with try
                let resolvedFolderURL: URL = try URL(resolvingBookmarkData: bookmarkData,
                                                     options: [],
                                                     relativeTo: nil,
                                                     bookmarkDataIsStale: &isStale)
                // If the above line succeeds, resolvedFolderURL is a non-optional URL
                // --- END CORRECTION ---

                if isStale { print("ROW (\(group.id)) Warning: Bookmark data was stale.") /* Handle if needed */ }

                print("ROW (\(group.id)): Resolved folder URL from bookmark: \(resolvedFolderURL.lastPathComponent)")

                // Start access on parent folder
                if resolvedFolderURL.startAccessingSecurityScopedResource() {
                    // Use defer to guarantee stopAccessing on the folder URL
                    defer { resolvedFolderURL.stopAccessingSecurityScopedResource(); print("ROW (\(group.id)): Stopped parent access.") }
                    print("ROW (\(group.id)): Parent access granted via bookmark.")

                    // Construct the specific file URL relative to the accessed parent
                    let specificFileURL = resolvedFolderURL.appendingPathComponent(bestURL.lastPathComponent)
                    urlToLoad = specificFileURL // Keep track

                    // Call ThumbnailLoader WHILE access is active
                    if let loadedThumbnail = await ThumbnailLoader.generateThumbnail(for: specificFileURL) {
                        self.thumbnail = loadedThumbnail
                        self.failedToLoad = false
                        thumbnailLoaded = true // Mark success
                        print("ROW (\(group.id)): Thumbnail loaded successfully.")
                    } else {
                        print("ROW (\(group.id)) ERROR: ThumbnailLoader failed for \(specificFileURL.lastPathComponent)")
                        // failedToLoad will be set later if !thumbnailLoaded
                    }
                } else {
                    print("ROW (\(group.id)) ERROR: Failed to start access on resolved parent folder.")
                }
            } catch {
                // Catch errors from URL(resolvingBookmarkData:)
                print("ROW (\(group.id)) ERROR: Failed resolving bookmark: \(error)")
            }
        } else {
            print("ROW (\(group.id)) ERROR: No bookmark data found for parent folder.")
        }

        // Final check: If thumbnail wasn't loaded successfully for any reason, mark as failed
        if !thumbnailLoaded {
            print("ROW (\(group.id)) ERROR: Failed to load thumbnail (access or loader error). URL attempted: \(urlToLoad?.lastPathComponent ?? "N/A")")
            self.failedToLoad = true
        }
    }
}

// MARK: - Preview Provider (Optional: Provide Sample Data)

struct GroupRowView_Previews: PreviewProvider {
    static var previews: some View {
        // Create some dummy data for preview
        let dummyURL1 = URL(fileURLWithPath: "/path/to/image1.jpg")
        let dummyURL2 = URL(fileURLWithPath: "/path/to/image2.jpg")
        let dummyGroupExact = DuplicateGroup(urls: [dummyURL1, dummyURL2], bestURL: dummyURL1, isExact: true)
        let dummyGroupNear = DuplicateGroup(urls: [dummyURL1, dummyURL2], bestURL: dummyURL2, isExact: false)

        Group { // Group multiple previews
            GroupRowView(group: dummyGroupExact)
            GroupRowView(group: dummyGroupNear)
        }
        .padding() // Add padding to the preview canvas
        .previewLayout(.sizeThatFits) // Adjust preview size
    }
}
