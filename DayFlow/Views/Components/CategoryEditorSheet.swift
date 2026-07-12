import SwiftUI

/// Sheet for creating a custom category: a name, a color from the palette, and an
/// SF Symbol. Kept intentionally small — presets cover most needs, this is the
/// "add your own" escape hatch.
struct CategoryEditorSheet: View {
    /// (name, colorHex, symbol)
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = TimeCategory.customPalette.first ?? "#E64980"
    @State private var symbol = "tag.fill"

    private let symbols = [
        "tag.fill", "star.fill", "heart.fill", "cup.and.saucer.fill", "cart.fill",
        "airplane", "pawprint.fill", "paintbrush.fill", "music.note", "camera.fill",
        "phone.fill", "cross.case.fill", "leaf.fill", "flame.fill", "bed.double.fill",
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: 副業", text: $name)
                }
                Section("色") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(TimeCategory.customPalette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(height: 34)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == hex ? 3 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("アイコン") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(symbols, id: \.self) { s in
                            Image(systemName: s)
                                .font(.title3)
                                .frame(height: 34)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(symbol == s ? Color(hex: colorHex) : .secondary)
                                .background(symbol == s ? Color(hex: colorHex).opacity(0.15) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { symbol = s }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("カテゴリを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        onSave(name, colorHex, symbol)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
