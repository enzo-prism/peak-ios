import SwiftUI

struct DocumentView: View {
    let title: String
    let resourceName: String
    let resourceExtension: String
    @State private var content = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                Text(.init(content))
                    .font(.custom("Avenir Next", size: 15, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle(title)
        .onAppear(perform: loadDocument)
    }

    private func loadDocument() {
        guard content.isEmpty else { return }
        let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Resources"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)

        if let url,
           let data = try? Data(contentsOf: url),
           let string = String(data: data, encoding: .utf8) {
            content = string
        } else {
            content = "Unable to load \(title)."
        }
    }
}
