import Foundation

/// Offline chronological evaluation. Each observation sees strictly older
/// history, never itself, same-time observations or future records. This reports
/// historical similarity accuracy, not archived-forecast or ocean validation.
nonisolated enum WindowValidation {
    struct Observation: Equatable, Sendable {
        let date: Date
        let trainingCount: Int
        let actualRating: Double
        let predictedRating: Double?
        let baselineRating: Double
    }
    struct Report: Sendable {
        let observations: [Observation]
        var acceptedCount: Int { observations.filter { $0.predictedRating != nil }.count }
        var abstainedCount: Int { observations.count - acceptedCount }
        var meanAbsoluteError: Double? {
            let errors = observations.compactMap { row in row.predictedRating.map { abs($0 - row.actualRating) } }
            return errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count)
        }
        /// Compare on the SAME accepted rows; abstention must not flatter one model.
        var matchedBaselineError: Double? {
            let rows = observations.filter { $0.predictedRating != nil }
            return rows.isEmpty ? nil : rows.reduce(0) { $0 + abs($1.baselineRating - $1.actualRating) } / Double(rows.count)
        }
    }
    static func evaluate(history: [RatedSession], minimumTraining: Int = 8, tuning: Tuning = Tuning()) -> Report {
        let ordered = history.filter { (1...5).contains($0.rating) }.sorted { $0.date < $1.date }
        var results: [Observation] = []
        for current in ordered {
            let older = ordered.filter { $0.date < current.date }
            guard older.count >= max(1, minimumTraining) else { continue }
            let hour = ForecastHour(date: current.date, conditions: current.conditions)
            let scored = WindowScorer.scoreHours(forecast: [hour], history: older, tuning: tuning).first
            let prediction = scored.flatMap { $0.confidence >= tuning.minConfidence ? $0.predictedRating : nil }
            results.append(Observation(date: current.date, trainingCount: older.count,
                                       actualRating: Double(current.rating), predictedRating: prediction,
                                       baselineRating: older.reduce(0) { $0 + Double($1.rating) } / Double(older.count)))
        }
        return Report(observations: results)
    }
}
