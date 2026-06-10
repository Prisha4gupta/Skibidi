import SwiftUI
struct CreateCommunityView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var communityName = ""
    @State private var communityType: CommunityType = .detail
    @State private var dateActive = Date()
    /// Set when the community is created — presents the system invite sheet so the flow goes
    /// straight from "Create" into sharing the link.
    @State private var shareData: ShareSheetData?
    @State private var isCreating = false

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

                    Button {
                    } label: {
                        Text("Add Participants")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    extensionsSection
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
                            shareData = await viewModel.createCommunity(name: communityName)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
                .frame(height: 140)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiaryText)
                    }
                }

            Button("Add photo") {
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.blue)
        }
    }

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Type of community")
                    .font(.body)
                Spacer()
                Picker("", selection: $communityType) {
                    ForEach(CommunityType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(.secondary)
            }

            Divider()
            HStack {
                Text("Date Active")
                    .font(.body)
                Spacer()
                DatePicker("", selection: $dateActive, displayedComponents: .date)
                    .labelsHidden()
                    .tint(.secondary)
            }
        }
    }
}

#Preview {
    CreateCommunityView(viewModel: CommunityViewModel())
}
