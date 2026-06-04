import SwiftUI
struct CreateCommunityView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var communityName = ""
    @State private var communityType: CommunityType = .detail
    @State private var dateActive = Date()
    @State private var memberCount = 0
    @State private var isLocationSharing = true
    @State private var isHealthSharing = false
    @State private var isFitnessSharing = false
    
    private var canCreate: Bool {
        !communityName.trimmingCharacters(in: .whitespaces).isEmpty
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

                    togglesSection
                    


                    
                    Text("Choose the content you want to share to fit. It's your choice.")
                        .font(.caption)
                        .foregroundStyle(.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.createCommunity(
                            name: communityName,
                            type: communityType,
                            memberCount: memberCount,
                            locationSharing: isLocationSharing,
                            healthSharing: isHealthSharing,
                            fitnessSharing: isFitnessSharing,
                            dateActive: dateActive
                        )
                        dismiss()
                    } label: {
                        Text("Create")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(canCreate ? Color.blue : Color(.systemGray4))
                            .clipShape(Capsule())
                    }
                    .disabled(!canCreate)
                }
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
            
            Divider()
            
            HStack {
                Text("\(memberCount) Members")
                    .font(.body)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button {
                        if memberCount > 0 { memberCount -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .foregroundStyle(.primary)
                    
                    Button {
                        memberCount += 1
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }
    private var togglesSection: some View {
        VStack(spacing: 16) {
            toggleRow(title: "Location", isOn: $isLocationSharing)
            Divider()
            toggleRow(title: "Health", isOn: $isHealthSharing)
            Divider()
            toggleRow(title: "Fitness", isOn: $isFitnessSharing)
        }
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.body)
        }
        .tint(.blue)
    }
}

#Preview {
    CreateCommunityView(viewModel: CommunityViewModel())
}
