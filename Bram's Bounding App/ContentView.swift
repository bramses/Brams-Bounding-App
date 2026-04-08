//
//  ContentView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPage.timestamp, order: .reverse) private var pages: [SavedPage]
    @State private var selectedTab = 0
    
    // Add photo state
    @State private var showingSourceSelector = false
    @State private var showingImagePicker = false
    @State private var showingMultiPicker = false
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var errorMessage: String?
    @State private var showingReview = false
    @State private var capturedImage: UIImage?
    @State private var detectedBoxes: [DetectedBoundingBox] = []
    @State private var failedImages: [FailedImage] = []
    @State private var showingFailedQueue = false
    @State private var imageQueue: [UIImage] = []
    @AppStorage("claudeAPIKey") private var apiKey: String = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GalleryView(
                onAddPhoto: { triggerAddPhoto() },
                failedCount: failedImages.count,
                onShowFailed: { showingFailedQueue = true }
            )
            .tabItem {
                Label("Gallery", systemImage: "square.grid.2x2")
            }
            .tag(0)
            
            SearchView(
                onAddPhoto: { triggerAddPhoto() },
                failedCount: failedImages.count,
                onShowFailed: { showingFailedQueue = true }
            )
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(1)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera) { image in
                processImage(image)
            }
        }
        .sheet(isPresented: $showingMultiPicker) {
            NavigationStack {
                MultiPhotoPicker { images in
                    processMultipleImages(images)
                }
                .navigationTitle("Select Photos")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            if let image = capturedImage, !detectedBoxes.isEmpty {
                BoundingBoxReviewView(
                    image: image,
                    detectedBoxes: detectedBoxes,
                    onComplete: { approvedBoxes in
                        saveReviewedBoxes(image: image, boxes: approvedBoxes)
                        showingReview = false
                        processNextInQueue()
                    },
                    onCancel: {
                        showingReview = false
                        capturedImage = nil
                        detectedBoxes = []
                        processNextInQueue()
                    }
                )
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showingSourceSelector) {
            Button("Take Photo") {
                showingImagePicker = true
            }
            Button("Choose from Library") {
                showingMultiPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showingFailedQueue) {
            FailedQueueView(
                failedImages: $failedImages,
                onRetry: { failedImage in
                    retrySingle(failedImage)
                }
            )
        }
        .overlay {
            if isProcessing {
                processingOverlay
            }
        }
        .task(id: pages.count) {
            await preloadThumbnails()
        }
    }
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text(processingStatus.isEmpty ? "Analyzing photo with Claude AI..." : processingStatus)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(Color(.systemGray6))
            .cornerRadius(20)
        }
    }
    
    private func triggerAddPhoto() {
        if apiKey.isEmpty {
            errorMessage = "Please set your Claude API key in Settings first"
        } else {
            showingSourceSelector = true
        }
    }
    
    private func processMultipleImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        
        if images.count == 1 {
            processImage(images[0])
        } else {
            imageQueue = Array(images.dropFirst())
            processImage(images[0])
        }
    }
    
    private func processNextInQueue() {
        // Don't process next if review is showing
        guard !showingReview else { return }
        guard !imageQueue.isEmpty else { return }
        let next = imageQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            processImage(next)
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        let remaining = imageQueue.count
        processingStatus = remaining > 0
            ? "Analyzing image (\(remaining) more in queue)..."
            : "Analyzing photo with Claude AI..."
        
        Task {
            do {
                let claudeService = ClaudeService(apiKey: apiKey)
                let boxes = try await claudeService.analyzePage(image: image)
                
                await MainActor.run {
                    isProcessing = false
                    
                    if boxes.isEmpty {
                        errorMessage = "No sections detected in the image."
                        processNextInQueue()
                    } else {
                        capturedImage = image
                        detectedBoxes = boxes
                        showingReview = true
                    }
                }
            } catch let error as ClaudeError where error == .timeout {
                await MainActor.run {
                    failedImages.append(FailedImage(image: image, error: "Request timed out. Check your connection and try again."))
                    isProcessing = false
                    processNextInQueue()
                }
            } catch {
                await MainActor.run {
                    failedImages.append(FailedImage(image: image, error: error.localizedDescription))
                    isProcessing = false
                    processNextInQueue()
                }
            }
        }
    }
    
    // Retry a single failed image — processes it through the normal flow
    private func retrySingle(_ failedImage: FailedImage) {
        // Don't retry while reviewing or processing
        guard !showingReview && !isProcessing else {
            errorMessage = "Please finish reviewing the current photo first."
            return
        }
        
        failedImages.removeAll { $0.id == failedImage.id }
        showingFailedQueue = false
        // Small delay to let sheet dismiss before processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            processImage(failedImage.image)
        }
    }
    
    private func saveReviewedBoxes(image: UIImage, boxes: [DetectedBoundingBox]) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to save image"
            return
        }
        
        let newPage = SavedPage(imageData: imageData)
        
        for detectedBox in boxes {
            let box = BoundingBox(
                x: detectedBox.x,
                y: detectedBox.y,
                width: detectedBox.width,
                height: detectedBox.height,
                extractedText: detectedBox.extractedText
            )
            box.page = newPage
            if newPage.boundingBoxes == nil { newPage.boundingBoxes = [] }
            newPage.boundingBoxes?.append(box)
            modelContext.insert(box)
        }
        
        modelContext.insert(newPage)
        
        do {
            try modelContext.save()
            EmbeddingCache.shared.precomputeAsync(for: newPage.boundingBoxes ?? [])
        } catch {
            errorMessage = "Failed to save photo: \(error.localizedDescription)"
        }
        
        capturedImage = nil
        detectedBoxes = []
    }
    
    private func preloadThumbnails() async {
        let snapshots = pages.map { page in
            PageThumbnailSnapshot(
                imageData: page.imageData,
                boxes: (page.boundingBoxes ?? []).map { box in
                    BoxThumbnailSnapshot(id: box.id, x: box.x, y: box.y, width: box.width, height: box.height)
                }
            )
        }
        await ThumbnailCache.shared.preloadAll(pageSnapshots: snapshots)
    }
}

// MARK: - Failed Queue View

struct FailedQueueView: View {
    @Binding var failedImages: [FailedImage]
    let onRetry: (FailedImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if failedImages.isEmpty {
                    ContentUnavailableView(
                        "No Failed Images",
                        systemImage: "checkmark.circle",
                        description: Text("All images processed successfully")
                    )
                } else {
                    List {
                        ForEach(failedImages) { item in
                            FailedImageRow(
                                item: item,
                                onRetry: {
                                    onRetry(item)
                                }
                            )
                        }
                        .onDelete { offsets in
                            failedImages.remove(atOffsets: offsets)
                        }
                        
                        Section {
                            Button(role: .destructive) {
                                failedImages.removeAll()
                            } label: {
                                Label("Discard All", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Failed Images (\(failedImages.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FailedImageRow: View {
    let item: FailedImage
    let onRetry: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail of the failed image
            Image(uiImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()
            
            // Error details
            VStack(alignment: .leading, spacing: 4) {
                Text("Analysis Failed")
                    .font(.subheadline.weight(.semibold))
                
                Text(item.error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(10)
            }
            
            Spacer()
            
            // Retry button
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedPage.self, inMemory: true)
}
