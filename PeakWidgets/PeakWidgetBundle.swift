import WidgetKit
import SwiftUI

@main
struct PeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        LastSessionWidget()
        PeakSessionLiveActivity()
        // Control Center controls arrived in iOS 18; the rest of the bundle
        // still ships to Peak's iOS 17 deployment target.
        if #available(iOS 18.0, *) {
            StartSessionControl()
        }
    }
}
