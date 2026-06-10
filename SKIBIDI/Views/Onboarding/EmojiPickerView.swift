import SwiftUI

/// A sheet that presents a grid of standard emoji to use as the profile avatar. Tapping one
/// stores it (as a plain `String`) via the binding and dismisses. Kept self-contained — no
/// service needed — since it's pure local selection state.
struct EmojiPickerView: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.adaptive(minimum: 52), spacing: 12), count: 1)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.emojis, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            dismiss()
                        } label: {
                            emojiCell(emoji)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Pick your vibe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// One emoji tile, highlighted when it's the current selection. Extracted into its own
    /// builder to keep the grid body cheap for the type-checker.
    private func emojiCell(_ emoji: String) -> some View {
        let isSelected = emoji == selectedEmoji
        return Text(emoji)
            .font(.system(size: 32))
            .frame(width: 52, height: 52)
            .background(Circle().fill(isSelected ? Color.skibidiBlue.opacity(0.18) : Color(.systemGray6)))
            .overlay(Circle().stroke(Color.skibidiBlue, lineWidth: isSelected ? 2 : 0))
    }

    /// A curated set of standard emoji characters covering faces, gestures, animals, food,
    /// activities, and symbols — enough variety to "express your vibe" without an exhaustive list.
    static let emojis: [String] = [
        "😀", "😄", "😁", "😆", "😅", "😂", "🙂", "😉", "😊", "😇",
        "🥰", "😍", "🤩", "😎", "🥳", "😜", "🤪", "😝", "🤗", "🤔",
        "🤨", "😐", "😶", "🙄", "😴", "😌", "😏", "😬", "🤓", "🧐",
        "😺", "🐶", "🐱", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮",
        "🐸", "🐵", "🦄", "🐝", "🦋", "🐢", "🐙", "🦖", "🐳", "🐬",
        "🌟", "⭐️", "✨", "⚡️", "🔥", "🌈", "🌸", "🌺", "🌻", "🌴",
        "🍀", "🍎", "🍕", "🍔", "🍦", "🍩", "☕️", "🍵", "🧋", "🍹",
        "⚽️", "🏀", "🎾", "🏄", "🚴", "🏃", "🧘", "🎸", "🎮", "🎧",
        "🚀", "✈️", "🗺", "🏝", "🏔", "🎯", "🎨", "📚", "💡", "💎",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "👻", "👽"
    ]
}

#Preview {
    EmojiPickerView(selectedEmoji: .constant("😎"))
}
