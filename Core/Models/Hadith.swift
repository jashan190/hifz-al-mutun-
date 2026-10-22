import Foundation

/// Whether a matn is verse (sadr/ajuz bayts) or flowing prose (hadith).
enum MatnKind: String, Decodable, Hashable { case poem, prose }

/// The part of a hadith a word belongs to, which decides its colour.
/// Takhrīj is not a role — it is a separate footer string on `Hadith`.
enum ProseRole: String, Decodable, Hashable {
    case isnad   // chain + narration frame — normal ink
    case matn    // the Prophet's words (the «…» spans) — subject colour
}

/// A word in a hadith body: display text, normalised form (for future voice/
/// memorize matching), and the role that decides its colour.
struct ProseWord: Decodable, Hashable {
    let text: String
    let normalized: String
    let role: ProseRole

    enum CodingKeys: String, CodingKey { case text, normalized = "norm", role }
}

/// One hadith: its number, heading, the body as an ordered word sequence
/// (isnād + matn interleaved, each word role-tagged) and the takhrīj line.
struct Hadith: Decodable, Hashable, Identifiable {
    let number: Int
    let title: String        // e.g. "الحديث الأول"
    let body: [ProseWord]
    let takhrij: String      // e.g. "رواه البخاري ومسلم"
    var id: Int { number }
}

/// A page-sized slice of one hadith, produced by `ProsePaginator` at runtime
/// (never decoded). `isFirst` → render the heading above it; `isLast` → render
/// the takhrīj below it; `words` is the slice shown on this page.
struct HadithFragment: Hashable {
    let hadithNumber: Int
    let title: String
    let words: [ProseWord]
    let takhrij: String
    let isFirst: Bool
    let isLast: Bool
}
