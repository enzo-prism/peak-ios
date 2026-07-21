import SwiftUI
import SwiftData

struct MoreView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    GlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())

                            NavigationLink {
                                YearInReviewView()
                            } label: {
                                Label("Year in Review", systemImage: "sparkles")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())

                            NavigationLink {
                                SpotLibraryView()
                            } label: {
                                Label("Spots", systemImage: "mappin.and.ellipse")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())

                            NavigationLink {
                                BuddyLibraryView()
                            } label: {
                                Label("Buddies", systemImage: "person.2")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                        }
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
