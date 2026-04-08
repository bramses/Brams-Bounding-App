//
//  FeedView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData
import PhotosUI

// Track failed images for retry
struct FailedImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let error: String
    var retryCount: Int = 0
}

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPage.timestamp, order: .reverse) private var pages: [SavedPage]
    @State private var selectedPage: SavedPage?
    @State private var showingImagePicker = false
    @State private var showingMultiPicker = false
    @State private var showingSourceSelector = false
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showingReview = false
    @State private var capturedImage: UIImage?
    @State private var detectedBoxes: [DetectedBoundingBox] = []
    @State private var failedImages: [FailedImage] = []
    @State private var showingFailedQueue = false
    // Multi-image processing queue
    @State private var imageQueue: [UIImage] = []
    @AppStorage("claudeAPIKey") private var apiKey: String = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty && failedImages.isEmpty {
                    emptyStateView
                } else {
                    feedScrollView
                }
            }
            .navigationTitle("My Photos")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                        }
                        
                        if !failedImages.isEmpty {
                            Button(action: {
                                showingFailedQueue = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("\(failedImages.count)")
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        if apiKey.isEmpty {
                            errorMessage = "Please set your Claude API key in Settings first"
                        } else {
                            showingSourceSelector = true
                        }
                    }) {
                        Label("Add Photo", systemImage: "plus")
                    }
                    .disabled(isProcessing)
                }
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
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $selectedPage) { page in
                FullPageView(page: page)
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
            .alert("Failed Images", isPresented: $showingFailedQueue) {
                Button("Retry All") {
                    retryAllFailed()
                }
                Button("Discard All", role: .destructive) {
                    failedImages.removeAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(failedImages.count) image(s) failed to process. Would you like to retry?")
            }
            .overlay {
                if isProcessing {
                    processingOverlay
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Photos Yet",
            systemImage: "doc.text.image",
            description: Text("Take a photo or choose from your library to get started")
        )
    }
    
    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(pages, id: \.id) { page in
                    PageCardView(page: page) {
                        selectedPage = page
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deletePage(page)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deletePage(page)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
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
    
    // Process multiple images in sequence
    private func processMultipleImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        
        if images.count == 1 {
            processImage(images[0])
        } else {
            // Queue all but the first, process the first immediately
            imageQueue = Array(images.dropFirst())
            processImage(images[0])
        }
    }
    
    // Process next image in queue after review completes
    private func processNextInQueue() {
        guard !imageQueue.isEmpty else { return }
        let next = imageQueue.removeFirst()
        // Small delay to let sheets dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            processImage(next)
        }
    }
    
    // Process image with Claude AI
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
                    failedImages.append(FailedImage(image: image, error: "Timed out"))
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
    
    // Retry all failed images
    private func retryAllFailed() {
        let imagesToRetry = failedImages.map { $0.image }
        failedImages.removeAll()
        processMultipleImages(imagesToRetry)
    }
    
    // Save reviewed boxes after user approval
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
            // Pre-compute embeddings for the new boxes in the background
            EmbeddingCache.shared.precomputeAsync(for: newPage.boundingBoxes ?? [])
        } catch {
            errorMessage = "Failed to save photo: \(error.localizedDescription)"
        }
        
        capturedImage = nil
        detectedBoxes = []
    }
    
    // Delete a page and all its bounding boxes
    private func deletePage(_ page: SavedPage) {
        withAnimation {
            // Clear cached embeddings for deleted boxes
            for box in page.boundingBoxes ?? [] {
                EmbeddingCache.shared.remove(for: box.id)
            }
            modelContext.delete(page)
            do {
                try modelContext.save()
            } catch {
                errorMessage = "Failed to delete photo: \(error.localizedDescription)"
            }
        }
    }
}

struct PageCardView: View {
    let page: SavedPage
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Page thumbnail
                if let image = page.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(12)
                }
                
                // Page info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("\((page.boundingBoxes ?? []).count) sections", systemImage: "square.on.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(page.timestamp, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Preview of first bounding box
                    if let firstBox = page.boundingBoxes?.first {
                        Text(firstBox.extractedText)
                            .font(.body)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FeedView()
        .modelContainer(for: SavedPage.self, inMemory: true)
}
