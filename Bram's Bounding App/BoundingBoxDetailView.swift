//
//  BoundingBoxDetailView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData

// Outer wrapper that owns the NavigationStack — presented as a sheet
struct BoundingBoxDetailView: View {
    let boundingBox: BoundingBox
    @Environment(\.dismiss) private var dismiss
    @State private var path: [BoundingBox] = []
    
    var body: some View {
        NavigationStack(path: $path) {
            BoundingBoxDetailContent(boundingBox: boundingBox, path: $path)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: BoundingBox.self) { box in
                    BoundingBoxDetailContent(boundingBox: box, path: $path)
                }
        }
    }
}

// Reusable content view used for both the root and pushed destinations
struct BoundingBoxDetailContent: View {
    let boundingBox: BoundingBox
    @Binding var path: [BoundingBox]
    @Environment(\.modelContext) private var modelContext
    @Query private var allPages: [SavedPage]
    @State private var showingFullPage = false
    @State private var similarItems: [SimilarItem] = []
    @State private var isLoadingSimilar = true
    @State private var showingShareSheet = false
    
    private var allBoxes: [BoundingBox] {
        allPages.flatMap { $0.boundingBoxes ?? [] }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Show cropped image section if available
                if let page = boundingBox.page,
                   let image = page.image {
                    croppedImageView(from: image)
                        .frame(maxHeight: 400)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                }
                
                // Extracted text content
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extracted Content")
                        .font(.headline)
                    
                    Text(boundingBox.extractedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                // Metadata
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.headline)
                    
                    HStack {
                        Text("Date:")
                            .foregroundStyle(.secondary)
                        Text(boundingBox.timestamp, style: .date)
                        Text(boundingBox.timestamp, style: .time)
                    }
                    .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Action buttons row
                HStack(spacing: 12) {
                    // See full page
                    if boundingBox.page != nil {
                        Button(action: {
                            showingFullPage = true
                        }) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("Full Photo")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(10)
                        }
                    }
                    
                    // Share original image
                    if boundingBox.page?.image != nil {
                        Button(action: {
                            showingShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Similar items section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Similar Sections")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if isLoadingSimilar {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Finding similar content...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else if similarItems.isEmpty {
                        Text("No similar sections found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(similarItems, id: \.box.id) { item in
                            Button {
                                path.append(item.box)
                            } label: {
                                SimilarItemRow(item: item)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("Saved Section")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFullPage) {
            if let page = boundingBox.page {
                FullPageView(page: page, highlightedBox: boundingBox)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = boundingBox.page?.image {
                ShareSheet(items: [image])
            }
        }
        .onAppear {
            computeSimilarItems()
        }
    }
    
    private func computeSimilarItems() {
        isLoadingSimilar = true
        Task {
            let boxes = allBoxes
            let results = await SimilarityService.findSimilarAsync(
                to: boundingBox,
                from: boxes
            )
            similarItems = results
            isLoadingSimilar = false
        }
    }
    
    // Crop the image to show only the bounding box region
    @ViewBuilder
    private func croppedImageView(from image: UIImage) -> some View {
        if let croppedImage = cropImage(image, to: boundingBox) {
            Image(uiImage: croppedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
    
    // Crop UIImage to bounding box coordinates
    private func cropImage(_ image: UIImage, to box: BoundingBox) -> UIImage? {
        guard let orientedImage = image.fixedOrientation() else {
            return nil
        }
        
        guard let cgImage = orientedImage.cgImage else {
            return nil
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        let rect = CGRect(
            x: box.x * imageSize.width,
            y: box.y * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
        
        guard let croppedCGImage = cgImage.cropping(to: rect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage)
    }
}

// Extension to fix image orientation issues
extension UIImage {
    func fixedOrientation() -> UIImage? {
        // If image is already in correct orientation, return as is
        if imageOrientation == .up {
            return self
        }
        
        guard let cgImage = self.cgImage else { return nil }
        
        // Calculate the size after orientation correction
        var transform = CGAffineTransform.identity
        let size = self.size
        
        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }
        
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        context.concatenate(transform)
        
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        
        guard let newCGImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: newCGImage)
    }
}

struct SimilarItemRow: View {
    let item: SimilarItem
    
    // Map cosine distance (0-2) to a percentage (100%-0%)
    private var similarityPercent: Int {
        Int(max(0, (1 - item.distance / 2)) * 100)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail if available
            if let page = item.box.page,
               let image = page.image,
               let cropped = cropThumbnail(image: image, box: item.box) {
                Image(uiImage: cropped)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.box.extractedText)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                Text("\(similarityPercent)% similar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private func cropThumbnail(image: UIImage, box: BoundingBox) -> UIImage? {
        guard let oriented = image.fixedOrientation(),
              let cgImage = oriented.cgImage else { return nil }
        
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let rect = CGRect(
            x: box.x * size.width,
            y: box.y * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
        
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let box = BoundingBox(x: 0.1, y: 0.1, width: 0.8, height: 0.3, extractedText: "Sample extracted text from the bounding box")
    BoundingBoxDetailView(boundingBox: box)
        .modelContainer(for: SavedPage.self, inMemory: true)
}
