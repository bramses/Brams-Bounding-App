//
//  BoundingBoxReviewView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData

struct BoundingBoxReviewView: View {
    let image: UIImage
    let detectedBoxes: [DetectedBoundingBox]
    let onComplete: ([DetectedBoundingBox]) -> Void
    let onCancel: () -> Void
    
    @State private var currentIndex = 0
    @State private var reviewedBoxes: [ReviewedBox] = []
    @State private var editedText = ""
    @FocusState private var isTextEditorFocused: Bool
    
    struct ReviewedBox {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var content: String
    }
    
    private var currentBox: ReviewedBox? {
        guard currentIndex < reviewedBoxes.count else { return nil }
        return reviewedBoxes[currentIndex]
    }
    
    private var totalBoxes: Int {
        reviewedBoxes.count
    }
    
    private var completedCount: Int {
        currentIndex
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                VStack(spacing: 8) {
                    Text("\(currentIndex + 1) of \(totalBoxes)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: Double(currentIndex + 1), total: Double(totalBoxes))
                        .tint(.blue)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                
                // Image with current bounding box
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                            
                            if currentIndex < reviewedBoxes.count {
                                DraggableReviewBox(
                                    box: $reviewedBoxes[currentIndex],
                                    renderedSize: calculateRenderedSize(geometry: geometry),
                                    onUpdate: { newBox in
                                        reviewedBoxes[currentIndex] = newBox
                                    }
                                )
                            }
                        }
                        .frame(width: geometry.size.width)
                    }
                }
                
                // Text editing section
                VStack(spacing: 16) {
                    HStack {
                        Text("Extracted Content")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isTextEditorFocused {
                            Button("Done") {
                                isTextEditorFocused = false
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                    }
                    
                    TextEditor(text: $editedText)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .focused($isTextEditorFocused)
                        .onChange(of: editedText) { _, newValue in
                            reviewedBoxes[currentIndex].content = newValue
                        }
                }
                .padding()
                .background(Color(.systemBackground))
                
                // Action buttons
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Delete button
                        Button(action: deleteCurrentBox) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        // Looks good / Next button
                        Button(action: approveCurrentBox) {
                            HStack {
                                Image(systemName: "checkmark")
                                Text(currentIndex < totalBoxes - 1 ? "Next" : "Finish")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    Text("Drag the box to reposition • Edit text above • Tap Delete to remove")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Review Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            initializeReviewedBoxes()
        }
    }
    
    private func calculateRenderedSize(geometry: GeometryProxy) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerWidth = geometry.size.width
        let renderedHeight = containerWidth / imageAspect
        return CGSize(width: containerWidth, height: renderedHeight)
    }
    
    private func initializeReviewedBoxes() {
        reviewedBoxes = detectedBoxes.map { box in
            ReviewedBox(
                x: box.x,
                y: box.y,
                width: box.width,
                height: box.height,
                content: box.extractedText
            )
        }
        if let first = reviewedBoxes.first {
            editedText = first.content
        }
    }
    
    private func deleteCurrentBox() {
        isTextEditorFocused = false
        
        withAnimation {
            reviewedBoxes.remove(at: currentIndex)
            
            if reviewedBoxes.isEmpty {
                // No boxes left, complete with empty array
                completeReview()
            } else if currentIndex >= reviewedBoxes.count {
                // Was last box, go to previous
                currentIndex = reviewedBoxes.count - 1
                editedText = currentBox?.content ?? ""
            } else {
                // Update text for new current box
                editedText = currentBox?.content ?? ""
            }
        }
    }
    
    private func approveCurrentBox() {
        isTextEditorFocused = false
        
        if currentIndex < totalBoxes - 1 {
            // Move to next box
            withAnimation {
                currentIndex += 1
                editedText = currentBox?.content ?? ""
            }
        } else {
            // Last box, complete review
            completeReview()
        }
    }
    
    private func completeReview() {
        let finalBoxes = reviewedBoxes.map { box in
            DetectedBoundingBox(
                x: box.x,
                y: box.y,
                width: box.width,
                height: box.height,
                extractedText: box.content
            )
        }
        onComplete(finalBoxes)
    }
}

struct DraggableReviewBox: View {
    @Binding var box: BoundingBoxReviewView.ReviewedBox
    let renderedSize: CGSize
    let onUpdate: (BoundingBoxReviewView.ReviewedBox) -> Void
    
    @State private var currentOffset = CGSize.zero
    
    private var boxWidth: CGFloat { box.width * renderedSize.width }
    private var boxHeight: CGFloat { box.height * renderedSize.height }
    private var boxX: CGFloat { box.x * renderedSize.width }
    private var boxY: CGFloat { box.y * renderedSize.height }
    
    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.yellow, lineWidth: 3)
                .background(Color.yellow.opacity(0.3))
            
            // Corner handles for resize
            ResizeHandle(corner: .topLeft)
            ResizeHandle(corner: .topRight)
            ResizeHandle(corner: .bottomLeft)
            ResizeHandle(corner: .bottomRight)
        }
        .frame(width: boxWidth, height: boxHeight)
        .offset(
            x: boxX + currentOffset.width,
            y: boxY + currentOffset.height
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    currentOffset = value.translation
                }
                .onEnded { value in
                    updatePosition(translation: value.translation)
                    currentOffset = .zero
                }
        )
    }
    
    private func updatePosition(translation: CGSize) {
        let newX = max(0, min(1 - box.width, (boxX + translation.width) / renderedSize.width))
        let newY = max(0, min(1 - box.height, (boxY + translation.height) / renderedSize.height))
        
        box.x = newX
        box.y = newY
        onUpdate(box)
    }
    
    @ViewBuilder
    private func ResizeHandle(corner: Corner) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .offset(
                x: corner == .topLeft || corner == .bottomLeft ? -boxWidth / 2 : boxWidth / 2,
                y: corner == .topLeft || corner == .topRight ? -boxHeight / 2 : boxHeight / 2
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        resizeBox(corner: corner, translation: value.translation)
                    }
            )
    }
    
    private func resizeBox(corner: Corner, translation: CGSize) {
        let deltaX = translation.width / renderedSize.width
        let deltaY = translation.height / renderedSize.height
        
        var newBox = box
        
        switch corner {
        case .topLeft:
            newBox.x = max(0, box.x + deltaX)
            newBox.y = max(0, box.y + deltaY)
            newBox.width = max(0.05, box.width - deltaX)
            newBox.height = max(0.05, box.height - deltaY)
        case .topRight:
            newBox.y = max(0, box.y + deltaY)
            newBox.width = max(0.05, min(1 - box.x, box.width + deltaX))
            newBox.height = max(0.05, box.height - deltaY)
        case .bottomLeft:
            newBox.x = max(0, box.x + deltaX)
            newBox.width = max(0.05, box.width - deltaX)
            newBox.height = max(0.05, min(1 - box.y, box.height + deltaY))
        case .bottomRight:
            newBox.width = max(0.05, min(1 - box.x, box.width + deltaX))
            newBox.height = max(0.05, min(1 - box.y, box.height + deltaY))
        }
        
        box = newBox
        onUpdate(newBox)
    }
    
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

#Preview {
    let sampleImage = UIImage(systemName: "doc.text")!
    let boxes = [
        DetectedBoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.2, extractedText: "Sample text 1"),
        DetectedBoundingBox(x: 0.5, y: 0.5, width: 0.4, height: 0.3, extractedText: "Sample text 2")
    ]
    
    BoundingBoxReviewView(
        image: sampleImage,
        detectedBoxes: boxes,
        onComplete: { _ in },
        onCancel: {}
    )
}
