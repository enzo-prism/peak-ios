import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button that starts a surf session without launching Peak.
///
/// `ControlWidget` is iOS 18+, so both the type and its registration in
/// `PeakWidgetBundle` are availability-gated; on iOS 17 the bundle simply ships
/// the two timeline widgets.
@available(iOS 18.0, *)
struct StartSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PeakStartSessionControl") {
            ControlWidgetButton(action: StartSessionIntent()) {
                Label("Start Surf", systemImage: "figure.surfing")
            }
        }
        .displayName("Start Surf Session")
        .description("Start a session timer the moment you paddle out.")
    }
}
