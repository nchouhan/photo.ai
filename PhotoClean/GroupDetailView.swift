//
//  GroupDetailView.swift
//  PhotoClean
//
//  Created by Nirdosh on 17/04/25.
//

import Foundation
import SwiftUI

struct GroupDetailView: View {
    // The group being reviewed
    let group: DuplicateGroup

    // State to track the currently selected 'keeper' URL
    // Initialize with the 'bestURL' suggested by the analysis
    @State private var selectedURL: URL?
    @State private var isShowingImagePreview = false // Controls sheet presentation
    @State private var previewImageURL: URL? = nil    // URL of the image to show large
    @State private var previewItem: PreviewableURL? = nil
    // Grid layout configuration
    private let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3) // 3 columns, adjust as needed

    // Environment variable to dismiss the view (needed later for actions)
    // @Environment(\.dismiss) private var dismiss

    // Initializer to set the initial selected URL
    init(group: DuplicateGroup) {
        self.group = group
        // Use _selectedURL direct state initialization IF using @State,
        // otherwise set it in .onAppear if needed or handle potential nil bestURL
        _selectedURL = State(initialValue: group.bestURL)
         // If group.bestURL could be nil, handle default selection:
         // _selectedURL = State(initialValue: group.bestURL ?? group.urls.first)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // Header Information (Optional)
                Text(group.isExact ? "Exact Duplicates (\(group.urls.count))" : "Near Duplicates (\(group.urls.count))")
                    .font(.title2)
                    .padding(.horizontal)
                    .padding(.bottom, 5)

                // The Grid of Thumbnails
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(group.urls, id: \.self) { imageURL in
                        // We'll create a separate view for the grid item later
                        // For now, just a placeholder
                        ThumbnailGridItem(
                            imageURL: imageURL,
                            isSelected: imageURL == selectedURL,
                            isSuggestedBest: imageURL == group.bestURL // Mark the originally suggested one
                        )
                        // --- ADD THIS MODIFIER ---
                            .zIndex(imageURL == selectedURL ? 1 : 0) // Draw selected item on top (zIndex 1 > default 0)
                            .padding(2)
                            // --- END ADDITION ---
                        .onTapGesture {
                             // Update selection when tapped
                            withAnimation(.easeInOut(duration:0.15)) {
                                selectedURL = imageURL
                            }
                            previewItem = PreviewableURL(url: imageURL)
                            // 2. Set the URL for the preview sheet
                            previewImageURL = imageURL
                            // 3. Trigger the sheet presentation
                            isShowingImagePreview = true
                            // --- END UPDATE ---
                            print("Tapped: \(imageURL.lastPathComponent), preparing preview.")
                            print("Selected: \(imageURL.lastPathComponent)")
                            Task {
                                     // Allow state to propagate (e.g., 1 millisecond)
                                     try? await Task.sleep(nanoseconds: 1_000_000)
                                     isShowingImagePreview = true // Trigger sheet AFTER delay
                                     print("Triggering sheet presentation.")
                                }
                        }
                    }
                }
                .padding(.horizontal, 12) // Padding for the grid

                Spacer(minLength: 30) // Space before action buttons

                // Action Buttons (Placeholders for now)
                HStack { // Arrange buttons horizontally
                    Spacer() // Push buttons to center/sides

                    Button {
                        // Action: Keep selected, delete others
                         print("ACTION: Keep \(selectedURL?.lastPathComponent ?? "None"), Delete Others")
                         // Add actual logic in Phase 8
                    } label: {
                        Label("Keep Selected", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedURL == nil) // Disable if nothing is selected

                    // Optional: Add "Keep All" or other actions?
                    // Button("Keep All") { /* Action */ }

                    Spacer()
                }
                .padding(.horizontal)

            } // End VStack
            .padding(.vertical) // Padding top/bottom for the whole content
        } // End ScrollView
        .navigationTitle("Review Group") // Set title for this screen
        .navigationBarTitleDisplayMode(.inline) // Or .large
        // --- ADD SHEET MODIFIER ---
//       .sheet(isPresented: $isShowingImagePreview) {
//           // Content of the sheet
//           // Ensure previewImageURL is not nil before presenting
//           if let urlToShow = previewImageURL {
//                ImagePreviewView(imageURL: urlToShow)
//           } else {
//                // Fallback or error view if URL is unexpectedly nil
//                Text("Error: No image selected for preview.")
//           }
        .sheet(item: $previewItem) { item in // Binds to optional identifiable item
            // The sheet only appears if previewItem is non-nil
            // 'item' here is the non-optional PreviewableURL
            ImagePreviewView(imageURL: item.url) // Pass the URL from the item
        }
       
           // --- END SHEET MODIFIER ---
        // .onAppear {
        //     // If initialValue didn't work reliably for @State
        //     if selectedURL == nil {
        //         selectedURL = group.bestURL ?? group.urls.first
        //     }
        // }
    }
}

// MARK: - Subview for Grid Item (To handle thumbnail loading)

struct ThumbnailGridItem: View {
    let imageURL: URL
    let isSelected: Bool
    let isSuggestedBest: Bool

