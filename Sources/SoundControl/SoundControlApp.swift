import AppKit
import SwiftUI

@main
struct SoundControlApp: App {
    private static let hasLaunchedKey = "hasLaunchedBefore"

    @State private var model = AppModel()
    /// The window opens by itself only on the very first launch; afterwards the app lives in the menu bar.
    private let isFirstLaunch: Bool = {
        let defaults = UserDefaults.standard
        let first = !defaults.bool(forKey: SoundControlApp.hasLaunchedKey)
        defaults.set(true, forKey: SoundControlApp.hasLaunchedKey)
        return first
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: model.config.isListening ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Window("Sound Control", id: "main") {
            MainWindow().environment(model)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(isFirstLaunch ? .presented : .suppressed)
    }
}
