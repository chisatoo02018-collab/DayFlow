import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String
    let count: Int

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)

            Spacer()

            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }
}
