import SwiftUI
import SwiftData
import UIKit

@main
struct HifzApp: App {
    @StateObject private var content = ContentStore()
    /// The user's flags, stored on device with SwiftData.
    @StateObject private var flags = FlagStore(container: HifzApp.makeContainer())
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    init() {
        PageFont.registerBundledFonts()   // bundle Amiri for the page

        // iOS doesn't tint a segmented control's selected segment with the app
        // accent automatically, so set it to the app's charcoal brand explicitly.
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(Theme.brand)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: WordFlag.self)
        } catch {
            // A store that can't open must not stop the app from reading.
            return try! ModelContainer(for: WordFlag.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(content)
                .environmentObject(flags)
                // The mutun are Arabic; lay the UI out right-to-left.
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Theme.brand)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
