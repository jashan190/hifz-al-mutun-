import SwiftUI
import UIKit

@main
struct HifzApp: App {
    @StateObject private var content = ContentStore()
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    init() {
        PageFont.registerBundledFonts()   // bundle Amiri for the page

        // iOS doesn't tint a segmented control's selected segment with the app
        // accent automatically, so set it to Madinah green explicitly.
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(Theme.accent)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(content)
                // The mutun are Arabic; lay the UI out right-to-left.
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
