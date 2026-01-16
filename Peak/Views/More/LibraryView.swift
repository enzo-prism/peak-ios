import SwiftUI
import SwiftData

struct LibraryView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                GlassContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        NavigationLink {
                            QuiverView()
                        } label: {
                            Label("Quiver", image: "surfboard")
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressFeedbackButtonStyle())

                        NavigationLink {
                            SpotLibraryView()
                        } label: {
                            Label("Spots", systemImage: "mappin.and.ellipse")
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressFeedbackButtonStyle())

                        NavigationLink {
                            BuddyLibraryView()
                        } label: {
                            Label("Buddies", systemImage: "person.2")
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressFeedbackButtonStyle())
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Library")
    }
}

#Preview {
    LibraryView()
        .modelContainer(PreviewData.container)
}
