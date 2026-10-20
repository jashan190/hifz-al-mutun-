import Foundation

/// Classic two-row Levenshtein distance over Characters.
func levenshtein(_ a: String, _ b: String) -> Int {
    let s = Array(a), t = Array(b)
    if s.isEmpty { return t.count }
    if t.isEmpty { return s.count }
    var prev = Array(0...t.count)
    var curr = [Int](repeating: 0, count: t.count + 1)
    for i in 1...s.count {
        curr[0] = i
        for j in 1...t.count {
            let cost = s[i - 1] == t[j - 1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[t.count]
}

/// The letters of `expected` (Character offsets) that `heard` doesn't match,
/// by the cheapest alignment: substituted or missing letters, and for a letter
/// heard extra, the expected letter it was heard next to.
func mismatchedLetters(expected: String, heard: String) -> Set<Int> {
    let s = Array(expected), t = Array(heard)
    if s.isEmpty { return [] }
    if t.isEmpty { return Set(s.indices) }
    // Full table, so the alignment can be traced back.
    var d = [[Int]](repeating: [Int](repeating: 0, count: t.count + 1), count: s.count + 1)
    for i in 0...s.count { d[i][0] = i }
    for j in 0...t.count { d[0][j] = j }
    for i in 1...s.count {
        for j in 1...t.count {
            let cost = s[i - 1] == t[j - 1] ? 0 : 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
        }
    }
    var out: Set<Int> = []
    var i = s.count, j = t.count
    while i > 0 || j > 0 {
        if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + (s[i - 1] == t[j - 1] ? 0 : 1) {
            if s[i - 1] != t[j - 1] { out.insert(i - 1) }
            i -= 1; j -= 1
        } else if i > 0, d[i][j] == d[i - 1][j] + 1 {
            out.insert(i - 1)                    // not heard
            i -= 1
        } else {
            out.insert(max(0, i - 1))            // heard extra, next to this letter
            j -= 1
        }
    }
    return out
}
