import PhotosUI
import SwiftUI

@MainActor
struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(.secondarySystemBackground)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    // Spacer(minLength: 32)
                    // Profile photo with floating trash button
                    ZStack(alignment: .bottomTrailing) {
                        ProfilePhotoView(
                            image: viewModel.displayImage, name: viewModel.name, size: 120
                        )
                        .padding(.top, 16)
                        .onTapGesture { showPhotoPicker = true }
                        .photosPicker(
                            isPresented: $showPhotoPicker, selection: $viewModel.selectedItem,
                            matching: .images)

                        if viewModel.displayImage != nil {
                            Button(action: { viewModel.removePhoto() }) {
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

                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            TextField("Your Name", text: $viewModel.name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .font(.body)
                                .padding(.horizontal, 12)
                        }
                        .frame(height: 44)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Sign out button
                    Button("Sign Out") {
                        authService.signOut()
                    }
                    .foregroundColor(.red)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            if viewModel.isEdited {
                                await viewModel.saveChanges()
                            }
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .task {
                await viewModel.loadProfile()
            }
        }
    }
}

struct ImagePickerView: View {
    @Binding var selectedItem: PhotosPickerItem?
    let displayImage: Image?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ProfileImageView(image: displayImage)
        }
    }
}

private struct ProfileImageView: View {
    let image: Image?

    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.gray)
            }
        }
    }
}
