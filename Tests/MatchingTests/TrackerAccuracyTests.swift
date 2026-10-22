import Testing
import Foundation
@testable import HifzAlMutun

/// How the tracker copes with the way Whisper writes recitation (prefixes
/// joined to the next word, a word split in two), and how soon a mistake shows.
@Suite struct TrackerAccuracyTests {
    private func tracker(_ words: [String]) -> RecitationTracker {
        RecitationTracker(words: words, startIndex: 0)
    }

    // MARK: - Joined and split words

    @Test func aPrefixWrittenApartMatchesWhenHeardJoined() {
        // بِـ: بِسْمِ اللهِ — the text writes the ب apart; it's recited, and
        // transcribed, as ببسم.
        let t = tracker(["بدات", "ب", "بسم", "الله"])
        t.consume(.init(text: "بدأت ببسم الله", isFinal: true), at: 0)
        #expect(t.cursor == 4)
        #expect(t.outcomes == [0: .correct, 1: .correct, 2: .correct, 3: .correct])
    }

    @Test func aLongWordIsNeverAbsorbedIntoAJoin() {
        // "رب" + "قادر" joined doesn't stand for a skipped "عفو".
        let t = tracker(["يقول", "عفو", "رب", "قادر"])
        t.consume(.init(text: "يقول رب قادر", isFinal: true), at: 0)
        #expect(t.outcomes[1] == .skipped)
        #expect(t.outcomes[2] == .correct)
    }

    @Test func aWordHeardAsTwoTokensMatches() {
        let t = tracker(["قال", "مرتضاه", "هو"])
        t.consume(.init(text: "قال مر تضاه هو", isFinal: true), at: 0)
        #expect(t.cursor == 3)
        #expect(t.outcomes == [0: .correct, 1: .correct, 2: .correct])
    }

    // MARK: - Added words

    @Test func wordsTheTextDoesntHaveAreAdded() {
        // The Jazariyya's نبيه ومصطفاه said inside the Tuhfa's bayt.
        let t = tracker(["علي", "محمد", "واله"])
        t.consume(.init(text: "على نبيه ومصطفاه محمد وآله", isFinal: true), at: 0)
        #expect(t.added == [0: "نبيه ومصطفاه"])
        #expect(t.outcomes == [0: .correct, 1: .correct, 2: .correct])
        t.dismissAdded(after: 0)                         // "Not a mistake"
        #expect(t.added.isEmpty)
    }

    @Test func goingBackOverAWordIsNotAdding() {
        // The reciter repeats the last words before going on.
        let t = tracker(["يقول", "راجي", "رحمة", "الغفور"])
        t.consume(.init(text: "يقول راجي يقول راجي رحمة الغفور", isFinal: true), at: 0)
        #expect(t.added.isEmpty)
    }

    @Test func goingBackOverAWordWrittenSlightlyOffIsNotAdding() {
        // Whisper writes the repeated راجي as راجيه.
        let t = tracker(["يقول", "راجي", "رحمة", "الغفور"])
        t.consume(.init(text: "يقول راجي راجيه رحمة الغفور", isFinal: true), at: 0)
        #expect(t.added.isEmpty)
    }

    @Test func addedWordsInAGuessShowOnceTwoUpdatesAgree() {
        let t = tracker(["علي", "محمد", "واله"])
        t.consume(.init(text: "على نبيه ومصطفاه محمد", isFinal: false), at: 0)
        #expect(t.added.isEmpty)
        t.consume(.init(text: "على نبيه ومصطفاه محمد وآله", isFinal: false), at: 1)
        #expect(t.added == [0: "نبيه ومصطفاه"])
    }

    @Test func whispersAddedArticleIsNotAMistake() {
        // رَحْمَاناً رَحِيماً written by Whisper as in the basmala: رحمن الرحيم.
        let t = tracker(["تبارك", "رحمانا", "رحيما", "ومويلا"])
        t.consume(.init(text: "تبارك رحمن الرحيم وموئلا", isFinal: true), at: 0)
        #expect(t.outcomes[2] == .unsure)
        #expect(t.cursor == 4)
    }

    @Test func aDroppedLoneLetterIsUnsureNotRed() {
        // The recognizer often drops a lone letter; check it, don't fail it.
        let t = tracker(["بدات", "ب", "بسم", "الله"])
        t.consume(.init(text: "بدأت بسم الله", isFinal: true), at: 0)
        #expect(t.outcomes[1] == .unsure)
        #expect(t.outcomes[2] == .correct)
    }

    // MARK: - Showing mistakes from the guess

