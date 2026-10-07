import Testing
@testable import HifzAlMutun

@Suite struct ArabicNormalizeTests {
    @Test func stripsHarakat() {
        #expect(ArabicNormalize.normalize("يَقُولُ") == "يقول")
    }
    @Test func foldsHamzaAlef() {
        #expect(ArabicNormalize.normalize("الْأَطْفَالِ") == "الاطفال")
        #expect(ArabicNormalize.normalize("آمَنُوا") == "امنوا")
        #expect(ArabicNormalize.normalize("ٱلرَّحْمَٰنِ") == "الرحمن")   // ٱ (alef wasla) → ا
    }
    @Test func foldsTaMarbutaAndAlefMaqsura() {
        #expect(ArabicNormalize.normalize("رَحْمَةِ") == "رحمه")
        #expect(ArabicNormalize.normalize("عَلَى") == "علي")
    }
    @Test func dropsPunctuationAndTatweel() {
        #expect(ArabicNormalize.normalize("(تُحْفَةِ") == "تحفه")
        #expect(ArabicNormalize.normalize("بِـ:") == "ب")
    }
    @Test func emptyForPunctuationOnly() {
        #expect(ArabicNormalize.normalize("،") == "")
    }
}
