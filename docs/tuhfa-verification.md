# Tuhfat al-Atfal — transcription & verification notes

**Source of layout/ordering:** `source/Tuhfah + Jazariyya.pdf`, pages 10–15
(the poem; pages 1–9 are front matter — title, three shaykhs' introductions,
khutbat al-ḥāja, al-Jamzūrī's bio, and the Tuhfa title page).

**Source of text:** transcribed by hand with full harakat into
`Tools/sources/tuhfa.txt`, then checked bayt-by-bayt against the rendered PDF
pages. The PDF's own text layer is **not extractable** (legacy encoding, no
Unicode map), so direct copy was not possible — this is the spec's intended
fallback: digital text + visual verification against your PDF.

**Totals:** 61 bayts, 10 babs. Confirmed by the PDF, which ends page 15 with
«تَمَّتِ المَنْظُومَةُ، والحَمْدُ لِلّٰهِ رَبِّ العَالَمِين».

## Layout

Your app uses **10 bayts per page** (7 pages for Tuhfa), *not* the PDF's
pagination. The PDF happened to use ~10/page too (pages 10–14 held bayts 1–50),
but its last page held 11 (51–61) because of a heading. Our layout is uniform:

| app page | bayts |
|----------|-------|
| 1 | 1–10 |
| 2 | 11–20 |
| 3 | 21–30 |
| 4 | 31–40 |
| 5 | 41–50 |
| 6 | 51–60 |
| 7 | 61 |

## Babs (chapter headings)

| bab id                   | title                                   | bayts |
|--------------------------|-----------------------------------------|-------|
| `muqaddima`              | المقدمة                                  | 1–5   |
| `nun-sakinah`            | أحكام النون الساكنة والتنوين             | 6–16  |
| `mim-nun-mushaddadatayn` | حكم الميم والنون المشدَّدتين             | 17    |
| `mim-sakinah`            | أحكام الميم الساكنة                       | 18–23 |
| `lam-al`                 | أحكام لام «أل» ولام الفعل                 | 24–29 |
| `mithlayn`               | المثلان والمتقاربان والمتجانسان          | 30–34 |
| `aqsam-madd`             | أقسام المدّ                              | 35–41 |
| `ahkam-madd`             | أحكام المدّ                              | 42–47 |
| `aqsam-madd-lazim`       | أقسام المدّ اللازم                        | 48–57 |
| `khatimah`               | الخاتمة                                   | 58–61 |

## Wording notes (for your review)

The transcription matches the PDF. A few conventions to flag, none of them
changes to wording — just how they're stored:

1. **Mnemonic/quoted words** (e.g. `يَرْمَلُونَ`, `يَنْمُو`, `دُنْيَا`,
   `صِنْوَانٍ`, `ابْغِ حَجَّكَ وَخَفْ عَقِيمَهُ`, `كَمْ عَسَلْ نَقَصْ`) appear in
   **red and inside parentheses** in the PDF. The text is stored without the
   parentheses so each word normalizes cleanly for matching; colour/emphasis is
   a display concern we can add in the Reader (Phase 1) if you want it.
2. Harakat follow the PDF's vocalization (e.g. the rhyme-end sukūn forms like
   `غُنَّهْ`, `شَفْوِيَّهْ`, `قَمْرِيَّهْ`).

Please skim the Reader in Phase 1 against your PDF; if you spot any letter or
harakat you'd set differently, it's a one-line edit in `Tools/sources/tuhfa.txt`
followed by `build_matn.py` + `validate_matn.py`.
