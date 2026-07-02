import WidgetKit
import SwiftUI

@main
struct PeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        LastSessionWidget()
    }
}
