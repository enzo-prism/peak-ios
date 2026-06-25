import SwiftUI

/// Dedicated "Arrange media" sheet. Uses List + .onMove (the iOS-17-safe reorder primitive) over a
/// binding into the editor's draft array, so the new order is applied live and committed on Save.
struct MediaArrangeView: View {
    @Binding var items: [SessionMediaDraftItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            SessionMediaThumbnailView(
                                imageData: item.thumbnailData ?? item.photoData,
                                isVideo: item.kind == .video,
                                crop: item.cropRect
                            )
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(item.kind == .video ? "Video" : "Photo")
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)

                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        items.move(fromOffsets: source, toOffset: destination)
                    }
                }
                // Always-on grabbers so reordering is discoverable without an Edit toggle.
                .environment(\.editMode, .constant(.active))
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Arrange media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(Theme.textPrimary)
        }
    }
}
