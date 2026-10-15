import Foundation

/// The last page read in each matn, so the Library can show "Page N" and the
/// reader reopens where you left off. A per-device convenience, so it lives in
/// UserDefaults rather than with the flags.
enum ReadingPosition {
    static func key(_ matnID: String) -> String { "lastPage.\(matnID)" }

    static func lastPage(of matnID: String) -> Int? {
        let page = UserDefaults.standard.integer(forKey: key(matnID))
        return page > 0 ? page : nil
    }

    static func save(page: Int, of matnID: String) {
        UserDefaults.standard.set(page, forKey: key(matnID))
    }
}
