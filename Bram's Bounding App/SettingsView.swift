//
//  SettingsView.swift
//  Bram's Grounding App
//
//  Created by Bram Adams on 4/6/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("claudeAPIKey") private var apiKey: String = ""
    @State private var showingSaveConfirmation = false
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
                    VStack(alignment: .leading, spacing: 8) {
                        Label("From the Developer", systemImage: "info.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                        
                        Text("Want to become a serious reader? Download [Bram's Reading App](https://apps.apple.com/us/app/brams-reading-app/id6759291875) on the App Store.")
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

#Preview {
    SettingsView()
}
