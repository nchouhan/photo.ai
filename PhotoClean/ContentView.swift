import SwiftUI
import Vision // Make sure Vision is imported

struct DuplicateGroup: Identifiable, Hashable {
    let id = UUID() // For Identifiable conformance in SwiftUI lists
    let urls: [URL] // Original URLs in the group
    var bestURL: URL? = nil // Suggested best URL based on quality
    let isExact: Bool // True for exact, False for near-duplicate
}
struct ContentView: View {
    // MARK: - State Variables

    // Phase 2: Picker and File List
    @State private var showDocumentPicker = false
    @State private var selectedFolderURL: URL? = nil // Might only be used initially or for display name
    @State private var selectedFolderName: String? // Store name from UserDefaults
    @State private var imageFileURLs: [URL] = []
    @State private var pickerErrorMessage: String? = nil

    // Phase 3 & 4: Analysis State & Results
    @State private var isAnalyzing: Bool = false
    @State private var analysisProgress: Double = 0.0 // 0.0 to 1.0
    @State private var analysisMessage: String = ""

    // Exact Duplicates (Phase 3)
    @State private var imageHashes: [String: [URL]] = [:] // Hash -> Original URLs
    @State private var exactDuplicateGroups: [String: [URL]] = [:] // Filtered hashes with count > 1

    // Near Duplicates (Phase 4)
    @State private var imageFeaturePrints: [URL: VNFeaturePrintObservation] = [:] // Original URL -> FeaturePrint
    @State private var nearDuplicateGroups: [[URL]] = [] // Array of groups (arrays of Original URLs)
    @State private var duplicateGroups: [DuplicateGroup] = []
   
    // Phase 4: Configuration
    private let nearDuplicateThreshold: Float = 0.30 // Lower = more similar (tune this!)

    // MARK: - Computed Properties

    private var totalExactDuplicateFilesCount: Int {
        exactDuplicateGroups.reduce(0) { $0 + $1.value.count }
    }

