import SwiftUI
import SwiftData

struct LibraryView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink {
                        QuiverView()
                    } label: {
                        Label("Quiver", systemImage: "wrench.and.screwdriver")
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SpotLibraryView()
                    } label: {
                        Label("Spots", systemImage: "mappin.and.ellipse")
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BuddyLibraryView()
                    } label: {
                        Label("Buddies", systemImage: "person.2")
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)
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
