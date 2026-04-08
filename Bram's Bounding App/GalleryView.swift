//
//  GalleryView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/7/26.
//

import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPage.timestamp, order: .reverse) private var pages: [SavedPage]
    @State private var selectedPage: SavedPage?
    @State private var showingSettings = false
    
    var onAddPhoto: () -> Void
    var failedCount: Int
    var onShowFailed: () -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos you save will appear here")
                    )
                } else {
                    galleryGrid
                }
            }
            .navigationTitle("Gallery")
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
            .sheet(item: $selectedPage) { page in
                FullPageView(page: page)
            }
        }
    }
    
    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(pages, id: \.id) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        GalleryThumbnail(page: page)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deletePage(page)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
    
    private func deletePage(_ page: SavedPage) {
        withAnimation {
            for box in page.boundingBoxes {
                EmbeddingCache.shared.remove(for: box.id)
            }
            modelContext.delete(page)
            try? modelContext.save()
        }
    }
}

struct GalleryThumbnail: View {
    let page: SavedPage
    
    var body: some View {
        GeometryReader { geometry in
            if let image = page.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .clipped()
            } else {
                Color(.systemGray5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if page.boundingBoxes.count > 0 {
                Text("\(page.boundingBoxes.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(4)
            }
        }
    }
}

#Preview {
    GalleryView(onAddPhoto: {}, failedCount: 0, onShowFailed: {})
        .modelContainer(for: SavedPage.self, inMemory: true)
}
