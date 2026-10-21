import SwiftUI

// Library (home): the "Mutun" masthead, a search field, the Continue card, and
// the mutun grouped into collapsible subject sections of covers.
struct RootView: View {
    @EnvironmentObject private var content: ContentStore
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var collapsed: Set<Subject> = []
    @Namespace private var coverZoom

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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchBar

                    if let error = content.loadError {
                        ContentUnavailableView("Content didn't load",
                                               systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else {
                        if searchText.isEmpty, let (matn, page) = continueTarget {
                            NavigationLink { PageScreen(matn: matn) } label: {
                                ContinueCard(matn: matn, lastPage: page)
                            }
                            .buttonStyle(PressableStyle())
                        }

                        ForEach(visibleShelves) { shelf in
                            ShelfSection(shelf: shelf,
                                         isCollapsed: collapsed.contains(shelf.subject),
                                         zoom: coverZoom) {
                                withAnimation(.easeInOut(duration: 0.2)) { toggle(shelf.subject) }
                            }
                        }

                        if visibleShelves.isEmpty {
                            Text("لا توجد نتائج")
                                .font(DisplayFont.body(size: 16))
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
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

    // MARK: - Header + search

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mutun")
                .serifDisplay(.largeTitle)
                .foregroundStyle(Theme.ink)
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
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
            TextField("ابحث عن متن…", text: $searchText)
                .font(DisplayFont.body(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.ink.opacity(0.08)))
    }

    // MARK: - Data

    /// Shelves filtered by the search text (by matn title / full title / author /
    /// Latin title). Empty query → all shelves.
    private var visibleShelves: [Shelf] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return content.shelves }
        return content.shelves.compactMap { shelf in
            let hits = shelf.matns.filter { matnMatches($0, q) }
            return hits.isEmpty ? nil : Shelf(subject: shelf.subject, matns: hits)
        }
    }

    private func matnMatches(_ m: Matn, _ q: String) -> Bool {
        m.title.localizedCaseInsensitiveContains(q)
            || m.titleLatin.localizedCaseInsensitiveContains(q)
            || m.author.localizedCaseInsensitiveContains(q)
            || (m.fullTitle?.localizedCaseInsensitiveContains(q) ?? false)
    }

    private func toggle(_ s: Subject) {
        if collapsed.contains(s) { collapsed.remove(s) } else { collapsed.insert(s) }
    }

    /// The matn + last page for the Continue card: the most recently opened matn
    /// that has a saved page. nil if nothing has been opened yet.
    private var continueTarget: (Matn, Int)? {
        guard let id = ReadingPosition.mostRecentMatnID,
              let matn = content.matn(id: id),
              let page = ReadingPosition.lastPage(of: id) else { return nil }
        return (matn, page)
    }
}

/// One subject's collapsible section: a tappable subject header (with a chevron)
/// above a horizontally scrolling row of covers.
private struct ShelfSection: View {
    let shelf: Shelf
    let isCollapsed: Bool
    let zoom: Namespace.ID
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button(action: toggle) {
                HStack {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(shelf.subject.accent)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    Spacer()
                    Text(shelf.subject.arabicName)
                        .font(DisplayFont.body(size: 17).weight(.bold))
                        .foregroundStyle(shelf.subject.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if !isCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelf.matns) { matn in
                            NavigationLink {
                                PageScreen(matn: matn, startOnCover: true)
                                    .navigationTransition(.zoom(sourceID: matn.id, in: zoom))
                            } label: {
                                MatnCover(matn: matn, style: .shelf)
                                    .frame(width: 116)
                                    .matchedTransitionSource(id: matn.id, in: zoom)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .scrollClipDisabled()
            }
        }
    }
}

#Preview("Library") {
    RootView()
        .environmentObject(ContentStore())
        .environmentObject(FlagStore.inMemory())
}