    private var totalNearDuplicateFilesCount: Int {
        nearDuplicateGroups.reduce(0) { $0 + $1.count }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            VStack(spacing: 15) {
                // --- Folder Selection Info ---
                // Display name from state, preferring resolved URL if available
                if let folderName = selectedFolderName ?? selectedFolderURL?.lastPathComponent {
                    Text("Folder: \(folderName)")
                        .font(.headline)
                    if let errorMsg = pickerErrorMessage {
                        Text("Picker Error: \(errorMsg)")
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    } else if !imageFileURLs.isEmpty {
                        Text("\(imageFileURLs.count) image files found.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if !isAnalyzing { // Only show initial prompt if not loading bookmark etc.
                    Spacer()
                    Text("Select an iCloud Drive folder containing photos to begin analysis.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // --- Analysis Progress and Results ---
                

                if isAnalyzing {
                    ProgressView(value: analysisProgress, total: 1.0) {
                        Text(analysisMessage)
                            .font(.caption)
                    } currentValueLabel: {
                        Text("\(Int(analysisProgress * 100))%")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                } else if !duplicateGroups.isEmpty {
                        // Consolidated results display
                        VStack(alignment: .leading, spacing: 4) { // Added spacing
                       let exactCount = duplicateGroups.filter { $0.isExact }.count
                       let nearCount = duplicateGroups.filter { !$0.isExact }.count
                       let totalExactFiles = duplicateGroups.filter { $0.isExact }.reduce(0) { $0 + $1.urls.count }
                       let totalNearFiles = duplicateGroups.filter { !$0.isExact }.reduce(0) { $0 + $1.urls.count }

                       // --- Display counts based on final 'duplicateGroups' ---
                       if exactCount > 0 {
                           Text("• Found \(exactCount) groups of exact duplicates (\(totalExactFiles) files).")
                               .font(.subheadline)
                               .foregroundColor(.green)
                       }
                       if nearCount > 0 {
                            Text("• Found \(nearCount) groups of near duplicates (\(totalNearFiles) files).")
                               .font(.subheadline)
                               .foregroundColor(.blue)
                       }
                        // Optional: Add a total line?
                        // Text("• Total: \(duplicateGroups.count) groups found.")
                        //    .font(.subheadline)
                        //    .foregroundColor(.secondary)

                   }
                   .padding(.top, 5)
                } else if (selectedFolderName != nil || selectedFolderURL != nil) && !imageFileURLs.isEmpty && !isAnalyzing && analysisMessage.contains("completed") {
                     // Explicitly check analysisMessage to avoid showing this after picker errors
                    Text("No duplicates found.")
                       .font(.subheadline)
                       .foregroundColor(.orange)
                       .padding(.top, 5)
                }


                // --- Action Button ---
                Button {
                    // Reset state BEFORE showing picker (except folder name/bookmark)
                    imageFileURLs = []
                    pickerErrorMessage = nil
                    resetAnalysisState() // Clear analysis results
                    showDocumentPicker = true
                } label: {
                    Label(selectedFolderName != nil || selectedFolderURL != nil ? "Select Another Folder" : "Select Folder",
                          systemImage: "folder.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .disabled(isAnalyzing)

                // Placeholder for future results area
                if !exactDuplicateGroups.isEmpty || !nearDuplicateGroups.isEmpty {
                     Text("Review groups (coming soon)...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical)
                }

                Spacer() // Pushes content up

            } // End VStack
            .padding()
            .navigationTitle("PhotoClean")
            // --- Triggers Analysis ---
            .onChange(of: imageFileURLs) { oldValue, newValue in
                // Only trigger if the list becomes non-empty and we're not already analyzing
                guard !newValue.isEmpty, !isAnalyzing else {
                    // If list becomes empty, ensure analysis state is reset
                    if newValue.isEmpty {
                        resetAnalysisState()
                        print("onChange: Image file list cleared, resetting analysis state.")
                    }
                    return
                }

                // Analysis Trigger Task
                Task {
                    print("onChange: imageFileURLs populated with \(newValue.count) files. Starting access process.")
                    // --- Resolve Bookmark and Start Access (CORRECT iOS Version) ---
                    guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else {
                        print("onChange Error: No bookmark data found.")
                        await MainActor.run {
                            resetAnalysisState()
                            pickerErrorMessage = "Folder selection bookmark missing. Please select again."
                        }
                        return
                    }

                    var isStale = false
                    var resolvedFolderURL: URL?
                    do {
                        // Resolve WITHOUT .withSecurityScope on iOS.
                        resolvedFolderURL = try URL(resolvingBookmarkData: bookmarkData,
                                                    options: [], // <-- EMPTY OPTIONS
                                                    relativeTo: nil,
                                                    bookmarkDataIsStale: &isStale)

                        if isStale { print("onChange Warning: Bookmark data was stale.") /* Handle if needed */ }

                        guard let folderURL = resolvedFolderURL else {
                            throw NSError(domain: "PhotoCleanError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve bookmark data into a URL."])
                        }
                        print("onChange: Resolved folder URL from bookmark: \(folderURL.lastPathComponent)")

                        // Start access on the RESOLVED folder URL
                        print("onChange: Attempting access on RESOLVED folder URL.")
                        guard folderURL.startAccessingSecurityScopedResource() else {
                            print("onChange Error: Failed to start access on resolved folder URL.")
                            await MainActor.run {
                                resetAnalysisState()
                                pickerErrorMessage = "Lost access to folder (bookmark). Please select again."
                            }
                            // Maybe remove faulty bookmark here?
                            // UserDefaults.standard.removeObject(forKey: "selectedFolderBookmark")
                            return
                        }
                        print("onChange: Folder access granted via bookmark.")

                        // Use defer to ensure stopAccessing is called for the resolved folder URL
                        defer {
                            folderURL.stopAccessingSecurityScopedResource()
                            print("onChange: Stopped access on resolved folder URL after analysis task.")
                        }

                        // --- Start Analysis ---
                        print("onChange: Starting analysis...")
                        // Pass BOTH the original file list AND the activated folder URL
                        await startAnalysis(originalFileURLs: newValue, activatedFolderURL: folderURL)

                    } catch {
                        print("onChange Error: Failed to resolve bookmark or gain access: \(error)")
                        await MainActor.run {
                            resetAnalysisState()
                            pickerErrorMessage = "Could not re-access folder. Please select again. (\(error.localizedDescription))"
                        }
                         // Maybe remove faulty bookmark here?
                         // UserDefaults.standard.removeObject(forKey: "selectedFolderBookmark")
                        return
                    }
                } // End Task
            } // End onChange
            // --- Load initial state ---
            .onAppear {
                // Try to load the folder name initially if a bookmark exists
                if UserDefaults.standard.data(forKey: "selectedFolderBookmark") != nil {
                    self.selectedFolderName = UserDefaults.standard.string(forKey: "selectedFolderName")
                    print("onAppear: Found existing bookmark for folder: \(selectedFolderName ?? "Unknown")")
                     // Clear any previous analysis results when app appears with existing bookmark
                     resetAnalysisState()
                     imageFileURLs = [] // Clear file list too, it will repopulate via picker
                }
            }
        } // End NavigationView
        .navigationViewStyle(.stack) // Good for compatibility
        // --- Present Document Picker ---
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(selectedFolderURL: $selectedFolderURL, // Pass binding
                           imageFileURLs: $imageFileURLs,
                           errorMessage: $pickerErrorMessage)
        }
    } // End Body

    // MARK: - State Reset Functions

    /// Resets all state, including folder selection
    private func resetState() {
        selectedFolderURL = nil
        selectedFolderName = nil
        imageFileURLs = []
        pickerErrorMessage = nil
        UserDefaults.standard.removeObject(forKey: "selectedFolderBookmark")
        UserDefaults.standard.removeObject(forKey: "selectedFolderName")
        resetAnalysisState()
        print("State fully reset.")
    }

    /// Resets only analysis-related state
    private func resetAnalysisState() {
        isAnalyzing = false
        analysisProgress = 0.0
        analysisMessage = ""
        // Clear intermediate results if kept
        imageHashes = [:]
        exactDuplicateGroups = [:]
        imageFeaturePrints = [:]
        nearDuplicateGroups = []
        // Clear final results
        duplicateGroups = [] // Clear the main results array
        print("Analysis state reset.")
    }

    // MARK: - Analysis Helper Functions

    /// Helper to update progress and message safely on MainActor
    @MainActor
    private func updateProgress(progress: Double, message: String) {
        // Ensure progress doesn't exceed 1.0 due to rounding if issues occur
        self.analysisProgress = min(progress, 1.0)
        self.analysisMessage = message
         // Avoid excessive logging if needed:
         // print("Progress: \(String(format: "%.1f", self.analysisProgress * 100))% - \(message)")
    }

    /// Helper to set final analysis state
    @MainActor
    private func finalizeAnalysis() {
        isAnalyzing = false
        analysisProgress = 1.0
        analysisMessage = "Analysis completed."
        print("Analysis finalized.")
    }


    // MARK: - Main Analysis Function

    @MainActor
    private func startAnalysis(originalFileURLs: [URL], activatedFolderURL: URL) async {
        // Check if already analyzing (should be caught by onChange guard, but double-check)
        guard !isAnalyzing else {
             print("startAnalysis called while already analyzing. Ignoring.")
             return
        }

        let totalFiles = originalFileURLs.count
        guard totalFiles > 0 else {
             await MainActor.run {
                 analysisMessage = "No files to analyze."
                 isAnalyzing = false // Ensure analyzing flag is reset
             }
             return
        }

        // Reset state specifically for analysis start (progress, message, results)
        // Keep isAnalyzing = true set here
        await MainActor.run {
             self.analysisProgress = 0.0
             self.analysisMessage = "Starting..."
             self.imageHashes = [:]
             self.exactDuplicateGroups = [:]
             self.imageFeaturePrints = [:]
             self.nearDuplicateGroups = []
             self.isAnalyzing = true // Explicitly set true here
        }

        print("Starting analysis for \(totalFiles) files in folder \(activatedFolderURL.lastPathComponent).")

        // ===== Stage 1: Exact Duplicates (Hashing) =====
        await MainActor.run { updateProgress(progress: 0.0, message: "Stage 1/2: Finding exact duplicates...") }

        var hashes = [String: [URL]]() // Temp dict for stage 1 results
        var processedCountStage1 = 0

        print("Starting exact duplicate analysis loop...")
        for originalFileURL in originalFileURLs {
            // Check for cancellation / yield
             guard isAnalyzing else { print("Analysis cancelled during Stage 1 loop."); return }
             if processedCountStage1 % 10 == 0 { await Task.yield() } // Yield less often maybe

            let filename = originalFileURL.lastPathComponent
            print("Loop 1: Processing \(filename)")

            // Combine the ACTIVATED folder URL with the current filename
            let currentFileURL = activatedFolderURL.appendingPathComponent(filename)

            var imageData: Data? = nil
            // --- Load Data (Relying on Parent Scope) ---
            do {
                imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe)
                 // print("Loop 1: Loaded data (\(imageData?.count ?? 0) bytes) for \(filename)") // Verbose log
            } catch {
                print("Loop 1 ERROR: Could not load data for \(filename): \(error)")
                imageData = nil
                // Handle skip progress update
                 processedCountStage1 += 1
                 let progress = Double(processedCountStage1) / Double(totalFiles) * 0.5
                 await MainActor.run { updateProgress(progress: progress, message: "Stage 1/2: Analyzing \(processedCountStage1)/\(totalFiles) (Load Failed)") }
                continue // Skip hashing for this file
            }

            // --- Hashing Task ---
            var calculatedHash: String? = nil
            if let dataToHash = imageData {
                calculatedHash = await Task.detached(priority: .userInitiated) {
                    // print("DETACHED 1: Hashing data from \(filename)") // Verbose log
                    return ImageHasher.generatePixelHash(from: dataToHash)
                }.value
            } else {
                 print("Loop 1: Skipping hash for \(filename) because data loading failed.")
            }

            // --- Store Hash (using original URL) ---
            if let hash = calculatedHash {
                hashes[hash, default: []].append(originalFileURL)
            }

            // --- Update Progress ---
             processedCountStage1 += 1
             let progress = Double(processedCountStage1) / Double(totalFiles) * 0.5 // Stage 1 is 50% of total
             await MainActor.run { updateProgress(progress: progress, message: "Stage 1/2: Analyzing \(processedCountStage1)/\(totalFiles)") }

        } // End of Stage 1 loop
        
        let exactDupsRaw = hashes.filter { $1.count > 1 }
        // Don't store in exactDuplicateGroups state var anymore, process directly later

        // Check for cancellation again before proceeding
        guard isAnalyzing else { print("Analysis cancelled after Stage 1 loop."); return }

        // Finalize Stage 1 results
        let exactDups = hashes.filter { $1.count > 1 }
        await MainActor.run {
             self.imageHashes = hashes // Store all hashes
             self.exactDuplicateGroups = exactDups
             print("Stage 1 complete. Found \(exactDups.count) exact duplicate groups.")
        }


        // ===== Stage 2: Near Duplicates (Vision Feature Prints) =====
        await MainActor.run { updateProgress(progress: 0.5, message: "Stage 2/2: Finding near duplicates...") }
        print("Starting near duplicate analysis...")

        // Identify unique images to process for feature prints
        var representativeURLs: [URL] = [] // List of original URLs
        var processedHashes = Set<String>()
        for (hash, urls) in hashes { // Use final hashes from Stage 1
            if let firstURL = urls.first {
                representativeURLs.append(firstURL)
                processedHashes.insert(hash)
            }
        }
        print("Identified \(representativeURLs.count) representative images for Stage 2.")

        // Generate Feature Prints
        var featurePrints = [URL: VNFeaturePrintObservation]() // Temp dict for stage 2
        var processedCountStage2 = 0
        let totalStage2 = representativeURLs.count

        guard totalStage2 > 0 else {
            print("Stage 2: No representative images to analyze.")
            await MainActor.run { finalizeAnalysis() } // Go straight to finalize
            return
        }

        for representativeURL in representativeURLs { // Loop through original URLs
             guard isAnalyzing else { print("Analysis cancelled during Stage 2 loop."); return }
             if processedCountStage2 % 5 == 0 { await Task.yield() } // Yield less often

            let filename = representativeURL.lastPathComponent
            print("Loop 2: Processing \(filename) for feature print.")

            // Combine the ACTIVATED folder URL with the current filename
            let currentFileURL = activatedFolderURL.appendingPathComponent(filename)

            var imageData: Data? = nil
             // --- Load Data (Relying on Parent Scope) ---
            do {
                imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe)
                // print("Loop 2: Loaded data (\(imageData?.count ?? 0) bytes) for \(filename)") // Verbose log
            } catch {
                print("Loop 2 ERROR: Could not load data for \(filename): \(error)")
                imageData = nil
                 // Handle skip progress update
                 processedCountStage2 += 1
                 let progress = 0.5 + (Double(processedCountStage2) / Double(totalStage2) * 0.5)
                 await MainActor.run { updateProgress(progress: progress, message: "Stage 2/2: Analyzing \(processedCountStage2)/\(totalStage2) (Load Failed)") }
                continue // Skip feature print generation
            }

            // Generate feature print using detached task
            var calculatedPrint: VNFeaturePrintObservation? = nil
            if let dataToProcess = imageData {
                calculatedPrint = await Task.detached(priority: .userInitiated) {
                    // print("DETACHED 2: Generating feature print for \(filename)") // Verbose log
                    return await VisionService.generateFeaturePrint(from: dataToProcess)
                }.value
            } else {
                 print("Loop 2: Skipping feature print for \(filename) because data loading failed.")
            }

            // Store the print keyed by the ORIGINAL URL
            if let featurePrint = calculatedPrint {
                featurePrints[representativeURL] = featurePrint
            }

            // --- Update Progress ---
            processedCountStage2 += 1
            let progress = 0.5 + (Double(processedCountStage2) / Double(totalStage2) * 0.5)
            await MainActor.run { updateProgress(progress: progress, message: "Stage 2/2: Analyzing \(processedCountStage2)/\(totalStage2)") }

        } // End of feature print generation loop

        guard isAnalyzing else { print("Analysis cancelled after Stage 2 loop."); return }

        // --- Grouping Near Duplicates ---
        print("Grouping near duplicates using threshold: \(nearDuplicateThreshold)...")
        var nearDups = [[URL]]() // Array of arrays of original URLs
        var clusteredURLs = Set<URL>()

        // Use the representative URLs for which we actually generated prints
        let urlsWithPrints = Array(featurePrints.keys)

        for i in 0..<urlsWithPrints.count {
            let url1 = urlsWithPrints[i]
            guard !clusteredURLs.contains(url1), let print1 = featurePrints[url1] else { continue }

            var currentGroup: [URL] = [url1]

            for j in (i + 1)..<urlsWithPrints.count {
                let url2 = urlsWithPrints[j]
                guard !clusteredURLs.contains(url2), let print2 = featurePrints[url2] else { continue }

                if let distance = VisionService.calculateDistance(between: print1, and: print2) {
                    print("Distance between \(url1.lastPathComponent) and \(url2.lastPathComponent) = \(String(format: "%.4f", distance))")
                    if distance < nearDuplicateThreshold {
                        // print("Near duplicate: \(url1.lastPathComponent) - \(url2.lastPathComponent) (Dist: \(distance))") // Debug
                        currentGroup.append(url2)
                        clusteredURLs.insert(url2)
                    }
                }
            }

            if currentGroup.count > 1 {
                 clusteredURLs.insert(url1)
                 nearDups.append(currentGroup)
                 print("Found near duplicate group with \(currentGroup.count) images starting with \(url1.lastPathComponent)")
            }
        }
        print("Stage 2 complete. Found \(nearDups.count) near duplicate groups.")
        //End NearDuplicate
        
        // ===== Stage 3: Quality Assessment & Final Grouping =====
    // This stage combines exact and near duplicates and finds the best in each
    await MainActor.run { updateProgress(progress: 0.90, message: "Stage 3/3: Assessing quality...") } // Start near end of progress

    var finalGroups: [DuplicateGroup] = []
    var processedCountStage3 = 0
    let totalGroupsToProcess = exactDupsRaw.count + nearDups.count
    guard totalGroupsToProcess > 0 else {
        print("No duplicate groups found to assess quality.")
        await MainActor.run { finalizeAnalysis() }
        return
    }


    // --- Process Exact Duplicate Groups ---
    for (_, urls) in exactDupsRaw { // urls is [URL]
         guard isAnalyzing else { print("Analysis cancelled during Stage 3 (Exact)."); return }
         if processedCountStage3 % 2 == 0 { await Task.yield() } // Yield occasionally

         var bestScore: Float = -1.0 // Initialize with a value lower than any possible score
         var bestUrlInGroup: URL? = urls.first // Default to first if scoring fails

         print("QUALITY: Assessing Exact Group starting with \(urls.first?.lastPathComponent ?? "N/A") (\(urls.count) files)")

         for imageURL in urls { // Iterate through URLs in the exact group
             let filename = imageURL.lastPathComponent
             let currentFileURL = activatedFolderURL.appendingPathComponent(filename) // Combine with activated folder

             var imageData: Data? = nil
             // Load data (relying on parent scope) - Reuse logic from Stage 1/2
             do {
                 imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe)
             } catch {
                 print("QUALITY ERROR: Could not load data for \(filename): \(error)")
                 // Skip scoring this image if data load fails
                 continue
             }

             // Calculate Sharpness Score in detached task
             if let dataToScore = imageData {
                  let score = await Task.detached(priority: .utility) { // Lower priority maybe
                       return ImageQualityAnalyzer.calculateSharpnessScore(from: dataToScore)
                  }.value

                  if let score = score {
                       print("  Score for \(filename): \(score)")
                       if score > bestScore {
                           bestScore = score
                           bestUrlInGroup = imageURL // Store the ORIGINAL URL as best
                       }
                  } else {
                       print("  Failed to get score for \(filename)")
                  }
             }
         } // End loop through URLs in group

         // Create the final group object
         let group = DuplicateGroup(urls: urls, bestURL: bestUrlInGroup, isExact: true)
         finalGroups.append(group)
         processedCountStage3 += 1
         // Update progress (Stage 3 covers 90% to 100%)
         let progress = 0.90 + (Double(processedCountStage3) / Double(totalGroupsToProcess) * 0.10)
         await MainActor.run { updateProgress(progress: progress, message: "Stage 3/3: Assessing quality \(processedCountStage3)/\(totalGroupsToProcess)") }

    } // End loop through exact duplicate groups


        // --- Process Near Duplicate Groups ---
     for urls in nearDups { // urls is [URL]
         guard isAnalyzing else { print("Analysis cancelled during Stage 3 (Near)."); return }
         if processedCountStage3 % 2 == 0 { await Task.yield() } // Yield occasionally

         var bestScore: Float = -1.0
         var bestUrlInGroup: URL? = urls.first

         print("QUALITY: Assessing Near Group starting with \(urls.first?.lastPathComponent ?? "N/A") (\(urls.count) files)")

         for imageURL in urls {
             // --- Repeat data loading and scoring logic as above for exact dups ---
             let filename = imageURL.lastPathComponent
             let currentFileURL = activatedFolderURL.appendingPathComponent(filename)
             var imageData: Data? = nil
             do {
                 imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe)
             } catch { /* ... error handling ... */ continue }

             if let dataToScore = imageData {
                  let score = await Task.detached(priority: .utility) {
                       return ImageQualityAnalyzer.calculateSharpnessScore(from: dataToScore)
                  }.value
                  if let score = score {
                       print("  Score for \(filename): \(score)")
                       if score > bestScore {
                           bestScore = score
                           bestUrlInGroup = imageURL // Store ORIGINAL URL
                       }
                  } else { /* ... handle score failure ... */ }
             }
             // --- End repeat ---
         } // End loop through URLs in group

         let group = DuplicateGroup(urls: urls, bestURL: bestUrlInGroup, isExact: false)
         finalGroups.append(group)
         processedCountStage3 += 1
         // Update progress
         let progress = 0.90 + (Double(processedCountStage3) / Double(totalGroupsToProcess) * 0.10)
         await MainActor.run { updateProgress(progress: progress, message: "Stage 3/3: Assessing quality \(processedCountStage3)/\(totalGroupsToProcess)") }

     } // End loop through near duplicate groups
        // --- Final State Update ---
        await MainActor.run {
                    // Store the final, processed groups
                    self.duplicateGroups = finalGroups
                    // Clear intermediate state vars if no longer needed elsewhere
                    // self.imageHashes = [:]
                    // self.exactDuplicateGroups = [:]
                    // self.imageFeaturePrints = [:]
                    // self.nearDuplicateGroups = []
                    finalizeAnalysis() // Set final state (isAnalyzing=false, progress=1.0)
                    print("Quality assessment complete. Found \(finalGroups.count) total groups.")
                }
    } // End startAnalysis

} // End struct ContentView

// MARK: - Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
