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
                VStack(alignment: .leading, spacing: 14) {
                    header.appear()

                    if let error = content.loadError {
                        ContentUnavailableView(
                            "Content didn't load",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else {
                        ForEach(Array(content.matns.enumerated()), id: \.element.id) { index, matn in
                            NavigationLink {
                                PageScreen(matn: matn)
                            } label: {
                                MatnCard(matn: matn, order: index + 1)
                            }
                            .buttonStyle(PressableStyle())
                            .appear(delay: 0.06 * Double(index + 1))
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

// A matn as a card with a green "spine" on the right (RTL), Arabic title, and
// bayt count. Reads like a volume on a shelf.
private struct MatnCard: View {
    let matn: Matn
    let order: Int

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 5, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(matn.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let full = matn.fullTitle, !full.isEmpty, full != matn.title {
                    Text(full)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(matn.baytCount) bayts")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }

            Spacer(minLength: 8)

            Text("\(order)")
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.ink.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

#Preview("Library") {
    RootView().environmentObject(ContentStore())
}
