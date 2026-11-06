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
            self?.publishHeight(0)
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
            publishHeight(0)
            return
        }
        // Measure against the app's own window, not the display: in iPad Split
        // View / Slide Over / Stage Manager the window doesn't fill the screen,
        // so `UIScreen.main.maxY - frame.minY` (the deprecated old math here)
        // produced a phantom inset far taller than the real overlap.
        guard let window = Self.activeKeyWindow else {
            publishHeight(0)
            return
        }
        let keyboardFrame = window.convert(frame, from: window.screen.coordinateSpace)
        let overlap = window.bounds.intersection(keyboardFrame).height
        publishHeight(overlap.isFinite ? max(0, overlap) : 0)
    }

    private func publishHeight(_ value: CGFloat) {
        // UIKit can emit keyboard notifications while SwiftUI removes the
        // editor. Publish on the next main turn, outside that view update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.height != value else { return }
            self.height = value
        }
    }

    private static var activeKeyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.keyWindow
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
