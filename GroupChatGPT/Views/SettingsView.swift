import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false
    @State private var isClearing = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OPENAI API KEY")) {
                    TextEditor(text: $viewModel.apiKey)
                        .frame(height: 100)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))

                    if !viewModel.apiKey.isEmpty {
                        Button(role: .destructive, action: viewModel.clearAPIKey) {
                            Text("Clear API Key")
                        }
                    }
                }

                Section {
                    Link(
                        "Get API Key",
                        destination: URL(string: "https://platform.openai.com/api-keys")!)
                }

                Section {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        HStack {
                            Text("Clear Conversation")
                            if isClearing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearing)
                } footer: {
                    Text("This will permanently delete all messages in the conversation.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear Conversation", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        isClearing = true
                        await viewModel.clearAllMessages()
                        isClearing = false
                    }
                }
            } message: {
                Text("Are you sure you want to clear all messages? This action cannot be undone.")
            }
        }
    }
}