    @State private var thumbnail: UIImage? = nil
    @State private var failedToLoad = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) { // Alignment for selection badge
            // Thumbnail Image or Placeholder (keep this part the same)
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else if failedToLoad {
                    Image(systemName: "photo.fill") // Error placeholder
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                } else {
                    ProgressView() // Loading placeholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // --- NEW: Selection Checkmark Overlay ---
            if isSelected {
                ZStack { // Use ZStack to layer circle and checkmark
                    // Slightly larger background circle
                    Circle()
                        .fill(Color.accentColor) // Use accent color directly for background
                        // Optional: Add a thin outer stroke for contrast
                        // .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .frame(width: 26, height: 26) // INCREASED size

                    // Checkmark icon
                    Image(systemName: "checkmark") // Use plain checkmark for simplicity inside circle
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.bold) // Make it bolder
                        .frame(width: 14, height: 14) // Adjust size relative to circle
                        .foregroundColor(.white)
                    }
                    .shadow(radius: 3) // Add shadow to lift it visually
                    // Offset slightly OUTWARD from the corner
                    .offset(x: 4, y: 4) // Pushes slightly down and right
                    .padding(3) // Base padding from the corner
                    // Ensure alignment to the corner within the main ZStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            // --- NEW: Suggested Best Label/Icon (Top Left) ---
            if isSuggestedBest {
                 VStack { // Use VStack for potential text label later
                     Image(systemName: "star.fill")
                         .font(.callout) // Adjust size
                         .foregroundColor(.yellow)
                         .shadow(color: .black.opacity(0.5), radius: 1)
                 }
                 .padding(5) // Position in top-left corner
                 .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Align within ZStack
            }

        } // End ZStack
        .task {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard thumbnail == nil else { return }
        let filename = imageURL.lastPathComponent
        print("GRID ITEM (\(filename)): Loading thumbnail")

        var thumbnailLoaded = false

        // --- Get the specific file URL using the helper ---
        // This URL is constructed but not necessarily accessible yet
        guard let specificFileURL = getAccessibleURL(for: imageURL) else {
            print("GRID ITEM (\(filename)) ERROR: Could not get specific file URL via helper.")
            self.failedToLoad = true
            return
        }

        // --- Now, ensure the PARENT folder scope is active to use the URL ---
        if let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
            // --- CORRECTED PARENT FOLDER ACCESS ---
            var isStale = false // Declare BEFORE do-try
            do {
                // Resolve bookmark using throwing initializer
                let resolvedFolderURL = try URL(resolvingBookmarkData: bookmarkData,
                                                options: [],
                                                relativeTo: nil,
                                                bookmarkDataIsStale: &isStale) // Pass pointer

                if isStale { /* Handle stale */ }
                print("GRID ITEM (\(filename)): Resolved parent folder URL.")

                // Start access on parent
                if resolvedFolderURL.startAccessingSecurityScopedResource() {
                    defer { resolvedFolderURL.stopAccessingSecurityScopedResource(); print("GRID ITEM (\(filename)): Stopped parent access.") }
                    print("GRID ITEM (\(filename)): Parent access granted for thumbnail load.")

                    // --- Call ThumbnailLoader with the specific URL WHILE parent scope is active ---
                    self.thumbnail = await ThumbnailLoader.generateThumbnail(for: specificFileURL)
                    if thumbnail != nil {
                        thumbnailLoaded = true
                    } else {
                        print("GRID ITEM (\(filename)) ERROR: ThumbnailLoader failed.")
                    }
                    // --- End Call ---

                } else {
                    print("GRID ITEM (\(filename)) ERROR: Failed to start parent access before loading thumbnail.")
                }
            } catch {
                 // Catch errors from resolving bookmark
                 print("GRID ITEM (\(filename)) ERROR: Failed to resolve parent bookmark for access: \(error)")
            }
            // --- END CORRECTED PARENT FOLDER ACCESS ---

        } else {
            print("GRID ITEM (\(filename)) ERROR: Failed to get parent bookmark for access.")
        }

        // Update UI based on success/failure
        if thumbnailLoaded {
            self.failedToLoad = false
            print("GRID ITEM (\(filename)): Thumbnail loaded.")
        } else {
            self.failedToLoad = true
            print("GRID ITEM (\(filename)) ERROR: Failed to load thumbnail.") // Simplified final error
        }
    }

     // Hypothetical helper to get accessible URL using bookmark - needs implementation
     // based on the logic developed in GroupRowView.loadThumbnail
    private func getAccessibleURL(for fileURL: URL) -> URL? { // Made synchronous as it doesn't await

        // 1. Get bookmark data
        guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else {
            print("GRID ITEM Helper ERROR: No bookmark data found.")
            return nil
        }

        // 2. Resolve bookmark data (handle throws)
        var isStale = false // Declare variable for output parameter
        let resolvedFolderURL: URL

        do {
            resolvedFolderURL = try URL(resolvingBookmarkData: bookmarkData,
                                        options: [], // No scope option for resolution
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale) // Pass pointer
            // If we get here, resolution succeeded
            if isStale {
                print("GRID ITEM Helper WARNING: Bookmark data was stale.")
                // Optionally re-save bookmark here if needed
            }
            print("GRID ITEM Helper: Resolved bookmark to folder: \(resolvedFolderURL.lastPathComponent)")

        } catch {
            print("GRID ITEM Helper ERROR: Failed resolving bookmark: \(error)")
            return nil // Failed to resolve
        }

        // 3. Construct specific file URL relative to the resolved parent
        let specificFileURL = resolvedFolderURL.appendingPathComponent(fileURL.lastPathComponent)
        print("GRID ITEM Helper: Constructed specific URL: \(specificFileURL.path)")

        // 4. Return the constructed URL
        // Note: Access is NOT started here. Caller must manage access scope.
        return specificFileURL
    }

}


// MARK: - Preview Provider (Optional)
struct GroupDetailView_Previews: PreviewProvider {
    static var previews: some View {
        // Create dummy data
        let urls = (1...5).map { URL(fileURLWithPath: "/image\($0).jpg") }
        let group = DuplicateGroup(urls: urls, bestURL: urls[2], isExact: false)

        // Embed in NavigationView for title
        NavigationView {
             GroupDetailView(group: group)
        }
    }
}
struct PreviewableURL: Identifiable {
    let id = UUID() // Simple unique ID for Identifiable
    let url: URL
}