    @Test func aWrongWordShowsBeforeTheNextWord() {
        // "سعيد" said for "راجي": its letters part from the word's own, so it
        // is judged while still the last word heard, once two guesses agree.
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        t.consume(.init(text: "يقول سعيد", isFinal: false), at: 0)
        #expect(t.shownOutcomes[1] == nil)               // one guess: could still change
        t.consume(.init(text: "يقول سعيد", isFinal: false), at: 1)
        #expect(t.shownOutcomes[1] == .wrong(heard: "سعيد"))
        #expect(t.outcomes.isEmpty)                      // but not kept until final
    }

    @Test func goingBackOverAWordDoesntFlashTheNextRed() {
        // يقول said again before راجي: not راجي said wrong (CodeRabbit, #13).
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        for (k, text) in ["يقول يقول", "يقول يقول", "يقول يقول راجي"].enumerated() {
            t.consume(.init(text: text, isFinal: false), at: Double(k))
            #expect(t.shownOutcomes[1]?.isMistake != true)
        }
        // A wrong word after the repeat is still caught at once.
        let u = tracker(["يقول", "راجي", "عفو", "رب"])
        u.consume(.init(text: "يقول يقول سعيد", isFinal: false), at: 0)
        u.consume(.init(text: "يقول يقول سعيد", isFinal: false), at: 1)
        #expect(u.shownOutcomes[1] == .wrong(heard: "سعيد"))
    }

    @Test func aWordStillBeingSaidIsNotJudged() {
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        for text in ["يقول را", "يقول را", "يقول رجي", "يقول رجي"] {   // cut off; a letter misheard
            t.consume(.init(text: text, isFinal: false), at: 0)
            #expect(t.shownOutcomes[1]?.isMistake != true, "\(text)")
        }
    }

    @Test func aMistakeShowsOnceTwoGuessesAgree() {
        // A skip followed by a short word: only agreement shows it.
        let t = tracker(["يقول", "راجي", "في", "رب"])
        t.consume(.init(text: "يقول في", isFinal: false), at: 0)
        #expect(t.shownOutcomes[1] == nil)
        t.consume(.init(text: "يقول في", isFinal: false), at: 1)
        #expect(t.shownOutcomes[1] == .skipped)
        t.consume(.init(text: "يقول في رب", isFinal: true), at: 2)
        #expect(t.outcomes[1] == .skipped)
    }

    @Test func aMistakeFollowedByAWordShowsAtOnce() {
        let t = tracker(["يقول", "راجي", "عفو", "رب", "قادر"])
        t.consume(.init(text: "يقول عفو", isFinal: false), at: 0)
        #expect(t.shownOutcomes[1] == .skipped)          // عفو follows it, said exactly
        #expect(t.outcomes.isEmpty)
    }

    @Test func whatWasHeardIsKeptForANearMiss() {
        let t = tracker(["وثلثت", "ان", "الحمد"])
        t.consume(.init(text: "وثلست أن الحمد", isFinal: true), at: 0)
        #expect(t.outcomes[0] == .unsure)
        #expect(t.heard == [0: "وثلست"])
        #expect(mismatchedLetters(expected: "وثلثت", heard: "وثلست") == [3])
    }

    @Test func aGuessCorrectedBeforeItSettlesNeverShows() {
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        t.consume(.init(text: "يقول سعيد", isFinal: false), at: 0)
        t.consume(.init(text: "يقول راجي عفو", isFinal: false), at: 1)   // the recognizer fixed it
        #expect(t.shownOutcomes[1] == .correct || t.shownOutcomes[1] == nil)
        #expect(!t.shownOutcomes.values.contains { $0.isMistake })
    }

    @Test func notAMistakeOnAShownGuessSurvivesTheFinal() {
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        t.consume(.init(text: "يقول عفو", isFinal: false), at: 0)
        t.consume(.init(text: "يقول عفو رب", isFinal: false), at: 1)
        t.override(1, with: .correct)
        #expect(t.shownOutcomes[1] == .correct)
        t.consume(.init(text: "يقول عفو رب", isFinal: true), at: 2)
        #expect(t.outcomes[1] == .correct)
    }

    // MARK: - All three mutun

    @MainActor private static func allMatns() -> [Matn] {
        let store = ContentStore()
        store.load()
        return store.matns
    }

