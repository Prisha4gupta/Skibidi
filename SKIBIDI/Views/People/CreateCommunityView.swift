import SwiftUI
import PhotosUI
struct CreateCommunityView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var communityName = ""
    /// Set when the community is created — presents the system invite sheet so the flow goes
    /// straight from "Create" into sharing the link.
    @State private var shareData: ShareSheetData?
    @State private var isCreating = false

    @State private var photoItem: PhotosPickerItem?
    /// Compressed JPEG of the chosen avatar — stored on the community so every member sees it.
    @State private var imageData: Data?

    private var canCreate: Bool {
        !communityName.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    imageUploadArea

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Community's Name", text: $communityName)
                            .font(.body)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isCreating = true
                            shareData = await viewModel.createCommunity(name: communityName, imageData: imageData)
                            isCreating = false
                            // Success → the invite sheet shows (and dismisses us afterwards).
                            // Failure (no iCloud etc., already logged) → just close.
                            if shareData == nil { dismiss() }
                        }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                        } else {
                            Text("Create")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                                .background(canCreate ? Color.blue : Color(.systemGray4))
                                .clipShape(Capsule())
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .sheet(item: $shareData, onDismiss: { dismiss() }) { data in
                CloudSharingView(share: data.share, container: data.container)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var imageUploadArea: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(height: 140)
                    .overlay {
                        if let imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiaryText)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("Add photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                imageData = Self.downscaledJPEG(uiImage)
            }
        }
    }

    /// Community avatars don't need full-resolution source images, and CloudKit records
    /// shouldn't carry megabytes — clamp to ~512px and JPEG-compress before upload.
    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 512, quality: CGFloat = 0.7) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

#Preview {
    CreateCommunityView(viewModel: CommunityViewModel())
}
