import PhotosUI
import SwiftUI

struct AssistantSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showInvalidKeyAlert = false
    @State private var showEmptyNameAlert = false
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(.secondarySystemBackground)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    // Profile photo with floating trash button
                    ZStack(alignment: .bottomTrailing) {
                        ProfilePhotoView(
                            image: viewModel.assistantProfileImage,
                            name: viewModel.assistantName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty ? "ChatGPT" : viewModel.assistantName,
                            size: 120,
                            placeholderColor: User.generatePlaceholderColor(
                                for: viewModel.assistantName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty ? "ChatGPT" : viewModel.assistantName)
                        )
                        .padding(.top, 16)
                        .onTapGesture { showPhotoPicker = true }
                        .photosPicker(
                            isPresented: $showPhotoPicker,
                            selection: $viewModel.assistantPhotoPickerItem,
                            matching: .images
                        )
                        if viewModel.assistantProfileImage != nil {
                            Button(action: {
                                viewModel.assistantProfileImage = nil
                                viewModel.assistantProfileImageData = nil
                                viewModel.assistantProfileImageURL = nil
                                Task { await viewModel.updateAssistantProfileImage() }
                            }) {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                    .padding(10)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                        } else {
                            Button(action: { showPhotoPicker = true }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(Color.accentColor)
                                    .padding(10)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                        }
                    }

                    // Assistant Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASSISTANT NAME")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            TextField("Assistant Name", text: $viewModel.assistantName)
                                .autocorrectionDisabled()
                                .font(.body)
                                .padding(.horizontal, 12)
                        }
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal)

                    // Custom Instructions field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM INSTRUCTIONS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            TextEditor(text: $viewModel.customInstructions)
                                .font(.body)
                                .padding(8)
                                .background(Color.clear)
                        }
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Customize Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
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
    }
}