    /// Every word recited correctly, one final per hemistich: no mistakes —
    /// both token for token, and the way Whisper writes it (each lone letter
    /// joined to the word after it).
    @MainActor @Test(arguments: [false, true])
    func perfectRecitationOfEveryMatnHasNoMistakes(whisperStyle: Bool) {
        let matns = Self.allMatns()
        #expect(matns.count >= 3)   // at least the original three; more ship now
        for matn in matns {
            let index = RecitationIndex(matn: matn)
            let t = RecitationTracker(words: index.normalizedWords, startIndex: 0)
            var line: [String] = []
            var carry = ""
            for (i, word) in index.normalizedWords.enumerated() {
                if whisperStyle, word.count == 1 { carry += word; continue }
                line.append(carry + word)
                carry = ""
                let endOfHalf = i + 1 == index.refs.count
                    || index.refs[i + 1].half != index.refs[i].half
                    || index.refs[i + 1].bayt != index.refs[i].bayt
                if endOfHalf {
                    t.consume(.init(text: line.joined(separator: " "), isFinal: true), at: Double(i))
                    line = []
                }
            }
            let mistakes = t.outcomes.filter { $0.value.isMistake }
            #expect(mistakes.isEmpty, "\(matn.id): \(mistakes.count) false mistakes, e.g. \(mistakes.sorted { $0.key < $1.key }.prefix(5))")
            #expect(t.cursor == index.normalizedWords.count, "\(matn.id) stopped at \(t.cursor)")
        }
    }

    // MARK: - How soon a mistake shows

