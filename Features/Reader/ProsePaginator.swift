import CoreGraphics
import UIKit

/// Flows hadith (semantic units) into page-sized fragments. Each hadith starts
/// a fresh page; a short one leaves its page partly empty, a long one spills
/// onto further pages. The takhrīj is rendered on the last fragment but is not
/// height-reserved — minor overflow is absorbed by the page's scroll view.
enum ProsePaginator {
    /// - Parameters:
    ///   - bodyHeight: vertical space available for body text on a page.
    ///   - headingHeight: space the title block takes on a hadith's first page.
    ///   - takhrijHeight: unused by the split (kept for callers/clarity).
    ///   - measureBody: wrapped height of the given words at the content width.
    /// - Returns: the pages (1…N) and a map hadith number → its first page.
    static func paginate(_ hadiths: [Hadith],
                         bodyHeight: CGFloat,
                         headingHeight: CGFloat,
                         takhrijHeight: CGFloat,
                         measureBody: ([ProseWord]) -> CGFloat)
    -> (pages: [MatnPage], firstPageOf: [Int: Int]) {
        var pages: [MatnPage] = []
        var firstPageOf: [Int: Int] = [:]
        var pageNo = 0

        for h in hadiths {
            firstPageOf[h.number] = pageNo + 1
            var rest = h.body
            var first = true
            repeat {
                pageNo += 1
                let cap = max(1, bodyHeight - (first ? headingHeight : 0))
                let n = max(1, fit(rest, cap: cap, measure: measureBody))  // always progress
                let slice = Array(rest.prefix(n))
                rest = Array(rest.dropFirst(n))
                let isLast = rest.isEmpty
                pages.append(MatnPage(page: pageNo, items: [.hadith(
                    HadithFragment(hadithNumber: h.number, title: h.title,
                                   words: slice, takhrij: h.takhrij,
                                   isFirst: first, isLast: isLast))]))
                first = false
            } while !rest.isEmpty
        }
        return (pages, firstPageOf)
    }

    /// Largest prefix count whose measured height is ≤ cap (at least 0; the
    /// caller guarantees ≥1 word is taken). Binary search over prefix length.
    private static func fit(_ words: [ProseWord], cap: CGFloat,
                            measure: ([ProseWord]) -> CGFloat) -> Int {
        if words.isEmpty { return 0 }
        if measure(words) <= cap { return words.count }
        var lo = 1, hi = words.count, best = 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if measure(Array(words.prefix(mid))) <= cap { best = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return best
    }

    // MARK: Default measurement (used by the reader, not by tests)

    /// Wrapped height of a run of words at `width`, using the page font.
    static func bodyHeight(_ words: [ProseWord], width: CGFloat, font: UIFont) -> CGFloat {
        let s = words.map(\.text).joined(separator: " ")
        guard !s.isEmpty, width > 0 else { return 0 }
        let rect = (s as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        return ceil(rect.height)
    }
}
