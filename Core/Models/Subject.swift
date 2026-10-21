import SwiftUI

/// A branch of knowledge a matn belongs to. Drives the home "shelves" and each
/// cover's accent colour. `allCases` order is the shelf order on the home page.
/// Extensible: add a case here + a colour in `Theme.subjectAccent` and the home
/// page grows a new shelf with no other change.
enum Subject: String, CaseIterable, Codable, Hashable {
    case quran, hadith, seerah, aqeedah, arabic, fiqh

    /// Decode a raw id, falling back to `.quran` for anything unknown/missing,
    /// so older content without a subject keeps working.
    static func from(id: String?) -> Subject {
        guard let id, let s = Subject(rawValue: id) else { return .quran }
        return s
    }

    var arabicName: String {
        switch self {
        case .quran:   return "القرآن والتجويد"
        case .hadith:  return "الحديث"
        case .seerah:  return "السيرة"
        case .aqeedah: return "العقيدة"
        case .arabic:  return "العربية"
        case .fiqh:    return "الفقه"
        }
    }

    /// The subject's accent colour (loud, so a shelf reads at a glance).
    var accent: Color { Theme.subjectAccent(self) }
}
