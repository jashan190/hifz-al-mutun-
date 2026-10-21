import SwiftUI

// Library (home). The mutun in study order, from the content JSON. A calm,
// manuscript-styled index rather than a stock list. Tapping one opens it at the
// first page.
struct RootView: View {
    @EnvironmentObject private var content: ContentStore
    @State private var showSettings = false

    // Debug-only deep link: launch with `-openReaderMatn <id>` to open a matn
    // directly (used for deterministic screenshots). Harmless without the arg.
    private var deepLinkMatn: Matn? {
        guard let id = UserDefaults.standard.string(forKey: "openReaderMatn") else { return nil }
        return content.matns.first { $0.id == id }
    }

    var body: some View {
        if let matn = deepLinkMatn {
            NavigationStack { PageScreen(matn: matn) }
        } else {
            library
        }
    }

    private var library: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header.appear()

                    if let error = content.loadError {
                        ContentUnavailableView("Content didn't load",
                                               systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else {
                        if let (matn, page) = continueTarget {
                            NavigationLink { PageScreen(matn: matn) } label: {
                                ContinueCard(matn: matn, lastPage: page)
                            }
                            .buttonStyle(PressableStyle())
                            .appear()
                        }
                        ForEach(Array(content.shelves.enumerated()), id: \.element.id) { i, shelf in
                            ShelfRow(shelf: shelf)
                                .appear(delay: 0.06 * Double(i + 1))
                        }
                    }
                }
                .padding(Theme.margin)
                .padding(.top, 8)
            }
            .background(Theme.page.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsSheet() }
        }
    }

    /// The matn + last page for the Continue card: the most recently opened
    /// matn that has a saved page. nil if nothing has been opened yet.
    private var continueTarget: (Matn, Int)? {
        guard let id = ReadingPosition.mostRecentMatnID,
              let matn = content.matn(id: id),
              let page = ReadingPosition.lastPage(of: id) else { return nil }
        return (matn, page)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("المتون")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text("Mutun")
                    .serifDisplay(.largeTitle)
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.accent.opacity(0.1)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.bottom, 4)
    }
}

/// One subject's shelf: a header and a horizontally scrolling row of covers.
private struct ShelfRow: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text(shelf.subject.arabicName)
                .font(DisplayFont.body(size: 17).weight(.bold))
                .foregroundStyle(shelf.subject.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.matns) { matn in
                        NavigationLink { PageScreen(matn: matn) } label: {
                            MatnCover(matn: matn, style: .shelf)
                                .frame(width: 116)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 2)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

#Preview("Library") {
    RootView()
        .environmentObject(ContentStore())
        .environmentObject(FlagStore.inMemory())
}