    /// Mistakes put into the real Whisper transcript of the clip, replayed the
    /// way the streamer delivers it. Counts the updates from the one that first
    /// holds the word after the mistake (the earliest it can be judged) until
    /// the mistake shows.
    @Test func mistakesShowWithTheNextWord() throws {
        let index = try WhisperTests.shatibiyya()
        var heard = WhisperTests.turboTranscript.split(separator: " ").map(String.init)
        // Skip "الناس" (index 24 of the transcript) and say "قلبه" for "كتابه".
        let skipped = try #require(heard.firstIndex(of: "الناس"))
        heard.remove(at: skipped)
        let swapped = try #require(heard.firstIndex(of: "كتابه"))
        heard[swapped] = "قلبه"

        let t = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        let targets = [
            (word: try #require(index.normalizedWords.firstIndex(of: "الناس")), heardAfter: skipped),
            (word: try #require(index.normalizedWords.firstIndex(of: "كتابه")), heardAfter: swapped + 1),
        ]
        var firstHeard: [Int: Int] = [:]   // target word → update holding the word after it
        var shownAt: [Int: Int] = [:]
        var keptAt: [Int: Int] = [:]
        var update = 0
        WhisperTests.stream(heard.joined(separator: " "), into: t) { wordsHeard in
            update += 1
            for target in targets {
                if firstHeard[target.word] == nil, wordsHeard > target.heardAfter { firstHeard[target.word] = update }
                if shownAt[target.word] == nil, t.shownOutcomes[target.word]?.isMistake == true { shownAt[target.word] = update }
                if keptAt[target.word] == nil, t.outcomes[target.word]?.isMistake == true { keptAt[target.word] = update }
            }
        }
        for target in targets {
            let heardAt = try #require(firstHeard[target.word])
            let shown = try #require(shownAt[target.word], "word \(target.word) never shown")
            let kept = try #require(keptAt[target.word])
            print("LATENCY word \(target.word): shown \(shown - heardAt) updates after the next word, finalized \(kept - heardAt)")
            #expect(shown - heardAt == 0)
            #expect(shown <= kept)
        }
    }
}

extension TrackerAccuracyTests {
    /// A red mark that shows and is then taken back still beeps: on a correct
    /// recitation streamed update by update, nothing shows red that the final
    /// judgment doesn't also call a mistake.
    @Test func aCorrectRecitationNeverFlashesRed() throws {
        let index = try WhisperTests.shatibiyya()
        let t = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        var everShown: Set<Int> = []
        WhisperTests.stream(WhisperTests.turboTranscript, into: t) { _ in
            for (i, o) in t.shownOutcomes where o.isMistake { everShown.insert(i) }
        }
        let kept = Set(t.outcomes.filter { $0.value.isMistake }.keys)
        print("FLASH shown \(everShown.sorted()) kept \(kept.sorted())")
        #expect(everShown.subtracting(kept).isEmpty, "flashed red: \(everShown.subtracting(kept).sorted().map { index.normalizedWords[$0] })")
    }
}

extension TrackerAccuracyTests {
    /// Every fragment WhisperKit delivered for the clip in one live run on the
    /// Simulator (passes about 10 s apart there): (seconds, final, text).
    static let liveRun: [(Double, Bool, String)] = [
        (37.1, false, "بجد"),
        (44.8, false, "بدأت ببسم الله في النظم أولا تبارك رحمن الرحيم ومعنى"),
        (54.8, true, "بدأت ببسم الله في النظم أولا تبارك رحمن الرحيم وموئلا وثنيت صلى الله ربي على الرضا"),
        (54.8, false, "محمد المهدى إلى الناس"),
        (65.1, true, "محمد المهدى إلى الناس مرسلا وعطرته ثم الصحابة ثم من تلاهم على الإحسان بالخير وبلاء"),
        (65.1, false, "وثجره"),
        (74.2, true, "وثلست أن الحمد لله دائما وما ليس مبدوءا به أجذم العلا"),
        (74.2, false, "وبعد فحبل الله فإنه"),
        (83.3, true, "وبعد فحبل الله فينا كتابه فجاهد به حبل العدى متحبلا"),
        (83.3, false, "وأخلق به إذ ليس يخلق"),
        (92.6, true, "وأخلق به إذ ليس يخلق جدة جديدا مواليه على الجد مقبلا"),
        (92.6, false, "وقارئه المرضي قر مثاله"),
        (102.5, true, "وقارئه المرضي قر مثاله كالترجح عليه مريحا وموكلا"),
        (102.5, false, "هو المرتباء من إذا كان أمة ويممه ظهرا"),
        (112.3, true, "هو المرتضى أمن إذا كان أمة ويممه ظل الرزانة قنقلا"),
        (112.3, false, "هو الحر إن كان الحري حواليا له بتحريه إلى أن تنبلا"),
        (122.3, true, "هو الحر إن كان الحري حواليا له بتحريه إلى أن تنبلا"),
        (122.3, false, "وإن كتاب الله أوثق شافع وأغنى غناء واهبا متفضلا"),
        (122.3, true, "وإن كتاب الله أوثق شافع وأغنى غناء واهبا متفضلا"),
    ]

    /// Replayed, the correct recitation never shows a word red that is then
    /// taken back.
    @Test func aLiveRunNeverFlashesRed() throws {
        let index = try WhisperTests.shatibiyya()
        let t = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        var everShown: Set<Int> = []
        for (time, isFinal, text) in Self.liveRun {
            t.consume(.init(text: text, isFinal: isFinal), at: time)
            for (i, o) in t.shownOutcomes where o.isMistake {
                if !everShown.contains(i) { print("LIVE \(time) \(isFinal) shows \(i) \(index.normalizedWords[i]) \(o)") }
                everShown.insert(i)
            }
        }
        let kept = Set(t.outcomes.filter { $0.value.isMistake }.keys)
        #expect(everShown.subtracting(kept).isEmpty, "flashed red: \(everShown.subtracting(kept).sorted().map { index.normalizedWords[$0] })")
    }
}

extension TrackerAccuracyTests {
    /// The end of the skips clip fed at phone pace (a pass a second): Whisper
    /// merged وأغنى غناء into وأغناء for one pass, which made غناء look skipped.
    @Test func aMergedWordDoesNotFlashASkip() throws {
        let index = try WhisperTests.shatibiyya()
        let t = RecitationTracker(words: index.normalizedWords, startIndex: try #require(index.firstWordIndex(ofBayt: 9)))
        let run: [(Double, Bool, String)] = [
            (70.0, true, "هو الحر إن كان الحري حواليا"),
            (70.1, false, "له بتحريه إلى أن تنبنا"),
            (71.2, true, "له بتحريه إلى أن تنبلا"),
            (71.2, false, "وإنك"),
            (72.2, false, "وإن كتاب الله"),
            (73.4, false, "وإن كتاب الله أوثق شاكرا"),
            (74.5, false, "وإن كتاب الله يوثق شافعين وصفحين"),
            (75.6, false, "وإن كتاب الله يوثق شافع وأغنى غنى"),
            (76.8, true, "وإن كتاب الله أوثق شافع"),
            (76.8, false, "وأغنى غناء واه"),
            (77.8, false, "وأغناء واهبا متفضل"),
            (78.8, false, "وأغنى غناء واهبا متفضلا"),
            (78.8, true, "وأغنى غناء واهبا متفضلا"),
        ]
        var everShown: Set<Int> = []
        for (time, isFinal, text) in run {
            t.consume(.init(text: text, isFinal: isFinal), at: time)
            for (i, o) in t.shownOutcomes where o.isMistake { everShown.insert(i) }
        }
        #expect(everShown.isEmpty, "shown red: \(everShown.sorted().map { index.normalizedWords[$0] })")
    }
}
