//
//  Bram_s_Grounding_AppApp.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import SwiftData
import CoreData

/// Tracks whether the CloudKit-backed store loaded successfully.
enum CloudSyncState {
    static var isActive = false
    static var failureReason: String?
}

private let cloudKitContainerID = "iCloud.bram.Brams-Bounding-App"

@main
struct Bram_s_Grounding_AppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedPage.self,
            BoundingBox.self,
        ])
        
        // Step 1: Initialize the CloudKit development schema using Core Data.
        // This is required for new containers before SwiftData can sync.
        #if DEBUG
        initializeCloudKitSchema(schema: schema)
        #endif
        
        // Step 2: Create SwiftData container with CloudKit sync
        do {
            let config = ModelConfiguration(
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            CloudSyncState.isActive = true
            return container
        } catch {
            print("CloudKit ModelContainer failed: \(error). Using local store.")
            CloudSyncState.isActive = false
            CloudSyncState.failureReason = "\(error)"
            do {
                let localConfig = ModelConfiguration(
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
    
    /// Initialize CloudKit development schema as described in Apple docs.
    /// Uses NSPersistentCloudKitContainer to push the schema to CloudKit servers.
    private static func initializeCloudKitSchema(schema: Schema) {
        autoreleasepool {
            // Use the same default store URL that SwiftData would use
            let config = ModelConfiguration()
            let desc = NSPersistentStoreDescription(url: config.url)
            let opts = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
            desc.cloudKitContainerOptions = opts
            desc.shouldAddStoreAsynchronously = false
            
            if let mom = NSManagedObjectModel.makeManagedObjectModel(for: [SavedPage.self, BoundingBox.self]) {
                let container = NSPersistentCloudKitContainer(name: "BoundingBox", managedObjectModel: mom)
                container.persistentStoreDescriptions = [desc]
                container.loadPersistentStores { _, err in
                    if let err {
                        print("CloudKit schema init - store load failed: \(err)")
                    }
                }
                do {
                    try container.initializeCloudKitSchema()
                    print("CloudKit schema initialized successfully.")
                } catch {
                    print("CloudKit schema initialization failed: \(error)")
                }
                // Unload the store so SwiftData can use it
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
