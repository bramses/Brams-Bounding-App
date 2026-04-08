//
//  SettingsView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI
import CloudKit

struct SettingsView: View {
    @AppStorage("claudeAPIKey") private var apiKey: String = ""
    @State private var showingSaveConfirmation = false
    @State private var diagnosticResult: String?
    @State private var isRunningDiagnostics = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // Logo header
                Section {
                    HStack {
                        Spacer()
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 100)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                Section {
                    SecureField("Enter Claude API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Claude AI API Key")
                } footer: {
                    Text("Your API key is stored securely on your device and is only used to communicate with Claude AI for image analysis.")
                }
                
                Section {
                    Link("Get API Key from Anthropic", destination: URL(string: "https://console.anthropic.com/")!)
                }
                
                Section {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud")
                        Spacer()
                        if CloudSyncState.isActive {
                            Text("Active")
                                .foregroundColor(.green)
                        } else {
                            Text("Local Only")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if let reason = CloudSyncState.failureReason, !CloudSyncState.isActive {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    Button {
                        runDiagnostics()
                    } label: {
                        HStack {
                            Label("Run iCloud Diagnostics", systemImage: "stethoscope")
                            Spacer()
                            if isRunningDiagnostics {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRunningDiagnostics)
                    
                    if let diagnosticResult {
                        Text(diagnosticResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text(CloudSyncState.isActive
                         ? "Your photos and bounding boxes sync across all your iCloud devices."
                         : "iCloud sync is unavailable. Data is stored locally on this device only.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("From the Developer", systemImage: "info.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                        
                        Text("Want to become a serious reader? Download [Bram's Reading App](https://apps.apple.com/us/app/brams-reading-app/id6759291875) on the App Store.")
                            .font(.subheadline)
                        
                        Text("This app is open source! View the code on [GitHub](https://github.com/bramses/Brams-Bounding-App/tree/main).")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension SettingsView {
    private func runDiagnostics() {
        isRunningDiagnostics = true
        diagnosticResult = nil
        
        Task {
            var lines: [String] = []
            
            // 1. Check iCloud account status
            let container = CKContainer(identifier: "iCloud.bram.Brams-Bounding-App")
            do {
                let status = try await container.accountStatus()
                switch status {
                case .available:
                    lines.append("iCloud account: Available")
                case .noAccount:
                    lines.append("iCloud account: Not signed in")
                case .restricted:
                    lines.append("iCloud account: Restricted")
                case .couldNotDetermine:
                    lines.append("iCloud account: Could not determine")
                case .temporarilyUnavailable:
                    lines.append("iCloud account: Temporarily unavailable")
                @unknown default:
                    lines.append("iCloud account: Unknown status (\(status.rawValue))")
                }
            } catch {
                lines.append("iCloud account check failed: \(error.localizedDescription)")
            }
            
            // 2. Check container accessibility
            let db = container.privateCloudDatabase
            do {
                // Try to fetch zones to verify container is accessible
                let zones = try await db.allRecordZones()
                lines.append("CloudKit zones: \(zones.map(\.zoneID.zoneName).joined(separator: ", "))")
            } catch {
                lines.append("CloudKit zone fetch failed: \(error.localizedDescription)")
            }
            
            // 3. Report ModelContainer state
            lines.append("SwiftData CloudKit: \(CloudSyncState.isActive ? "Active" : "Failed")")
            if let reason = CloudSyncState.failureReason {
                lines.append("Failure: \(reason)")
            }
            
            // 4. Container ID
            lines.append("Container: \(container.containerIdentifier ?? "nil")")
            
            await MainActor.run {
                diagnosticResult = lines.joined(separator: "\n")
                isRunningDiagnostics = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
