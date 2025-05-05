import SwiftUI

struct AssistantSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showInvalidKeyAlert = false
    @State private var showEmptyNameAlert = false

    var body: some View {
        Form {
            Section {
                ZStack {
                    SecureField("OpenAI API Key", text: $viewModel.apiKey)
                        .padding(.trailing, 32)
                    if !viewModel.apiKey.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: { viewModel.apiKey = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            // .padding(.trailing, 8)
                        }
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                HStack(spacing: 4) {
                    Text("Get your OPEN AI key")
                        .font(.footnote)
                        .fontWeight(.regular)
                    Link("here", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundColor(.blue)
                }
            }

            Section {
                TextField("Assistant Name", text: $viewModel.assistantName)
            } header: {
                Text("Assistant Name")
            }

            Section {
                TextEditor(text: $viewModel.customInstructions)
                    .frame(height: 100)
            } header: {
                Text("Custom Instructions")
            }
        }
        .navigationTitle("Assistant Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveChanges()
                }
            }
        }
        .alert("Invalid API Key", isPresented: $showInvalidKeyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid OpenAI API key starting with 'sk-'")
        }
        .alert("Invalid Assistant Name", isPresented: $showEmptyNameAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid assistant name")
        }
    }

    private func saveChanges() {
        let trimmedName = viewModel.assistantName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            showEmptyNameAlert = true
            return
        }
        let key = viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && !(key.starts(with: "sk-") && key.count > 20) {
            showInvalidKeyAlert = true
            return
        }
        viewModel.updateAPIKey(key)
        viewModel.updateAssistantName(trimmedName)
        viewModel.updateCustomInstructions(viewModel.customInstructions)
        dismiss()
    }
}
