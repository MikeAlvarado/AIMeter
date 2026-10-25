import WidgetKit

/// Redraws everything that shows the App Group's figures outside the app:
/// every widget's timeline and, on iOS 18 and later, the Control Center
/// and Lock Screen control (`UsageControl`), which WidgetKit reloads on its
/// own call. One place, so a new surface is never left on old figures.
enum WidgetReload {
    static func all() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        #endif
    }
}
