<img src="https://github.com/bramses/Brams-Bounding-App/blob/main/Bram's%20Bounding%20App/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="250" />

<img width="200" alt="Simulator Screenshot - iPhone 16 Pro this - 2026-04-08 at 01 45 41" src="https://github.com/user-attachments/assets/2f1fa936-3947-46ad-b1ea-8512a4b923e9" />
<img width="200" alt="Simulator Screenshot - iPhone 16 Pro this - 2026-04-08 at 01 45 37" src="https://github.com/user-attachments/assets/5ed12638-c2bf-4980-8627-ff71a6d077e0" />
<img width="200" alt="Simulator Screenshot - iPhone 16 Pro this - 2026-04-08 at 01 45 22" src="https://github.com/user-attachments/assets/aedcc838-d872-48a3-849f-8528141a37e9" />
<img width="200" alt="Simulator Screenshot - iPhone 16 Pro this - 2026-04-08 at 01 45 18" src="https://github.com/user-attachments/assets/f01d87aa-1642-447f-ab54-b56eb381e279" />
<img width="200" alt="Simulator Screenshot - iPhone 16 Pro this - 2026-04-08 at 01 45 05" src="https://github.com/user-attachments/assets/42a242d5-dde3-4e17-8513-03d6f4217a63" />
<img width="200" alt="Simulator Screenshot - iPhone 16 Pro this - 2026-04-08 at 01 44 42" src="https://github.com/user-attachments/assets/5185b642-8b74-4bb9-bbd0-b58b9670123f" />


# Bram's Bounding App

An iOS app that uses Claude AI to analyze photos and extract salient regions (circled sections, boxed areas, or notable objects) for easy searching and reference.

## Features

- **Multi-Photo Selection**: Take photos with the camera or select multiple from your library
- **AI-Powered Analysis**: Claude AI automatically detects circled/boxed regions on handwritten pages, or salient objects in general photos
- **Review Flow**: Walk through each detected bounding box before saving — edit text, reposition boxes, or delete unwanted ones
- **Gallery View**: Browse saved photos in a Photos-like grid layout
- **Search**: Search through all saved sections by their extracted content, with thumbnail previews
- **Semantic Similarity**: Uses Apple's NLEmbedding to find similar sections across your library
- **Full Photo View**: See the original photo with all bounding boxes highlighted, with edit mode for repositioning
- **Share/Export**: Share original photos directly from the app
- **iCloud Sync**: Automatically syncs your photos and bounding boxes across all your iCloud devices via CloudKit
- **Retry Queue**: Failed analyses are queued with retry support
- **Image Compression**: Automatically compresses large images before sending to the API

## Setup

### 1. Get a Claude API Key

1. Visit [console.anthropic.com](https://console.anthropic.com/)
2. Sign up or log in
3. Generate an API key

### 2. Configure in App

1. Build and run the app in Xcode
2. Tap the gear icon in the navigation bar
3. Enter your Claude API key
4. Tap "Done"

## Usage

### Adding Photos

1. Tap the "+" button in the Gallery or Search tab
2. Choose "Take Photo" or "Choose from Library" (supports multiple selection)
3. The app analyzes each image with Claude AI
4. Review detected sections one by one — edit text, adjust boxes, or delete
5. Approved sections are saved to your library

### Searching

1. Go to the Search tab
2. Type keywords to search through extracted content
3. Tap a result to view details, similar sections, or the full photo

### Viewing Photos

1. In the Gallery tab, tap a photo to see it full-size with bounding boxes
2. Tap individual boxes to view extracted content and similar sections
3. Use Edit mode to drag and resize bounding boxes

## Architecture

- **SwiftUI** with **SwiftData** for persistence
- **CloudKit** for iCloud sync across devices
- **Claude API** (claude-opus-4-6) for image analysis
- **NLEmbedding** for semantic similarity search
- **PhotosUI** for multi-photo selection

### Key Models

- **SavedPage**: Stores the original image data and timestamp
- **BoundingBox**: Stores normalized coordinates (0-1 range), extracted text, and page relationship

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Claude API key from Anthropic

## Privacy

- Your API key is stored on-device using AppStorage
- Images are only sent to Claude AI during analysis
- iCloud sync uses Apple's CloudKit — your data is stored in your private iCloud container and is never accessible to the developer
- All similarity computations run on-device using Apple's NLEmbedding
