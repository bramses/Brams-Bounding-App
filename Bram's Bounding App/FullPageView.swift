//
//  FullPageView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData

struct FullPageView: View {
    let page: SavedPage
    var highlightedBox: BoundingBox?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedBox: BoundingBox?
    @State private var isEditMode = false
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: !isEditMode) {
                    if let image = page.image {
                        ImageWithBoundingBoxes(
                            image: image,
                            boundingBoxes: page.boundingBoxes,
                            highlightedBox: highlightedBox,
                            containerWidth: geometry.size.width,
                            isEditMode: isEditMode,
                            modelContext: modelContext,
                            onBoxTap: { box in
                                if !isEditMode {
                                    selectedBox = box
                                }
                            }
                        )
                    }
                }
                .scrollDisabled(isEditMode)
            }
            .navigationTitle("Full Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        Button(isEditMode ? "Done" : "Edit") {
                            withAnimation {
                                isEditMode.toggle()
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedBox) { box in
                BoundingBoxDetailView(boundingBox: box)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = page.image {
                    ShareSheet(items: [image])
                }
            }
        }
    }
}

struct ImageWithBoundingBoxes: View {
    let image: UIImage
    let boundingBoxes: [BoundingBox]
    let highlightedBox: BoundingBox?
    let containerWidth: CGFloat
    let isEditMode: Bool
    let modelContext: ModelContext
    let onBoxTap: (BoundingBox) -> Void
    
    var body: some View {
        GeometryReader { imageGeometry in
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                // Draw bounding boxes relative to the actual rendered image
                ForEach(boundingBoxes, id: \.id) { box in
                    if isEditMode {
                        DraggableBoundingBox(
                            box: box,
                            renderedSize: imageGeometry.size,
                            isHighlighted: highlightedBox?.id == box.id,
                            modelContext: modelContext
                        )
                    } else {
                        BoundingBoxOverlay(
                            box: box,
                            renderedSize: imageGeometry.size,
                            isHighlighted: highlightedBox?.id == box.id,
                            action: {
                                onBoxTap(box)
                            }
                        )
                    }
                }
            }
        }
        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
        .frame(width: containerWidth)
    }
}

struct DraggableBoundingBox: View {
    let box: BoundingBox
    let renderedSize: CGSize
    let isHighlighted: Bool
    let modelContext: ModelContext
    
    @State private var currentOffset = CGSize.zero
    @State private var isDragging = false
    @State private var resizeMode: ResizeMode?
    
    enum ResizeMode {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private var boxWidth: CGFloat { box.width * renderedSize.width }
    private var boxHeight: CGFloat { box.height * renderedSize.height }
    private var boxX: CGFloat { box.x * renderedSize.width }
    private var boxY: CGFloat { box.y * renderedSize.height }
    
    var body: some View {
        ZStack {
            // Main bounding box
            Rectangle()
                .stroke(isHighlighted ? Color.yellow : Color.blue, lineWidth: 3)
                .background(Color.blue.opacity(0.2))
            
            // Resize handles
            ResizeHandle(position: .topLeft)
            ResizeHandle(position: .topRight)
            ResizeHandle(position: .bottomLeft)
            ResizeHandle(position: .bottomRight)
        }
        .frame(width: boxWidth, height: boxHeight)
        .offset(
            x: boxX + currentOffset.width,
            y: boxY + currentOffset.height
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    currentOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    updateBoxPosition(translation: value.translation)
                    currentOffset = .zero
                }
        )
    }
    
    private func updateBoxPosition(translation: CGSize) {
        // Calculate new position in normalized coordinates
        let newX = max(0, min(1, (boxX + translation.width) / renderedSize.width))
        let newY = max(0, min(1, (boxY + translation.height) / renderedSize.height))
        
        // Ensure box stays within bounds
        let maxX = 1 - box.width
        let maxY = 1 - box.height
        
        box.x = min(maxX, max(0, newX))
        box.y = min(maxY, max(0, newY))
        
        // Save to database
        do {
            try modelContext.save()
            print("Updated box position: x=\(box.x), y=\(box.y)")
        } catch {
            print("Failed to save box position: \(error)")
        }
    }
    
    @ViewBuilder
    private func ResizeHandle(position: ResizeMode) -> some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .offset(
                x: position == .topLeft || position == .bottomLeft ? -boxWidth / 2 : boxWidth / 2,
                y: position == .topLeft || position == .topRight ? -boxHeight / 2 : boxHeight / 2
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        resizeBox(position: position, translation: value.translation)
                    }
                    .onEnded { _ in
                        saveBoxDimensions()
                    }
            )
    }
    
    private func resizeBox(position: ResizeMode, translation: CGSize) {
        let deltaX = translation.width / renderedSize.width
        let deltaY = translation.height / renderedSize.height
        
        switch position {
        case .topLeft:
            box.x = max(0, box.x + deltaX)
            box.y = max(0, box.y + deltaY)
            box.width = max(0.05, box.width - deltaX)
            box.height = max(0.05, box.height - deltaY)
        case .topRight:
            box.y = max(0, box.y + deltaY)
            box.width = max(0.05, min(1 - box.x, box.width + deltaX))
            box.height = max(0.05, box.height - deltaY)
        case .bottomLeft:
            box.x = max(0, box.x + deltaX)
            box.width = max(0.05, box.width - deltaX)
            box.height = max(0.05, min(1 - box.y, box.height + deltaY))
        case .bottomRight:
            box.width = max(0.05, min(1 - box.x, box.width + deltaX))
            box.height = max(0.05, min(1 - box.y, box.height + deltaY))
        }
    }
    
    private func saveBoxDimensions() {
        do {
            try modelContext.save()
            print("Updated box dimensions: x=\(box.x), y=\(box.y), w=\(box.width), h=\(box.height)")
        } catch {
            print("Failed to save box dimensions: \(error)")
        }
    }
}

struct BoundingBoxOverlay: View {
    let box: BoundingBox
    let renderedSize: CGSize
    let isHighlighted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Rectangle()
                .stroke(isHighlighted ? Color.yellow : Color.red, lineWidth: isHighlighted ? 4 : 2)
                .background(isHighlighted ? Color.yellow.opacity(0.3) : Color.red.opacity(0.15))
        }
        .frame(
            width: box.width * renderedSize.width,
            height: box.height * renderedSize.height
        )
        .offset(
            x: box.x * renderedSize.width,
            y: box.y * renderedSize.height
        )
    }
}

#Preview {
    let page = SavedPage(imageData: Data())
    let box1 = BoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.2, extractedText: "Sample text 1")
    let box2 = BoundingBox(x: 0.5, y: 0.5, width: 0.4, height: 0.3, extractedText: "Sample text 2")
    page.boundingBoxes = [box1, box2]
    
    return FullPageView(page: page, highlightedBox: box1)
}
