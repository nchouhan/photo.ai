//
//  ContentView.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//
import SwiftUI
import UniformTypeIdentifiers // For UTType

struct ContentView: View {
    // Use @StateObject if ContentView creates the VM (less common for shared state)
    // Use @ObservedObject if VM is passed via initializer
    // Use @EnvironmentObject if VM is injected via .environmentObject() in App struct
    @EnvironmentObject var viewModel: AnalysisViewModel

    // Local state ONLY for UI presentation (like showing the sheet)
    @State private var showDocumentPicker = false

    // MARK: - Computed Properties for Display Logic

    private var exactGroupCount: Int {
        viewModel.duplicateGroups.filter { $0.isExact }.count
    }
    private var nearGroupCount: Int {
        viewModel.duplicateGroups.filter { !$0.isExact }.count
    }
    private var totalExactFilesCount: Int {
         viewModel.duplicateGroups.filter { $0.isExact }.reduce(0) { $0 + $1.urls.count }
    }
    private var totalNearFilesCount: Int {
         viewModel.duplicateGroups.filter { !$0.isExact }.reduce(0) { $0 + $1.urls.count }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            VStack(spacing: 15) {

                // --- Folder Selection Info ---
                if let folderName = viewModel.selectedFolderName {
                    Text("Folder: \(folderName)")
                        .font(.headline)
                        .padding(.bottom, 1) // Add little space below folder name
                    if let errorMsg = viewModel.pickerErrorMessage {
                        Text("Error: \(errorMsg)") // Show picker/access errors prominently
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    } else if !viewModel.imageFileURLs.isEmpty && !viewModel.isAnalyzing && viewModel.analysisMessage.contains("completed") && viewModel.duplicateGroups.isEmpty {
                         // Explicitly show "No duplicates found" ONLY if analysis completed successfully but found none
                        Text("No duplicates found in this folder.")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .padding(.top, 5)
                    } else if !viewModel.imageFileURLs.isEmpty && !viewModel.isAnalyzing {
                        // Show file count if analysis hasn't started or is finished (and found results)
                         Text("\(viewModel.imageFileURLs.count) image files found.")
                             .font(.subheadline)
                             .foregroundColor(.secondary)
                     }

                } else if !viewModel.isAnalyzing {
                    Spacer()
                    Text("Select an iCloud Drive folder containing photos to begin analysis.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // --- Analysis Progress Indicator ---
                if viewModel.isAnalyzing {
                    ProgressView(value: viewModel.analysisProgress, total: 1.0) {
                        Text(viewModel.analysisMessage)
                            .font(.caption)
                    } currentValueLabel: {
                        Text("\(Int(viewModel.analysisProgress * 100))%")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.top, 5) // Add some space above progress bar
                }

                 // --- Results List ---
                 // Show list ONLY if analysis is NOT running AND there ARE results
                 if !viewModel.isAnalyzing && !viewModel.duplicateGroups.isEmpty {
                    // Summary Header (Optional, outside List for better placement)
                     VStack(alignment: .leading, spacing: 4) {
                          if exactGroupCount > 0 {
                              Text("• Found \(exactGroupCount) groups of exact duplicates (\(totalExactFilesCount) files).")
                                  .font(.subheadline)
                                  .foregroundColor(.green)
                          }
                          if nearGroupCount > 0 {
                               Text("• Found \(nearGroupCount) groups of near duplicates (\(totalNearFilesCount) files).")
                                  .font(.subheadline)
                                  .foregroundColor(.blue)
                          }
                     }
                     .padding(.horizontal) // Add padding to summary text
                     .padding(.top, 10)

                     // The List of Groups
                     List {
                         // Section header provides context within the list
                          Section(header: Text("Groups (\(viewModel.duplicateGroups.count))")
                                         .font(.callout)
                                         .foregroundColor(.secondary)) {
                             ForEach(viewModel.duplicateGroups) { group in
                                 NavigationLink {
                                      // Pass group, inject VM if detail view needs actions
                                      GroupDetailView(group: group)
                                          .environmentObject(viewModel)
                                 } label: {
                                     GroupRowView(group: group)
                                 }
                             }
                          }
                     }
                     .listStyle(.plain) // Or .insetGrouped
                     // Add flexible frame to allow list to take available space
                     // .frame(maxHeight: .infinity)

                 } else if viewModel.selectedFolderName != nil && !viewModel.isAnalyzing && viewModel.analysisMessage.contains("completed") && viewModel.duplicateGroups.isEmpty {
                     // If analysis is done, no groups found, show message (already handled above, this is slightly redundant but safe)
                     // Text("No duplicates found.") ... (Handled within folder name section)
                 }

                // --- Action Button ---
                // Place button logically, maybe not always at the bottom if list is long
                Button {
                    // Don't reset analysis state here, ViewModel handles it in presentPicker
                    // viewModel.presentPicker() // ViewModel method handles reset logic
                    showDocumentPicker = true // Just trigger the sheet
                } label: {
                    Label(viewModel.selectedFolderName != nil ? "Select Another Folder" : "Select Folder",
                          systemImage: "folder.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .disabled(viewModel.isAnalyzing) // Disable while analyzing

                // Use spacer to push button up if list is short, or keep content centered if no list
                if viewModel.duplicateGroups.isEmpty && !viewModel.isAnalyzing {
                     Spacer()
                }


            } // End VStack
            .padding(.vertical) // Add padding top/bottom of VStack
            .navigationTitle("PhotoClean")
        } // End NavigationView
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showDocumentPicker) {
            // Pass the ViewModel to the wrapper so Coordinator can call VM methods
            DocumentPickerWrapper(viewModel: viewModel)
        }
//        .onAppear {
//             // Optional: Reload folder name on appear, VM handles internal state loading
//             viewModel.loadPersistentFolderInfo() // Ensure folder name loads if app restarts
//        }

    } // End Body
} // End ContentView

// MARK: - Document Picker Wrapper (Needs access to ViewModel)

struct DocumentPickerWrapper: UIViewControllerRepresentable {
    @ObservedObject var viewModel: AnalysisViewModel // Use ObservedObject here

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Coordinator needs reference back to wrapper to access ViewModel
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerWrapper

        init(_ parent: DocumentPickerWrapper) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.viewModel.folderSelected(url: nil, urls: [], error: "Failed to get URL from picker.")
                return
            }

            // Perform initial scan synchronously using picker's temporary grant
            // Need to wrap this in access calls
            print("Coordinator: Attempting initial access for scan...")
            guard url.startAccessingSecurityScopedResource() else {
                print("Coordinator ERROR: Failed initial access for file listing.")
                parent.viewModel.folderSelected(url: nil, urls: [], error: "Could not access folder contents.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource(); print("Coordinator: Stopped initial access.") }

            print("Coordinator: Initial access granted. Scanning files...")
            let foundURLs = findImageFiles(at: url) // Call helper

            // Call ViewModel method with results (ViewModel saves bookmark & triggers analysis)
            parent.viewModel.folderSelected(url: url, urls: foundURLs, error: nil)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Picker cancelled.")
            // No action needed for ViewModel usually when cancelled
        }

        // findImageFiles helper (can be kept private here or moved to a utility)
        private func findImageFiles(at directoryURL: URL) -> [URL] {
             var foundImageURLs: [URL] = []
             let imageTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .gif, .bmp]
             let fileManager = FileManager.default
             let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .contentTypeKey]
             let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
             guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: resourceKeys, options: options, errorHandler: { url, error -> Bool in print("Error enumerating \(url.path): \(error.localizedDescription)"); return true }) else { return [] }
             for case let fileURL as URL in enumerator {
                 do {
                     let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                     if resourceValues.isDirectory == true { continue }
                     if let contentType = resourceValues.contentType, imageTypes.contains(where: { contentType.conforms(to: $0) }) { foundImageURLs.append(fileURL) }
                 } catch { print("Error getting resource values for \(fileURL.path): \(error)") }
             }
             print("Coordinator found \(foundImageURLs.count) image files.")
             return foundImageURLs
         }

    } // End Coordinator
} // End DocumentPickerWrapper


// MARK: - Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
         let previewViewModel = AnalysisViewModel()
         // Example: Add dummy data to preview results list
         // let url1 = URL(string:"file:///image1.jpg")!
         // let url2 = URL(string:"file:///image2.jpg")!
         // previewViewModel.duplicateGroups = [
         //     DuplicateGroup(urls: [url1, url2], bestURL: url1, isExact: true)
         // ]
         // previewViewModel.selectedFolderName = "Preview Folder"
         // previewViewModel.imageFileURLs = [url1, url2] // Simulate files found

         ContentView()
             .environmentObject(previewViewModel) // Provide VM to preview
    }
}
