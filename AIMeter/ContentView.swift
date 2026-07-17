import SwiftUI
import UsageKit

struct ContentView: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            DashboardView()
                .toolbar(.hidden, for: .automatic)
        }
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.scheduleNext()
            }
        }
        #endif
        .task {
            await model.refresh()
        }
    }
}

#Preview {
    ContentView()
        .environment(UsageModel())
        .environment(PreferencesModel())
}
