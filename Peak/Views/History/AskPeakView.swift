import SwiftData
import SwiftUI

struct AskPeakView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear])) private var sessions: [SurfSession]
    @State private var question: String
    @State private var reviewFilters = HistoryFilters()
    @State private var showFilters = false
    @State private var confirmedFilterReview = false

    private let onClose: (() -> Void)?

    init(initialQuestion: String = "", onClose: (() -> Void)? = nil) {
        _question = State(initialValue: initialQuestion)
        self.onClose = onClose
    }

    @State private var answer: LogbookQuery.Answer?
    @State private var limit = 30
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var searchGeneration = 0
    private let examples = ["How many sessions this month?", "Which board did I use most?", "How many hours last week?", "Find my clean morning sessions"]

    var body: some View {
        List {
            Section {
                TextField("Ask about your logbook", text: $question, axis: .vertical)
                    .submitLabel(.search)
                    .onSubmit(ask)
                    .accessibilityIdentifier("ask.question")
                Button("Search My Logbook", systemImage: "magnifyingglass", action: ask)
                    .disabled(question.trimmedNonEmpty == nil)
                    .accessibilityIdentifier("ask.submit")
                if SemanticLogbookSearch.isAvailable, answer?.needsFilters == true {
                    Button("Find Related Memories On Device", systemImage: "sparkle.magnifyingglass") { semanticSearch() }
                        .disabled(question.trimmedNonEmpty == nil || isSearching)
                    if isSearching { ProgressView("Searching your private index…") }
                }
                Text("Private, read-only answers from your saved sessions. Counts and rankings are calculated directly from the matching records.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let answer {
                Section {
                    Text(answer.title).font(.headline).accessibilityIdentifier("ask.answer")
                    Text(answer.explanation).font(.subheadline)
                    if answer.needsFilters {
                        Button("Review History filters") {
                            presentFilterReview()
                        }
                        .frame(minHeight: 44)
                        Text("Recognized dates, spots and gear are prefilled. Review them before viewing History; other words have not been applied.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("View these criteria in History") {
                            presentFilterReview()
                        }
                        Text("Review the filters: note concepts and time-of-day words are only applied in this answer.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Source sessions") {
                    ForEach(Array(answer.sessions.prefix(limit))) { session in
                        Button {
                                PeakNavigationCoordinator.shared.handle(.session(id: SessionIntentQueries.identifier(for: session)))
                            } label: {
                            VStack(alignment: .leading) {
                                Text(session.spot?.name ?? "Surf session")
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if answer.sessions.count > limit {
                        Button("Show more sessions") { limit += 30 }
                    }
                    if answer.sessions.isEmpty { Text("No source sessions for this answer.").foregroundStyle(.secondary) }
                }
            } else {
                Section("Try a question") {
                    ForEach(examples, id: \.self) { example in
                        Button(example) { question = example; ask() }
                    }
                }
            }
        }
        .navigationTitle("Ask Peak")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    if let onClose { onClose() } else { dismiss() }
                }
                .accessibilityIdentifier("ask.close")
            }
        }
        .sheet(isPresented: $showFilters, onDismiss: {
            guard confirmedFilterReview else { return }
            confirmedFilterReview = false
            confirmHistoryHandoff()
        }) {
            HistoryFilterSheetView(
                filters: $reviewFilters,
                onConfirm: { confirmedFilterReview = true },
                showsCancel: true
            )
        }
        .onAppear { if !question.isEmpty && answer == nil { ask() } }
        .onDisappear { searchGeneration += 1; searchTask?.cancel(); isSearching = false }
        .onChange(of: SessionQueryStamp.make(sessions)) { _, _ in if answer != nil { ask() } }
    }

    private func presentFilterReview() {
        confirmedFilterReview = false
        reviewFilters = LogbookQuery.suggestedFilters(question, sessions: sessions)
        showFilters = true
    }

    private func confirmHistoryHandoff() {
        PeakNavigationCoordinator.shared.showHistory(filters: reviewFilters)
        dismiss()
    }

    private func ask() {
        searchGeneration += 1
        searchTask?.cancel()
        isSearching = false
        limit = 30
        answer = LogbookQuery.answer(question, sessions: sessions)
    }

    private func semanticSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        let query = question
        isSearching = true
        searchTask = Task {
            defer { if generation == searchGeneration { isSearching = false } }
            do {
                let ids = try await SemanticLogbookSearch.find(query)
                try Task.checkCancellation()
                guard generation == searchGeneration else { return }
                let live = SessionIntentQueries.sessions(withIdentifiers: ids, in: sessions)
                answer = LogbookQuery.Answer(title: live.isEmpty ? "No related memories found" : "Related memories",
                    explanation: "Relevance search returns examples from your on-device index and may omit records. Open the source sessions to check them. Use the exact question search for totals and board usage.", sessions: live)
            } catch is CancellationError {
                if !Task.isCancelled && generation == searchGeneration { answer = LogbookQuery.Answer(title: "Search took too long", explanation: "Try the exact question search or History filters.", sessions: []) }
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                answer = LogbookQuery.Answer(title: "Related search is unavailable", explanation: "Try the exact question search or History filters. Your logbook remains on this device.", sessions: [])
            }
        }
    }
}
