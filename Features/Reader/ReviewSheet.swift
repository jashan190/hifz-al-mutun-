import SwiftUI

/// The cumulative review for one matn: every flagged word, in reading order,
/// read live from the FlagStore. Rows for the current sitting show "you said X".
struct ReviewSheet: View {
    let matn: Matn
    /// Ephemeral annotations from the current sitting (empty when none).
    var annotations: [FlagKey: ReviewSummary.Mistake] = [:]
    let onSelect: (FlagKey) -> Void
    let onRemove: (FlagKey) -> Void
    let reviewAgain: () -> Void
    let done: () -> Void

    @EnvironmentObject private var flagStore: FlagStore

    private var items: [ReviewItem] {
        ReviewItems.resolve(matn: matn, flags: flagStore.flags[matn.id] ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("المراجعة")
                        .font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                        .environment(\.layoutDirection, .rightToLeft)
                    Text(items.isEmpty ? "No flagged words yet"
                         : "\(Numerals.eastern(items.count)) flagged \(items.count == 1 ? "word" : "words")")
                        .font(.subheadline).foregroundStyle(Theme.ink.opacity(0.7))
                }
                Spacer()
                Button { done() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.ink.opacity(0.06)))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, Theme.margin).padding(.top, Theme.margin).padding(.bottom, 10)

            if items.isEmpty {
                Spacer()
                Text("Flag a word (long-press) or recite to collect your trouble spots here.")
                    .font(.subheadline).foregroundStyle(Theme.ink.opacity(0.6))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        MistakeCard(location: item.location, word: item.word,
                                    mistake: annotations[item.key]) { onSelect(item.key) }
                            .listRowInsets(EdgeInsets(top: 2, leading: Theme.margin, bottom: 2, trailing: Theme.margin))
                            .listRowSeparator(.visible)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { onRemove(item.key) } label: {
                                    Label("Remove", systemImage: "flag.slash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: reviewAgain) { Text("Review again").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .tint(matn.subject.accent)
            .padding(Theme.margin)
        }
        .background(Theme.page.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// One review row: location + the flagged word. When a fresh sitting's mistake
/// is supplied, it enriches the row with the differing letters marked and a
/// "you said X" / "skipped" / "added" line.
struct MistakeCard: View {
    let location: String
    let word: String
    /// The current sitting's mistake at this position, if any (ephemeral detail).
    var mistake: ReviewSummary.Mistake? = nil
    let onSelect: () -> Void

    /// The word with its differing letters (vs what was heard) in error-red.
    private var wordText: AttributedString {
        var text = AttributedString(word)
        text.foregroundColor = Theme.ink
        guard let m = mistake, let heard = m.heard, !m.added else { return text }
        let scalars = word.unicodeScalars
        for r in LetterEmphasis.ranges(written: word, heard: heard) {
            let lo = scalars.index(scalars.startIndex, offsetBy: r.lowerBound)
            let hi = scalars.index(scalars.startIndex, offsetBy: r.upperBound)
            guard let a = AttributedString.Index(lo, within: text),
                  let b = AttributedString.Index(hi, within: text) else { continue }
            text[a..<b].foregroundColor = Theme.error
        }
        return text
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(location)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(wordText)
                        .font(PageFont.font(size: 26))
                    if let m = mistake {
                        HStack(spacing: 5) {
                            Text(m.added ? "you added" : m.heard == nil ? "skipped" : "you said")
                                .font(.footnote).foregroundStyle(Theme.error)
                            if let heard = m.heard {
                                Text(heard).font(PageFont.font(size: 20)).foregroundStyle(Theme.error)
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink.opacity(0.35))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mistake.map {
            $0.added ? "\(location). After \(word), you added \($0.heard ?? "")."
                     : "\(location). Should be \(word)." + ($0.heard.map { " You said \($0)." } ?? " You skipped it.")
        } ?? "\(location). Flagged word \(word).")
        .accessibilityHint("Shows this word on the page")
    }
}
