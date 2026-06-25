import Combine
import SwiftUI
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.updateHeight(from: notification)
        })
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.height = 0
        })
    }

    deinit {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    private func updateHeight(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            height = 0
            return
        }
        let screen = UIScreen.main.bounds
        let overlap = max(0, screen.maxY - frame.minY)
        height = overlap
    }
}

private struct KeyboardSafeAreaInset: ViewModifier {
    @StateObject private var observer = KeyboardObserver()

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: observer.height)
        }
    }
}

extension View {
    func keyboardSafeAreaInset() -> some View {
        modifier(KeyboardSafeAreaInset())
    }
}
