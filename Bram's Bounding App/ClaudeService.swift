//
//  ClaudeService.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import Foundation
import UIKit

// Structure for Claude API request and response
struct ClaudeMessage: Codable {
    let role: String
    let content: [ContentBlock]
    
    struct ContentBlock: Codable {
        let type: String
        let text: String?
        let source: ImageSource?
        
        struct ImageSource: Codable {
            let type: String
            let mediaType: String
            let data: String
            
            enum CodingKeys: String, CodingKey {
                case type
                case mediaType = "media_type"
                case data
            }
        }
    }
}

struct ClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let messages: [ClaudeMessage]
    
    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

struct ClaudeResponse: Codable {
    let content: [ContentItem]
    
    struct ContentItem: Codable {
        let text: String?
    }
}

// Detected bounding box from Claude's analysis
struct DetectedBoundingBox {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let extractedText: String
}

enum ClaudeError: LocalizedError, Equatable {
    case imageConversionFailed
    case timeout
    case apiError(Int, String)
    case invalidResponse
    case noContent
    case parseFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Failed to convert image to JPEG"
        case .timeout: return "Request timed out. Image will be queued for retry."
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .invalidResponse: return "Invalid response from API"
        case .noContent: return "No content in response"
        case .parseFailed(let msg): return "Failed to parse response: \(msg)"
        }
    }
}

class ClaudeService {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let timeoutInterval: TimeInterval = 15
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // Compress image to be under maxSizeMB
    static func compressImage(_ image: UIImage, maxSizeMB: Double = 5.0) -> Data? {
        let maxBytes = Int(maxSizeMB * 1024 * 1024)
        var quality: CGFloat = 0.9
        
        while quality > 0.1 {
            if let data = image.jpegData(compressionQuality: quality) {
                if data.count <= maxBytes {
                    return data
                }
            }
            quality -= 0.1
        }
        
        // If still too large, resize the image
        let scale = sqrt(Double(maxBytes) / Double(image.jpegData(compressionQuality: 0.1)?.count ?? maxBytes))
        if scale < 1 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return resized.jpegData(compressionQuality: 0.7)
        }
        
        return image.jpegData(compressionQuality: 0.1)
    }
    
    // Analyze image and detect circled/boxed regions
    func analyzePage(image: UIImage) async throws -> [DetectedBoundingBox] {
        guard let imageData = ClaudeService.compressImage(image) else {
            throw ClaudeError.imageConversionFailed
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let prompt = """
        Analyze this image carefully. Determine what type of image this is and respond accordingly:
        
        **If this is a handwritten/hand-drawn page or document:**
        Look for sections that have circles, ovals, squares, rectangles, or other closed shapes drawn around text or images. Only include regions that are clearly marked with enclosing shapes. Ignore unmarked text or images.
        
        **If this is a photo, screenshot, or any other type of image:**
        Identify the most salient and visually distinct objects, people, text, or regions of interest. Focus on the key subjects and notable elements — things a person would naturally point to or want to highlight.
        
        COORDINATE INSTRUCTIONS:
        - Coordinate system: (0,0) at TOP-LEFT corner
        - x increases going RIGHT, y increases going DOWN
        - All values are normalized between 0 and 1 relative to full image dimensions
        - x = left edge of bounding box (0 = left side of image, 1 = right side)
        - y = top edge of bounding box (0 = top of image, 1 = bottom)
        - width = horizontal span of the bounding box
        - height = vertical span of the bounding box
        - Bounding boxes should tightly fit around the identified region
        
        For each identified region:
        1. Provide a precise bounding box
        2. For text: transcribe it exactly as written
        3. For objects/people/drawings: provide a short, clear description
        
        Return ONLY valid JSON in this exact format (no markdown, no extra text):
        {
          "boundingBoxes": [
            {
              "x": 0.1,
              "y": 0.2,
              "width": 0.3,
              "height": 0.15,
              "content": "transcribed text or description of object"
            }
          ]
        }
        
        Be precise with coordinates. Each bounding box must accurately represent where the region is located in the image.
        """
        
        let message = ClaudeMessage(
            role: "user",
            content: [
                ClaudeMessage.ContentBlock(
                    type: "image",
                    text: nil,
                    source: ClaudeMessage.ContentBlock.ImageSource(
                        type: "base64",
                        mediaType: "image/jpeg",
                        data: base64Image
                    )
                ),
                ClaudeMessage.ContentBlock(
                    type: "text",
                    text: prompt,
                    source: nil
                )
            ]
        )
        
        let request = ClaudeRequest(
            model: "claude-opus-4-6",
            maxTokens: 4096,
            messages: [message]
        )
        
        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw ClaudeError.timeout
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        
        guard let responseText = claudeResponse.content.first?.text else {
            throw ClaudeError.noContent
        }
        
        return try parseBoundingBoxes(from: responseText)
    }
    
    // Parse JSON response from Claude to extract bounding boxes
    private func parseBoundingBoxes(from text: String) throws -> [DetectedBoundingBox] {
        print("Claude response text: \(text)")
        
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.contains("```json") {
            // Extract content between ```json and ```
            let components = jsonString.components(separatedBy: "```json")
            if components.count > 1 {
                let afterStart = components[1]
                let jsonComponents = afterStart.components(separatedBy: "```")
                if jsonComponents.count > 0 {
                    jsonString = jsonComponents[0].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } else if jsonString.contains("```") {
            // Extract content between ``` and ```
            let components = jsonString.components(separatedBy: "```")
            if components.count > 1 {
                jsonString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Find the JSON object boundaries
        if let startIndex = jsonString.firstIndex(of: "{") {
            jsonString = String(jsonString[startIndex...])
            
            // Find matching closing brace by counting braces
            var braceCount = 0
            var endIndex: String.Index?
            
            for (index, char) in jsonString.enumerated() {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = jsonString.index(jsonString.startIndex, offsetBy: index)
                        break
                    }
                }
            }
            
            if let endIndex = endIndex {
                jsonString = String(jsonString[...endIndex])
            }
        }
        
        // If JSON is incomplete, try to fix it
        if !jsonString.hasSuffix("}") {
            // Count opening and closing braces
            let openBraces = jsonString.filter { $0 == "{" }.count
            let closeBraces = jsonString.filter { $0 == "}" }.count
            
            if openBraces > closeBraces {
                // Add missing closing braces
                jsonString += String(repeating: "}", count: openBraces - closeBraces)
            }
        }
        
        print("Extracted JSON string: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "ClaudeService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data"])
        }
        
        struct BoundingBoxResponse: Codable {
            let boundingBoxes: [Box]
            
            struct Box: Codable {
                let x: Double
                let y: Double
                let width: Double
                let height: Double
                let content: String
            }
        }
        
        do {
            let response = try JSONDecoder().decode(BoundingBoxResponse.self, from: jsonData)
            
            print("Parsed \(response.boundingBoxes.count) bounding boxes")
            for (index, box) in response.boundingBoxes.enumerated() {
                print("Box \(index): x=\(box.x), y=\(box.y), w=\(box.width), h=\(box.height), content=\(box.content)")
            }
            
            return response.boundingBoxes.map { box in
                DetectedBoundingBox(
                    x: box.x,
                    y: box.y,
                    width: box.width,
                    height: box.height,
                    extractedText: box.content
                )
            }
        } catch {
            print("JSON decode error: \(error)")
            print("Failed JSON string: \(jsonString)")
            throw NSError(domain: "ClaudeService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to decode JSON: \(error.localizedDescription)"])
        }
    }
}
