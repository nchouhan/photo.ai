//
//  ContentView.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//

import SwiftUI
import Vision

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
    
    @State private var imageFeaturePrints: [URL: VNFeaturePrintObservation] = [:] // Stores the groups of near-duplicate URLs
    @State private var nearDuplicateGroups: [[URL]] = [] // Array of arrays of URLs
    
    private let nearDuplicateThreshold: Float = 0.07 // Example Threshold

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
                } else if !exactDuplicateGroups.isEmpty || !nearDuplicateGroups.isEmpty { // Show if either has results
                    // Consolidated results display
                    VStack {
                        if !exactDuplicateGroups.isEmpty {
                            Text("Found \(exactDuplicateGroups.count) groups of exact duplicates (\(totalExactDuplicateFilesCount) files).") // Renamed computed var
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                        if !nearDuplicateGroups.isEmpty {
                             Text("Found \(nearDuplicateGroups.count) groups of near duplicates (\(totalNearDuplicateFilesCount) files).") // New computed var
                                .font(.subheadline)
                                .foregroundColor(.blue) // Different color maybe
                        }
                    }
                        .padding(.top, 5)
                } else if selectedFolderURL != nil && !imageFileURLs.isEmpty && !isAnalyzing && analysisMessage.contains("completed") {
                    Text("No duplicates found.")
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
                if !exactDuplicateGroups.isEmpty || !nearDuplicateGroups.isEmpty {
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
                        await startAnalysis(fileURLs: newValue)
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
    // --- Computed Properties for Counts ---
   private var totalExactDuplicateFilesCount: Int {
       exactDuplicateGroups.reduce(0) { $0 + $1.value.count }
   }

   private var totalNearDuplicateFilesCount: Int {
       nearDuplicateGroups.reduce(0) { $0 + $1.count }
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
        private func startAnalysis(fileURLs: [URL]) async {
            guard !isAnalyzing else { return }

            resetAnalysisState()
            isAnalyzing = true
            let totalFiles = fileURLs.count
            guard totalFiles > 0 else {
                 analysisMessage = "No files to analyze."
                 isAnalyzing = false
                 return
            }
            print("Starting analysis for \(totalFiles) files.")

            // ===== Stage 1: Exact Duplicates (Hashing) =====
            analysisMessage = "Stage 1/2: Finding exact duplicates..."
            analysisProgress = 0.0 // Reset progress for stage 1

            var hashes = [String: [URL]]()
            var processedCountStage1 = 0

            print("Starting exact duplicate analysis loop...")
            for fileURL in fileURLs {
                 // (Yielding logic as before)
                 if processedCountStage1 % 5 == 0 { await Task.yield() }
                 guard isAnalyzing else { break }

                 print("Loop 1: Processing \(fileURL.lastPathComponent)")

                 // (Load Data logic as before)
                 var imageData: Data? = nil
                 guard fileURL.startAccessingSecurityScopedResource() else {
                     print("Loop 1 ERROR: Could not start access for \(fileURL.lastPathComponent). Skipping.")
                     processedCountStage1 += 1 // Increment count even if skipped
                     // Update progress reflecting skip
                     let progress = Double(processedCountStage1) / Double(totalFiles) * 0.5 // Stage 1 is 50%
                     await MainActor.run { updateProgress(progress: progress, message: "Stage 1/2: Analyzing \(processedCountStage1)/\(totalFiles) (Skipped Access)") }
                     continue
                 }
                 do {
                     defer { fileURL.stopAccessingSecurityScopedResource(); print("Loop 1: Stopped accessing \(fileURL.lastPathComponent)") }
                     imageData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                     print("Loop 1: Loaded data (\(imageData?.count ?? 0) bytes)")
                 } catch {
                     print("Loop 1 ERROR: Could not load data for \(fileURL.lastPathComponent): \(error)")
                     imageData = nil
                 }

                // (Hashing logic using detached task as before)
                var calculatedHash: String? = nil
                if let dataToHash = imageData {
                    calculatedHash = await Task.detached(priority: .userInitiated) {
                        print("DETACHED 1: Hashing data from \(fileURL.lastPathComponent)")
                        return ImageHasher.generatePixelHash(from: dataToHash)
                    }.value
                } else {
                    print("Loop 1: Skipping hash for \(fileURL.lastPathComponent).")
                }

                if let hash = calculatedHash {
                    hashes[hash, default: []].append(fileURL)
                }

                 // Update Progress for Stage 1 (0% to 50%)
                 processedCountStage1 += 1
                 let progress = Double(processedCountStage1) / Double(totalFiles) * 0.5 // Stage 1 is 50% of total
                 await MainActor.run { updateProgress(progress: progress, message: "Stage 1/2: Analyzing \(processedCountStage1)/\(totalFiles)") }

            } // End of exact duplicate loop

            guard isAnalyzing else { print("Analysis cancelled during Stage 1."); resetAnalysisState(); return }

            // Finalize Stage 1 results
            let exactDups = hashes.filter { $1.count > 1 }
            await MainActor.run {
                 self.imageHashes = hashes // Store all hashes
                 self.exactDuplicateGroups = exactDups
                 print("Stage 1 complete. Found \(exactDups.count) exact duplicate groups.")
            }


            // ===== Stage 2: Near Duplicates (Vision Feature Prints) =====
            await MainActor.run {
                 analysisMessage = "Stage 2/2: Finding near duplicates..."
                 // Keep progress at 0.5 initially for stage 2
            }
            print("Starting near duplicate analysis...")

            // Identify unique images to process for feature prints:
            // One representative from each exact duplicate group + all unique images (hash count == 1)
            var representativeURLs: [URL] = []
            var processedHashes = Set<String>() // Keep track of processed hashes

            for (hash, urls) in hashes {
                 if let firstURL = urls.first { // Take the first URL from the list
                     representativeURLs.append(firstURL)
                     processedHashes.insert(hash) // Mark this hash as covered
                 }
            }
            print("Identified \(representativeURLs.count) representative images for Stage 2.")


            // Generate Feature Prints for representative images
            var featurePrints = [URL: VNFeaturePrintObservation]() // Temporary dict for this stage
            var processedCountStage2 = 0
            let totalStage2 = representativeURLs.count

            guard totalStage2 > 0 else {
                print("Stage 2: No representative images to analyze.")
                await MainActor.run { finalizeAnalysis() } // Go straight to finalize
                return
            }

            for fileURL in representativeURLs {
                 if processedCountStage2 % 5 == 0 { await Task.yield() } // Yielding
                 guard isAnalyzing else { break }

                 print("Loop 2: Processing \(fileURL.lastPathComponent) for feature print.")

                // (Load Data logic - REPEATED - Consider optimizing later by caching loaded data)
                var imageData: Data? = nil
                guard fileURL.startAccessingSecurityScopedResource() else {
                    print("Loop 2 ERROR: Could not start access for \(fileURL.lastPathComponent). Skipping.")
                    processedCountStage2 += 1
                    let progress = 0.5 + (Double(processedCountStage2) / Double(totalStage2) * 0.5) // Stage 2 is 50%
                     await MainActor.run { updateProgress(progress: progress, message: "Stage 2/2: Analyzing \(processedCountStage2)/\(totalStage2) (Skipped Access)") }
                    continue
                }
                do {
                    defer { fileURL.stopAccessingSecurityScopedResource(); print("Loop 2: Stopped accessing \(fileURL.lastPathComponent)") }
                    imageData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                    print("Loop 2: Loaded data (\(imageData?.count ?? 0) bytes)")
                } catch {
                    print("Loop 2 ERROR: Could not load data for \(fileURL.lastPathComponent): \(error)")
                    imageData = nil
                }

                // Generate feature print using detached task
                var calculatedPrint: VNFeaturePrintObservation? = nil
                if let dataToProcess = imageData {
                     calculatedPrint = await Task.detached(priority: .userInitiated) {
                          print("DETACHED 2: Generating feature print for \(fileURL.lastPathComponent)")
                          return await VisionService.generateFeaturePrint(from: dataToProcess)
                     }.value
                } else {
                     print("Loop 2: Skipping feature print for \(fileURL.lastPathComponent).")
                }

                if let featurePrint = calculatedPrint {
                     featurePrints[fileURL] = featurePrint // Store the print keyed by URL
                }

                // Update Progress for Stage 2 (50% to 100%)
                processedCountStage2 += 1
                let progress = 0.5 + (Double(processedCountStage2) / Double(totalStage2) * 0.5) // Stage 2 is 50%
                 await MainActor.run { updateProgress(progress: progress, message: "Stage 2/2: Analyzing \(processedCountStage2)/\(totalStage2)") }

            } // End of feature print generation loop

            guard isAnalyzing else { print("Analysis cancelled during Stage 2."); resetAnalysisState(); return }

            // --- Grouping Near Duplicates ---
            print("Grouping near duplicates...")
            var nearDups = [[URL]]()
            var clusteredURLs = Set<URL>() // Keep track of URLs already put into a group

            // Iterate through the representative URLs for which we got feature prints
            let urlsWithPrints = Array(featurePrints.keys)

            for i in 0..<urlsWithPrints.count {
                let url1 = urlsWithPrints[i]
                guard !clusteredURLs.contains(url1), let print1 = featurePrints[url1] else {
                    continue // Skip if already clustered or no print available
                }

                var currentGroup: [URL] = [url1] // Start a new potential group

                // Compare url1 with subsequent images
                for j in (i + 1)..<urlsWithPrints.count {
                    let url2 = urlsWithPrints[j]
                    guard !clusteredURLs.contains(url2), let print2 = featurePrints[url2] else {
                        continue // Skip if already clustered or no print
                    }

                    // Calculate distance
                    if let distance = VisionService.calculateDistance(between: print1, and: print2) {
                        // print("Distance between \(url1.lastPathComponent) and \(url2.lastPathComponent) = \(distance)") // Debug
                        if distance < nearDuplicateThreshold { // Check against threshold
                            print("Found near duplicate: \(url1.lastPathComponent) and \(url2.lastPathComponent) (Distance: \(distance))")
                            currentGroup.append(url2)
                            clusteredURLs.insert(url2) // Mark url2 as clustered
                        }
                    }
                }

                // If the group has more than one image, add it to the results
                if currentGroup.count > 1 {
                     clusteredURLs.insert(url1) // Mark url1 as clustered
                     nearDups.append(currentGroup)
                }
            }
            print("Stage 2 complete. Found \(nearDups.count) near duplicate groups.")

            // --- Final State Update ---
            await MainActor.run {
                self.imageFeaturePrints = featurePrints // Store prints if needed later
                self.nearDuplicateGroups = nearDups
                finalizeAnalysis() // Call helper to set final state
            }
        }
    // Helper to update progress and message safely on MainActor
        @MainActor
        private func updateProgress(progress: Double, message: String) {
            guard isAnalyzing else { return }
            self.analysisProgress = progress
            self.analysisMessage = message
            print("Progress: \(String(format: "%.1f", progress * 100))% - \(message)") // Log progress updates
        }

        // Helper to set final analysis state
        @MainActor
        private func finalizeAnalysis() {
             isAnalyzing = false
             analysisProgress = 1.0
             analysisMessage = "Analysis completed."
        }
    
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
