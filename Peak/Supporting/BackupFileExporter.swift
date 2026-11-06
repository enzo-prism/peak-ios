import SwiftUI
import UIKit

/// Export the existing verified URL directly. SwiftUI's Transferable exporter
/// constructs an NSFileWrapper (and traps on a missing preferred name on iOS
/// 27.0); this system URL-based picker also avoids materializing large videos.
struct BackupFileExporter: UIViewControllerRepresentable {
    let url: URL
    let completion: (Result<URL, Error>) -> Void
    let cancellation: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: BackupFileExporter
        init(_ parent: BackupFileExporter) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.completion(.success(url)) }
            else { parent.completion(.failure(CocoaError(.fileWriteUnknown))) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.cancellation() }
    }
}
