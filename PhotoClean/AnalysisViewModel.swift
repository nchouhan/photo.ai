//
//  AnalysisViewModel.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//
import SwiftUI
import Vision // For VNFeaturePrintObservation
import Combine // For ObservableObject

// Ensure ImageQualityAnalyzer and ImageHasher enums/structs exist in separate files
// Ensure ThumbnailLoader enum exists

@MainActor // Ensures UI updates happen on main thread easily for @Published properties
class AnalysisViewModel: ObservableObject {

    // MARK: - Published Properties (Trigger UI Updates)

    @Published var selectedFolderURL: URL? = nil // Reference URL if needed
    @Published var selectedFolderName: String? = nil
    @Published var imageFileURLs: [URL] = [] // List of originally found files
    @Published var pickerErrorMessage: String? = nil

    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0.0
    @Published var analysisMessage: String = ""
    @Published var duplicateGroups: [DuplicateGroup] = [] // Final combined results

    // MARK: - Configuration

    let nearDuplicateThreshold: Float = 0.30 // Tune this value

    // MARK: - Intermediate Results (Optional)
    // Not published, used during analysis calculation

    var imageHashes: [String: [URL]] = [:]
    var imageFeaturePrints: [URL: VNFeaturePrintObservation] = [:]

    // MARK: - Initialization

    init() {
        loadPersistentFolderInfo()
    }

    // MARK: - Public Methods (Called by View/Coordinator)

    func presentPicker() {
        // Reset relevant state before showing picker
        pickerErrorMessage = nil
        resetAnalysisState() // Clear previous analysis results
        // Note: imageFileURLs clearing is handled in folderSelected or if picker cancelled implicitly
    }

