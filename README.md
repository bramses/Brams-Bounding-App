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
- **Retry Queue**: Failed analyses are queued with retry support
- **Image Compression**: Automatically compresses large images (>5MB) before sending to the API

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
- No data is stored on external servers except during API calls
- All similarity computations run on-device using Apple's NLEmbedding
