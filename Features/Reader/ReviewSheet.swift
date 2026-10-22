import SwiftUI

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
