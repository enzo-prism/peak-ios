import SwiftUI
import SwiftData

struct MoreView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            LibraryView()
                        } label: {
                            Label("Library", systemImage: "books.vertical")
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
            .navigationTitle("More")
        }
        .tint(Theme.textPrimary)
    }
}

#Preview {
    MoreView()
        .modelContainer(PreviewData.container)
}