    func folderSelected(url: URL?, urls: [URL], error: String?) {
        // This method is called by the DocumentPickerWrapper Coordinator

        // Clear previous results FIRST regardless of outcome
        resetAnalysisState()
        self.imageFileURLs = [] // Clear file list initially

        guard let selectedURL = url, error == nil else {
            self.pickerErrorMessage = error ?? "Failed to get folder URL from picker."
            self.selectedFolderURL = nil
            self.selectedFolderName = nil
            UserDefaults.standard.removeObject(forKey: "selectedFolderBookmark")
            UserDefaults.standard.removeObject(forKey: "selectedFolderName")
            return
        }

        // --- Save Bookmark ---
        do {
            let bookmarkData = try selectedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "selectedFolderBookmark")
            UserDefaults.standard.set(selectedURL.lastPathComponent, forKey: "selectedFolderName")
            print("VIEWMODEL: Bookmark data saved for \(selectedURL.lastPathComponent).")

            // Update published properties
            self.selectedFolderURL = selectedURL
            self.selectedFolderName = selectedURL.lastPathComponent
            self.imageFileURLs = urls // Assign the scanned URLs
            self.pickerErrorMessage = nil

            // --- Trigger analysis after state is updated ---
            if !urls.isEmpty {
                 self.triggerAnalysis()
            } else {
                 // Handle case where folder was selected but was empty
                 self.analysisMessage = "Selected folder is empty."
                 print("VIEWMODEL: Selected folder is empty.")
            }

        } catch {
            print("VIEWMODEL ERROR: Failed to create bookmark data: \(error)")
            self.pickerErrorMessage = "Could not save folder permission."
            self.selectedFolderURL = nil
            self.selectedFolderName = nil
            UserDefaults.standard.removeObject(forKey: "selectedFolderBookmark")
            UserDefaults.standard.removeObject(forKey: "selectedFolderName")
        }
    }

    // MARK: - Analysis Trigger

    func triggerAnalysis() {
        guard !imageFileURLs.isEmpty, !isAnalyzing else {
             print("VIEWMODEL: Analysis trigger skipped (no files, or already analyzing).")
             return
        }

        print("VIEWMODEL: Triggering analysis task.")
        Task {
            // --- Resolve Bookmark & Get Activated Folder URL ---
            guard let folderURL = await self.getActivatedFolderURL() else {
                // Error message already set within getActivatedFolderURL
                print("VIEWMODEL: Failed to get activated folder URL for analysis.")
                return
            }
            // Ensure access is stopped after analysis using defer
            defer { folderURL.stopAccessingSecurityScopedResource(); print("VIEWMODEL: Stopped access on folder URL after analysis task.") }

            // --- Start the actual analysis ---
            await self.performAnalysis(originalFileURLs: self.imageFileURLs, activatedFolderURL: folderURL)
        }
    }

    // MARK: - Private: State Management & Helpers

    private func loadPersistentFolderInfo() {
        // Load folder name if bookmark exists
        if UserDefaults.standard.data(forKey: "selectedFolderBookmark") != nil {
           self.selectedFolderName = UserDefaults.standard.string(forKey: "selectedFolderName")
           print("VIEWMODEL init: Found existing bookmark for folder: \(selectedFolderName ?? "Unknown")")
        }
    }

    private func resetAnalysisState() {
        // Reset all analysis-related properties
        isAnalyzing = false
        analysisProgress = 0.0
        analysisMessage = ""
        imageHashes = [:]
        imageFeaturePrints = [:]
        duplicateGroups = [] // Clear final results array
        print("VIEWMODEL: Analysis state reset.")
    }

    // Helper to get activated folder URL
    private func getActivatedFolderURL() async -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else {
            print("VIEWMODEL ERROR: No bookmark data found for activation.")
            await MainActor.run { pickerErrorMessage = "Folder bookmark missing. Please select again." }
            return nil
        }

        var isStale = false
        do {
            let resolvedFolderURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale { print("VIEWMODEL Warning: Bookmark was stale.") /* Resave if needed */ }

            print("VIEWMODEL: Attempting access on resolved folder URL for analysis.")
            guard resolvedFolderURL.startAccessingSecurityScopedResource() else {
                print("VIEWMODEL ERROR: Failed to start access on resolved folder URL.")
                await MainActor.run { pickerErrorMessage = "Lost access to folder (bookmark). Please select again." }
                return nil
            }
            print("VIEWMODEL: Folder access granted.")
            // Return the activated URL - CALLER MUST CALL stopAccessingSecurityScopedResource
            return resolvedFolderURL
        } catch {
            print("VIEWMODEL ERROR: Failed resolving bookmark for activation: \(error)")
            await MainActor.run { pickerErrorMessage = "Could not re-access folder. Select again." }
            return nil
        }
    }

    // Helpers to update progress and finalize (must be called on MainActor)
    @MainActor
    private func updateProgress(progress: Double, message: String) {
        guard self.isAnalyzing else { return } // Don't update if cancelled
        self.analysisProgress = min(progress, 1.0)
        self.analysisMessage = message
    }

    @MainActor
    private func finalizeAnalysis() {
        isAnalyzing = false
        analysisProgress = 1.0 // Ensure it shows 100%
        analysisMessage = "Analysis completed."
        print("Analysis finalized.")
    }

    // MARK: - Private: Core Analysis Logic

    private func performAnalysis(originalFileURLs: [URL], activatedFolderURL: URL) async {
        let totalFiles = originalFileURLs.count
        guard totalFiles > 0 else { return } // Should be checked earlier

        // Reset results and set analyzing flag on main thread
        await MainActor.run {
            self.analysisProgress = 0.0
            self.analysisMessage = "Starting analysis..."
            self.imageHashes = [:] // Clear intermediate
            self.imageFeaturePrints = [:] // Clear intermediate
            self.duplicateGroups = [] // Clear final results
            self.isAnalyzing = true
        }
        print("Performing analysis for \(totalFiles) files in folder \(activatedFolderURL.lastPathComponent).")

        // --- Local variables for results build-up ---
        var localHashes = [String: [URL]]()
        var localFeaturePrints = [URL: VNFeaturePrintObservation]()
        var exactDupsRaw: [String: [URL]] = [:] // URL arrays grouped by hash
        var nearDupsRaw = [[URL]]() // Array of URL arrays
        var finalGroups: [DuplicateGroup] = []

        // ===== Stage 1: Exact Duplicates (Hashing) =====
        await MainActor.run { self.updateProgress(progress: 0.0, message: "Stage 1/3: Finding exact duplicates...") }
        var processedCountStage1 = 0
        print("Starting exact duplicate analysis loop...")

        for originalFileURL in originalFileURLs {
            guard self.isAnalyzing else { print("Analysis cancelled (Stage 1)"); return }
            if processedCountStage1 % 10 == 0 { await Task.yield() }

            let filename = originalFileURL.lastPathComponent
            let currentFileURL = activatedFolderURL.appendingPathComponent(filename)
            var imageData: Data? = nil

            do {
                imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe)
            } catch {
                print("Loop 1 ERROR: Could not load data for \(filename): \(error)")
                processedCountStage1 += 1
                let progress = Double(processedCountStage1) / Double(totalFiles) * (1.0/3.0) // Stage 1 is 1/3
                await self.updateProgress(progress: progress, message: "Stage 1/3: Analyzing \(processedCountStage1)/\(totalFiles) (Load Failed)")
                continue
            }

            var calculatedHash: String? = nil
            if let dataToHash = imageData {
                calculatedHash = await Task.detached(priority: .userInitiated) {
                    return ImageHasher.generatePixelHash(from: dataToHash)
                }.value
            }

            if let hash = calculatedHash {
                localHashes[hash, default: []].append(originalFileURL)
            }

            processedCountStage1 += 1
            let progress = Double(processedCountStage1) / Double(totalFiles) * (1.0/3.0) // Stage 1 is 1/3
            await self.updateProgress(progress: progress, message: "Stage 1/3: Analyzing \(processedCountStage1)/\(totalFiles)")
        } // End Stage 1 loop

        guard self.isAnalyzing else { print("Analysis cancelled after Stage 1 loop."); return }
        exactDupsRaw = localHashes.filter { $1.count > 1 }
        // Optionally store all hashes: self.imageHashes = localHashes
        print("Stage 1 complete. Found \(exactDupsRaw.count) exact duplicate groups.")


        // ===== Stage 2: Near Duplicates =====
        await MainActor.run { self.updateProgress(progress: 1.0/3.0, message: "Stage 2/3: Finding near duplicates...") } // Start at 1/3
        print("Starting near duplicate analysis...")

        var representativeURLs: [URL] = []
        for (_, urls) in localHashes { // Use hashes from Stage 1
            if let firstURL = urls.first { representativeURLs.append(firstURL) }
        }
        print("Identified \(representativeURLs.count) representative images for Stage 2.")

        var processedCountStage2 = 0
        let totalStage2 = representativeURLs.count
        if totalStage2 > 0 {
            // Only execute Stage 2 processing IF there are representatives
            var processedCountStage2 = 0
            
            for representativeURL in representativeURLs {
                guard self.isAnalyzing else { print("Analysis cancelled (Stage 2)"); return }
                if processedCountStage2 % 5 == 0 { await Task.yield() }
                
                let filename = representativeURL.lastPathComponent
                let currentFileURL = activatedFolderURL.appendingPathComponent(filename)
                var imageData: Data? = nil
                
                do {
                    imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe)
                } catch {
                    print("Loop 2 ERROR: Could not load data for \(filename): \(error)")
                    processedCountStage2 += 1
                    let progress = (1.0/3.0) + (Double(processedCountStage2) / Double(totalStage2) * (1.0/3.0)) // Stage 2 is 1/3
                    await self.updateProgress(progress: progress, message: "Stage 2/3: Analyzing \(processedCountStage2)/\(totalStage2) (Load Failed)")
                    continue
                }
                
                var calculatedPrint: VNFeaturePrintObservation? = nil
                if let dataToProcess = imageData {
                    calculatedPrint = await Task.detached(priority: .userInitiated) {
                        return await VisionService.generateFeaturePrint(from: dataToProcess)
                    }.value
                }
                
                if let featurePrint = calculatedPrint {
                    localFeaturePrints[representativeURL] = featurePrint // Use original URL as key
                }
                
                processedCountStage2 += 1
                let progress = (1.0/3.0) + (Double(processedCountStage2) / Double(totalStage2) * (1.0/3.0)) // Stage 2 is 1/3
                await self.updateProgress(progress: progress, message: "Stage 2/3: Analyzing \(processedCountStage2)/\(totalStage2)")
            } // End Stage 2 loop
            
            guard self.isAnalyzing else { print("Analysis cancelled after Stage 2 loop."); return }
            // Optionally store all prints: self.imageFeaturePrints = localFeaturePrints
            
            // --- Grouping Near Duplicates ---
            print("Grouping near duplicates using threshold: \(nearDuplicateThreshold)...")
            var clusteredURLs = Set<URL>()
            let urlsWithPrints = Array(localFeaturePrints.keys)
            for i in 0..<urlsWithPrints.count {
                let url1 = urlsWithPrints[i]
                guard !clusteredURLs.contains(url1), let print1 = localFeaturePrints[url1] else { continue }
                var currentGroup: [URL] = [url1]
                for j in (i + 1)..<urlsWithPrints.count {
                    let url2 = urlsWithPrints[j]
                    guard !clusteredURLs.contains(url2), let print2 = localFeaturePrints[url2] else { continue }
                    if let distance = VisionService.calculateDistance(between: print1, and: print2), distance < nearDuplicateThreshold {
                        currentGroup.append(url2)
                        clusteredURLs.insert(url2)
                    }
                }
                if currentGroup.count > 1 {
                    clusteredURLs.insert(url1)
                    nearDupsRaw.append(currentGroup) // Add the group of original URLs
                }
            }
            print("Stage 2 complete. Found \(nearDupsRaw.count) near duplicate groups.")
        } else{
            // This block executes if totalStage2 was 0
                     print("Stage 2: No representative images to analyze. Skipping near duplicate processing.")
                     // No need to do anything else here, just proceed to Stage 3
        }
        
        guard self.isAnalyzing else { print("Analysis cancelled before Stage 3."); return }

        // ===== Stage 3: Quality Assessment =====
        await MainActor.run { self.updateProgress(progress: 2.0/3.0, message: "Stage 3/3: Assessing quality...") } // Start at 2/3
        print("Starting quality assessment...")

        var processedCountStage3 = 0
        let totalGroupsToProcess = exactDupsRaw.count + nearDupsRaw.count
        guard totalGroupsToProcess > 0 else {
            print("No duplicate groups found to assess quality.")
            await MainActor.run { finalizeAnalysis() }
            return
        }

        // Process Exact Groups
        for (_, urls) in exactDupsRaw {
             guard self.isAnalyzing else { print("Analysis cancelled (Stage 3 Exact)"); return }
             if processedCountStage3 % 2 == 0 { await Task.yield() }
             var bestScore: Float = -1.0
             var bestUrlInGroup: URL? = urls.first

             for imageURL in urls { // imageURL is original URL
                 let filename = imageURL.lastPathComponent
                 let currentFileURL = activatedFolderURL.appendingPathComponent(filename)
                 var imageData: Data? = nil
                 do { imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe) }
                 catch { print("QUALITY ERROR: Load failed for \(filename): \(error)"); continue }

                 if let dataToScore = imageData {
                     let score = await Task.detached(priority: .utility) { ImageQualityAnalyzer.calculateSharpnessScore(from: dataToScore) }.value
                     if let score = score, score > bestScore { bestScore = score; bestUrlInGroup = imageURL }
                 }
             } // End inner loop (files in group)
             finalGroups.append(DuplicateGroup(urls: urls, bestURL: bestUrlInGroup, isExact: true))
             processedCountStage3 += 1
             let progress = (2.0/3.0) + (Double(processedCountStage3) / Double(totalGroupsToProcess) * (1.0/3.0))
             await self.updateProgress(progress: progress, message: "Stage 3/3: Assessing quality \(processedCountStage3)/\(totalGroupsToProcess)")
        } // End exact groups loop

        // Process Near Groups
        for urls in nearDupsRaw {
             guard self.isAnalyzing else { print("Analysis cancelled (Stage 3 Near)"); return }
             if processedCountStage3 % 2 == 0 { await Task.yield() }
             var bestScore: Float = -1.0
             var bestUrlInGroup: URL? = urls.first

             for imageURL in urls { // imageURL is original URL
                 let filename = imageURL.lastPathComponent
                 let currentFileURL = activatedFolderURL.appendingPathComponent(filename)
                 var imageData: Data? = nil
                 do { imageData = try Data(contentsOf: currentFileURL, options: .mappedIfSafe) }
                 catch { print("QUALITY ERROR: Load failed for \(filename): \(error)"); continue }

                 if let dataToScore = imageData {
                     let score = await Task.detached(priority: .utility) { ImageQualityAnalyzer.calculateSharpnessScore(from: dataToScore) }.value
                     if let score = score, score > bestScore { bestScore = score; bestUrlInGroup = imageURL }
                 }
             } // End inner loop
             finalGroups.append(DuplicateGroup(urls: urls, bestURL: bestUrlInGroup, isExact: false))
             processedCountStage3 += 1
             let progress = (2.0/3.0) + (Double(processedCountStage3) / Double(totalGroupsToProcess) * (1.0/3.0))
             await self.updateProgress(progress: progress, message: "Stage 3/3: Assessing quality \(processedCountStage3)/\(totalGroupsToProcess)")
        } // End near groups loop

        guard self.isAnalyzing else { print("Analysis cancelled after Stage 3 loop."); return }
        print("Quality assessment complete. Found \(finalGroups.count) total groups.")

        // --- Final State Update ---
        await MainActor.run {
            self.duplicateGroups = finalGroups // Update the @Published property
            self.finalizeAnalysis()
        }
    } // End performAnalysis

} // End Class AnalysisViewModel
