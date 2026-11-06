import AVFoundation
import Foundation
import Observation
#if canImport(Speech)
import Speech
#endif

struct VoiceLogFields {
    let transcript: String
    let spot: Spot?
    let gear: [Gear]
    let durationMinutes: Int?
    let rating: Int?
}

enum VoiceLogParser {
    private static let numbers = ["one": 1.0, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15,
        "twenty": 20, "thirty": 30, "forty": 40, "forty-five": 45, "sixty": 60, "ninety": 90]

    static func parse(_ transcript: String, spots: [Spot], gear: [Gear]) -> VoiceLogFields {
        let text = transcript.lowercased()
        if text.contains("not ") || text.contains("actually ") {
            return VoiceLogFields(transcript: transcript, spot: nil, gear: [], durationMinutes: nil, rating: nil)
        }
        let number = "(?:[0-9]+(?:\\.[0-9]+)?|" + numbers.keys.sorted().joined(separator: "|") + ")"
        let durations = captures("\\b(\(number))\\s*(hours?|hrs?|minutes?|mins?)\\b", in: text)
        var minutes = 0.0
        var hourCount = 0
        var minuteCount = 0
        for groups in durations where groups.count == 2 {
            guard let value = Double(groups[0]) ?? numbers[groups[0]] else { continue }
            if groups[1].hasPrefix("h") { hourCount += 1; minutes += value * 60 }
            else { minuteCount += 1; minutes += value }
        }
        let validDuration = !durations.isEmpty && hourCount <= 1 && minuteCount <= 1
            && minutes >= 5 && minutes <= Double(SurfSession.maxDurationMinutes)
        var ratings: [Double] = []
        for capture in captures("\\b(\(number))\\s*(?:stars?|out of five)\\b", in: text) {
            guard let word = capture.first, let value = Double(word) ?? numbers[word],
                  value.rounded() == value, value >= 1, value <= 5 else { continue }
            ratings.append(value)
        }
        let matchedSpots = spots.filter { containsName($0.name, in: text) }
        return VoiceLogFields(transcript: transcript, spot: matchedSpots.count == 1 ? matchedSpots[0] : nil,
                              gear: gear.filter { !$0.isArchived && containsName($0.name, in: text) },
                              durationMinutes: validDuration ? Int(minutes.rounded()) : nil,
                              rating: ratings.count == 1 ? Int(ratings[0]) : nil)
    }

    private static func containsName(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name.lowercased())
        return text.range(of: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])", options: .regularExpression) != nil
    }

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}

#if canImport(Speech)
@available(iOS 26.0, *)
@MainActor @Observable
final class VoiceLogRecorder {
    enum State: Equatable { case idle, recording, transcribing }
    var state: State = .idle
    var errorMessage: String?
    var transcript = ""
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var transcriptionTask: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var generation = 0
    private var requestingPermission = false
    private var ownsAudioSession = false

    nonisolated private static var recordingsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PeakVoiceRecordings", isDirectory: true)
    }

    /// A force quit skips view cleanup. Remove only Peak-owned temporary audio
    /// at the next process launch, before any recorder exists.
    nonisolated static func cleanAbandonedRecordings() {
        try? FileManager.default.removeItem(at: recordingsDirectory)
    }

    func start() async {
        guard state == .idle, !requestingPermission, !TestingDefaults.isRunningTests else { return }
        generation += 1
        let requestedGeneration = generation
        requestingPermission = true
        defer { if requestedGeneration == generation { requestingPermission = false } }
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard requestedGeneration == generation, !Task.isCancelled else { return }
        guard permitted else {
            errorMessage = "Microphone access is off. You can type your session below or enable access in Settings."
            return
        }
        guard !Task.isCancelled else { return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement)
            try audio.setActive(true)
            ownsAudioSession = true
            try FileManager.default.createDirectory(at: Self.recordingsDirectory, withIntermediateDirectories: true)
            let url = Self.recordingsDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            recordingURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            guard recorder.record(forDuration: 120) else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            errorMessage = nil
            state = .recording
        } catch {
            cancel()
            errorMessage = "Recording could not start. You can type your session below."
        }
    }

    func finish() {
        guard state == .recording, let url = recordingURL else { return }
        recorder?.stop(); recorder = nil
        deactivateAudioSession()
        state = .transcribing
        generation += 1
        let requestedGeneration = generation
        transcriptionTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                if requestedGeneration == generation {
                    recordingURL = nil
                    state = .idle
                    analyzer = nil
                }
            }
            do {
                guard SpeechTranscriber.isAvailable,
                      let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                    throw CocoaError(.featureUnsupported)
                }
                let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    // Only reached by the explicit Record/Finish action.
                    try await request.downloadAndInstall()
                }
                try Task.checkCancellation()
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                async let text: String = Self.collect(transcriber)
                let file = try AVAudioFile(forReading: url)
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                let result = try await text
                try Task.checkCancellation()
                guard requestedGeneration == generation else { return }
                transcript = result
                if result.trimmedNonEmpty == nil { errorMessage = "No speech was recognized. Try again or type below." }
            } catch is CancellationError {
                // Dismissal cancels without writing to the draft.
            } catch {
                guard requestedGeneration == generation, !Task.isCancelled else { return }
                errorMessage = "On-device transcription is unavailable. You can type your session below. No audio was sent to a server."
            }
        }
    }

    private static func collect(_ transcriber: SpeechTranscriber) async throws -> String {
        var result = ""
        for try await part in transcriber.results {
            result += String(part.text.characters) + " "
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deactivateAudioSession() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        generation += 1
        requestingPermission = false
        transcriptionTask?.cancel(); transcriptionTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        recorder?.stop(); recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        state = .idle
        deactivateAudioSession()
    }
}
#endif
