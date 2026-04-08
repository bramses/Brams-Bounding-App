//
//  SimilarityService.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/7/26.
//

import Foundation
import NaturalLanguage

struct SimilarItem {
    let box: BoundingBox
    let distance: Double
}

// MARK: - Embedding Cache

/// Caches NLEmbedding vectors so we only compute each text's vector once.
/// Uses NSCache for automatic memory management plus a text hash
/// to detect when content changes.
class EmbeddingCache {
    static let shared = EmbeddingCache()
    
    private var vectorCache: [UUID: (textHash: Int, vector: [Double])] = [:]
    private let lock = NSLock()
    
    func getVector(for id: UUID, text: String, embedding: NLEmbedding) -> [Double]? {
        let hash = text.hashValue
        
        lock.lock()
        if let cached = vectorCache[id], cached.textHash == hash {
            lock.unlock()
            return cached.vector
        }
        lock.unlock()
        
        // Compute and cache
        guard let vector = embedding.vector(for: text) else { return nil }
        
        lock.lock()
        vectorCache[id] = (textHash: hash, vector: vector)
        lock.unlock()
        
        return vector
    }
    
    func remove(for id: UUID) {
        lock.lock()
        vectorCache.removeValue(forKey: id)
        lock.unlock()
    }
    
    /// Pre-compute embeddings for a set of boxes in the background
    func precomputeAsync(for boxes: [BoundingBox]) {
        let snapshots: [(UUID, String)] = boxes.compactMap { box in
            let text = box.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (box.id, text)
        }
        
        Task.detached(priority: .background) { [weak self] in
            guard let self,
                  let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return }
            
            for (id, text) in snapshots {
                _ = self.getVector(for: id, text: text, embedding: embedding)
            }
        }
    }
}

// MARK: - Lightweight structs for background thread

private struct BoxSnapshot: Sendable {
    let id: UUID
    let text: String
}

private struct DistanceResult: Sendable {
    let id: UUID
    let distance: Double
}

// MARK: - Similarity Service

class SimilarityService {
    
    /// Find the nearest neighbors to a given bounding box.
    /// Uses cached vectors when available for fast lookups.
    static func findSimilarAsync(
        to target: BoundingBox,
        from allBoxes: [BoundingBox],
        maxCount: Int = 5
    ) async -> [SimilarItem] {
        let targetText = target.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetText.isEmpty else { return [] }
        
        // Snapshot data on the main thread
        let targetId = target.id
        let snapshots: [BoxSnapshot] = allBoxes.compactMap { box in
            guard box.id != targetId else { return nil }
            let text = box.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return BoxSnapshot(id: box.id, text: text)
        }
        
        guard !snapshots.isEmpty else { return [] }
        
        // Compute distances on background thread using cached vectors
        let cache = EmbeddingCache.shared
        
        let distanceResults: [DistanceResult] = await Task.detached(priority: .utility) {
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                return []
            }
            
            guard let targetVector = cache.getVector(
                for: targetId,
                text: targetText,
                embedding: embedding
            ) else {
                return []
            }
            
            var results: [DistanceResult] = []
            
            for snapshot in snapshots {
                guard let vector = cache.getVector(
                    for: snapshot.id,
                    text: snapshot.text,
                    embedding: embedding
                ) else { continue }
                
                // Compute cosine distance from cached vectors
                let distance = cosineDist(targetVector, vector)
                if distance.isFinite {
                    results.append(DistanceResult(id: snapshot.id, distance: distance))
                }
            }
            
            results.sort { $0.distance < $1.distance }
            return Array(results.prefix(maxCount))
        }.value
        
        // Map back to model objects
        let boxLookup = Dictionary(uniqueKeysWithValues: allBoxes.map { ($0.id, $0) })
        return distanceResults.compactMap { result in
            guard let box = boxLookup[result.id] else { return nil }
            return SimilarItem(box: box, distance: result.distance)
        }
    }
}

// MARK: - Vector Math

/// Cosine distance between two vectors (0 = identical, 2 = opposite)
private func cosineDist(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return .infinity }
    
    var dot = 0.0
    var normA = 0.0
    var normB = 0.0
    
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    
    let denom = sqrt(normA) * sqrt(normB)
    guard denom > 0 else { return .infinity }
    
    // cosine similarity in [-1, 1], distance = 1 - similarity
    return 1.0 - (dot / denom)
}
