//
//  SearchView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allPages: [SavedPage]
    @State private var searchText = ""
    @State private var selectedBox: BoundingBox?
    @State private var showingSettings = false
    
    var onAddPhoto: () -> Void
    var failedCount: Int
    var onShowFailed: () -> Void
    
    // Filter bounding boxes based on search text
    private var filteredBoxes: [BoundingBox] {
        let allBoxes = allPages.flatMap { $0.boundingBoxes ?? [] }
        
        if searchText.isEmpty {
            return allBoxes.sorted { $0.timestamp > $1.timestamp }
        } else {
            return allBoxes.filter { box in
                box.extractedText.localizedCaseInsensitiveContains(searchText)
            }.sorted { $0.timestamp > $1.timestamp }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search saved content", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Results list
                if filteredBoxes.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Start searching to find saved content" : "No matches found for '\(searchText)'")
                    )
                } else {
                    List(filteredBoxes, id: \.id) { box in
                        Button(action: {
                            selectedBox = box
                        }) {
                            BoundingBoxRowView(box: box)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                        }
                        
                        if failedCount > 0 {
                            Button(action: {
                                onShowFailed()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("\(failedCount)")
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
                        onAddPhoto()
                    }) {
                        Label("Add Photo", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $selectedBox) { box in
                BoundingBoxDetailView(boundingBox: box)
            }
        }
    }
}

struct BoundingBoxRowView: View {
    let box: BoundingBox
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(box.extractedText)
                    .font(.body)
                    .lineLimit(2)
                
                Text(box.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: box.id) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: box)
        }
    }
}

/// Lightweight snapshots for passing SwiftData objects to background tasks.
struct BoxThumbnailSnapshot: Sendable {
    let id: UUID
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct PageThumbnailSnapshot: Sendable {
    let imageData: Data
    let boxes: [BoxThumbnailSnapshot]
}

/// Generates and caches cropped thumbnails off the main thread.
actor ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private var cache: [UUID: UIImage] = [:]
    
    func getCached(_ id: UUID) -> UIImage? {
        cache[id]
    }
    
    /// Single-box fallback (used by BoundingBoxRowView if preload hasn't run yet).
    func thumbnail(for box: BoundingBox) async -> UIImage? {
        if let cached = cache[box.id] {
            return cached
        }
        
        guard let page = box.page,
              let imageData = page.imageData as Data? else { return nil }
        
        let snapshot = PageThumbnailSnapshot(
            imageData: imageData,
            boxes: [BoxThumbnailSnapshot(id: box.id, x: box.x, y: box.y, width: box.width, height: box.height)]
        )
        
        let results = await Self.generateThumbnails(for: snapshot)
        for (id, image) in results {
            cache[id] = image
        }
        return cache[box.id]
    }
    
    /// Preload thumbnails for all pages. Groups by page so each full image is
    /// decoded only once, then all its boxes are cropped in a single pass.
    /// Call from main actor after snapshotting SwiftData objects.
    func preloadAll(pageSnapshots: [PageThumbnailSnapshot]) async {
        // Filter to only uncached boxes
        let uncached = pageSnapshots.compactMap { snapshot -> PageThumbnailSnapshot? in
            let needed = snapshot.boxes.filter { cache[$0.id] == nil }
            guard !needed.isEmpty else { return nil }
            return PageThumbnailSnapshot(imageData: snapshot.imageData, boxes: needed)
        }
        
        guard !uncached.isEmpty else { return }
        
        // Process pages concurrently (max 3 at a time to limit memory)
        await withTaskGroup(of: [(UUID, UIImage)].self) { group in
            var running = 0
            var index = 0
            
            while index < uncached.count || running > 0 {
                // Launch tasks up to concurrency limit
                while running < 3 && index < uncached.count {
                    let snapshot = uncached[index]
                    index += 1
                    running += 1
                    group.addTask {
                        await Self.generateThumbnails(for: snapshot)
                    }
                }
                
                // Collect one result
                if let results = await group.next() {
                    running -= 1
                    for (id, image) in results {
                        cache[id] = image
                    }
                }
            }
        }
    }
    
    /// Pure function: decodes the page image once and crops all boxes.
    /// Runs outside actor isolation for true parallelism.
    private static func generateThumbnails(for snapshot: PageThumbnailSnapshot) async -> [(UUID, UIImage)] {
        await Task.detached(priority: .utility) {
            guard let fullImage = UIImage(data: snapshot.imageData),
                  let oriented = fullImage.fixedOrientation(),
                  let cgImage = oriented.cgImage else { return [] }
            
            let imgSize = CGSize(width: cgImage.width, height: cgImage.height)
            var results: [(UUID, UIImage)] = []
            
            for box in snapshot.boxes {
                let rect = CGRect(
                    x: box.x * imgSize.width,
                    y: box.y * imgSize.height,
                    width: box.width * imgSize.width,
                    height: box.height * imgSize.height
                )
                guard let cropped = cgImage.cropping(to: rect) else { continue }
                
                let thumbSize = CGSize(width: 112, height: 112)
                let renderer = UIGraphicsImageRenderer(size: thumbSize)
                let thumb = renderer.image { _ in
                    UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: thumbSize))
                }
                results.append((box.id, thumb))
            }
            return results
        }.value
    }
}

#Preview {
    SearchView(onAddPhoto: {}, failedCount: 0, onShowFailed: {})
        .modelContainer(for: SavedPage.self, inMemory: true)
}
