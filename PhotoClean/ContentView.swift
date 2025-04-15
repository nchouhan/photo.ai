//
//  ContentView.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//

import SwiftUI

struct ContentView: View {
    // State variables
    @State private var showDocumentPicker = false
    @State private var selectedFolderURL: URL? = nil
    @State private var imageFileURLs: [URL] = []
    @State private var pickerErrorMessage: String? = nil // Renamed for clarity
    // --- State variables for Phase 3: Hashing ---
    @State private var isAnalyzing: Bool = false // General analysis flag
    @State private var analysisProgress: Double = 0.0 // 0.0 to 1.0
    @State private var analysisMessage: String = ""
    // Stores hash -> [URLs] for ALL images initially
    @State private var imageHashes: [String: [URL]] = [:]
    // Stores only the groups with count > 1
    @State private var exactDuplicateGroups: [String: [URL]] = [:]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 15) { // Adjusted spacing slightly
                
                // --- Folder Selection Info ---
                if let folderURL = selectedFolderURL {
                    Text("Folder: \(folderURL.lastPathComponent)")
                        .font(.headline)
                    if let errorMsg = pickerErrorMessage {
                        Text("Error: \(errorMsg)")
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    } else {
                        Text("Found \(imageFileURLs.count) image files.")
                            .font(.subheadline)
                            .foregroundColor(.secondary) // Changed color slightly
                    }
                } else {
                    Spacer()
                    Text("Select an iCloud Drive folder containing photos to begin analysis.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // --- Analysis Progress and Results ---
                if isAnalyzing {
                    ProgressView(value: analysisProgress, total: 1.0) {
                        Text(analysisMessage) // Show message within ProgressView label
                            .font(.caption)
                    } currentValueLabel: {
                        // Show percentage
                        Text("\(Int(analysisProgress * 100))%")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                } else if !exactDuplicateGroups.isEmpty {
                    // Show results after analysis
                    Text("Found \(exactDuplicateGroups.count) groups of exact duplicates (\(totalDuplicateFilesCount) files).")
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding(.top, 5)
                } else if selectedFolderURL != nil && !imageFileURLs.isEmpty && !isAnalyzing && exactDuplicateGroups.isEmpty && analysisMessage.contains("completed") {
                    // Handle case where analysis finished but found no duplicates
                    Text("No exact duplicates found.")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .padding(.top, 5)
                }
                
                
                // --- Action Button ---
                Button {
                    resetState() // Clear previous results before picking new folder
                    showDocumentPicker = true
                } label: {
                    Label(selectedFolderURL == nil ? "Select Folder" : "Select Another Folder",
                          systemImage: "folder.badge.plus")
                    .font(.title3) // Adjusted size slightly
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .disabled(isAnalyzing) // Disable button during analysis
                
                // Placeholder for future results area (Phase 6+)
                if !exactDuplicateGroups.isEmpty {
                    Text("Review groups (coming soon)...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical)
                }
                
                Spacer() // Pushes content
                
            }
            .padding()
            .navigationTitle("PhotoClean")
            .onChange(of: imageFileURLs) { oldValue, newValue in // << NEW iOS 17+ VERSION
                // Check the new value passed into the closure
                if !newValue.isEmpty {
                    // Start the analysis in a background task
                    // Pass the newValue to the analysis function
                    Task {
                        await analyzeExactDuplicates(fileURLs: newValue)
                    }
                } else {
                    // If file list becomes empty, clear analysis results
                    resetAnalysisState()
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(selectedFolderURL: $selectedFolderURL,
                           imageFileURLs: $imageFileURLs,
                           errorMessage: $pickerErrorMessage) // Pass the renamed binding
        }
    }
    
    // Helper computed property for total duplicate file count
    private var totalDuplicateFilesCount: Int {
        exactDuplicateGroups.reduce(0) { $0 + $1.value.count }
    }
    
    // Function to clear all state
    private func resetState() {
        selectedFolderURL = nil
        imageFileURLs = []
        pickerErrorMessage = nil
        resetAnalysisState()
    }
    
    // Function to clear only analysis-related state
    private func resetAnalysisState() {
        isAnalyzing = false
        analysisProgress = 0.0
        analysisMessage = ""
        imageHashes = [:]
        exactDuplicateGroups = [:]
    }
    
    
    // --- Exact Duplicate Analysis Function ---
    @MainActor
    private func analyzeExactDuplicates(fileURLs: [URL]) async {
        guard !isAnalyzing else { return }
        
        resetAnalysisState()
        isAnalyzing = true
        analysisMessage = "Starting exact duplicate analysis..."
        analysisProgress = 0.0
        print("Starting analysis for \(fileURLs.count) files.")
        
        var hashes = [String: [URL]]()
        var processedCount = 0
        let totalFiles = fileURLs.count
        
        print("Starting analysis loop...")
        
        for fileURL in fileURLs {
            // Yield periodically to keep UI responsive
            if processedCount % 5 == 0 { // Yield more often perhaps
                await Task.yield()
            }
            guard isAnalyzing else { break } // Check for cancellation before processing
            
            print("Loop: Processing \(fileURL.lastPathComponent)")
            
            // --- Load Data and Handle Security Scope BEFORE Detached Task ---
            var imageData: Data? = nil // Variable to hold loaded data

            // Start access
            guard fileURL.startAccessingSecurityScopedResource() else {
                print("Loop ERROR: Could not start accessing security-scoped resource for \(fileURL.lastPathComponent). Skipping file.")
                // If guard fails, exit the current iteration and go to the next fileURL
                // Need to increment processedCount here so progress doesn't stall
                processedCount += 1
                // Update progress to reflect skipped file
                let progress = Double(processedCount) / Double(totalFiles)
                await MainActor.run {
                     guard isAnalyzing else { return }
                     self.analysisProgress = progress
                     self.analysisMessage = "Analyzing: \(processedCount) / \(totalFiles) (Skipped Access)"
                     print("Loop: Updated progress to \(String(format: "%.1f", progress * 100))%")
                }
                continue // Go to the next iteration of the for loop
            }

            // Access granted, now load data and ensure stopAccessing is called
            do {
                // Use a defer block WITHIN this do/catch scope to ensure stopAccessing is always called if access started
                defer {
                    fileURL.stopAccessingSecurityScopedResource()
                    print("Loop: Stopped accessing \(fileURL.lastPathComponent)")
                }

                // Try loading data
                imageData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                print("Loop: Loaded data (\(imageData?.count ?? 0) bytes) for \(fileURL.lastPathComponent)")

            } catch {
                print("Loop ERROR: Could not load data for \(fileURL.lastPathComponent): \(error)")
                imageData = nil // Ensure data is nil on error
                // stopAccessingSecurityScopedResource() is called by defer
            }
            // --- End Data Loading ---
            
            
            // --- Detached Task for Hashing ---
            // Only proceed if we successfully loaded data
            var calculatedHash: String? = nil
            if let dataToHash = imageData {
                calculatedHash = await Task.detached(priority: .userInitiated) {
                    print("DETACHED TASK: Starting hash for data from \(fileURL.lastPathComponent)")
                    // Use the NEW hasher function that takes Data
                    let result = ImageHasher.generatePixelHash(from: dataToHash)
                    print("DETACHED TASK: Finished hash for data from \(fileURL.lastPathComponent). Result: \(result == nil ? "NIL" : "OK")")
                    return result
                }.value // Await the result
            } else {
                print("Loop: Skipping hash for \(fileURL.lastPathComponent) due to loading error or access failure.")
                // Mark as processed even if skipped, otherwise progress stalls
            }
            // --- End Detached Task ---
            
            print("Loop: Hash received for \(fileURL.lastPathComponent). Hash: \(calculatedHash ?? "nil")")
            
            // Store the hash if successfully calculated
            if let hash = calculatedHash {
                hashes[hash, default: []].append(fileURL)
            } else {
                // Already logged specific error during loading/hashing
            }
            
            // --- Progress Update ---
            processedCount += 1
            let progress = Double(processedCount) / Double(totalFiles)
            // Use MainActor.run explicitly
            await MainActor.run {
                guard isAnalyzing else { return } // Check again before UI update
                self.analysisProgress = progress
                self.analysisMessage = "Analyzing: \(processedCount) / \(totalFiles)"
                print("Loop: Updated progress to \(String(format: "%.1f", progress * 100))%")
            }
        } // End of for loop
        
        // --- Final Grouping ---
        if isAnalyzing { // Only finalize if analysis wasn't cancelled
            print("Finished analysis loop. Starting grouping...")
            let duplicates = hashes.filter { $1.count > 1 }
            
            await MainActor.run {
                self.imageHashes = hashes
                self.exactDuplicateGroups = duplicates
                self.isAnalyzing = false
                self.analysisProgress = 1.0
                self.analysisMessage = "Exact duplicate analysis completed."
                print("Analysis complete. Found \(duplicates.count) groups of exact duplicates.")
            }
        } else {
            print("Analysis cancelled before completion.")
            // Ensure state is fully reset if cancelled
            await MainActor.run {
                resetAnalysisState()
            }
        }
    }
}


            // MARK: - Preview
            struct ContentView_Previews: PreviewProvider {
                static var previews: some View {
                    // Add previews as before
                     Group {
                        ContentView()
                            .previewDevice("iPhone 14 Pro")
                            .previewDisplayName("iPhone")

                        ContentView()
                            .previewDevice("iPad Pro (11-inch) (4th generation)")
                            .previewDisplayName("iPad")
                            .previewInterfaceOrientation(.landscapeLeft)
                    }
                }
            }
