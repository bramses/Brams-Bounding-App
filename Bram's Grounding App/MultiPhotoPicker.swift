//
//  MultiPhotoPicker.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/7/26.
//

import SwiftUI
import PhotosUI

struct MultiPhotoPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onImagesPicked: ([UIImage]) -> Void
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 20,
            matching: .images
        ) {
            Text("Select Photos")
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            isLoading = true
            
            Task {
                var images: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                
                await MainActor.run {
                    isLoading = false
                    if !images.isEmpty {
                        onImagesPicked(images)
                    }
                    dismiss()
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading photos...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }
}
