import SwiftUI

extension View {
    /// The app's two models, handed to a sheet's or a cover's content by its
    /// presenter rather than left to inheritance. The iPhone build running
    /// on a Mac with Apple silicon presented the first launch's tour without
    /// them, and its first read of `UsageModel` crashed the app a second
    /// after it opened (4.3.0, macOS 27.0; the iPhone and its simulator
    /// inherit them fine).
    func withAppModels(_ model: UsageModel, _ prefs: PreferencesModel) -> some View {
        environment(model)
            .environment(prefs)
    }
}
