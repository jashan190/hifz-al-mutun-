# Shatibiyyah data: Suwaid edition (shatibiyyah_suwaid.json)

The full text of ash-Shatibiyyah (حرز الأماني, 1,173 bayts) exactly as printed in Dr. Ayman Rushdi Suwaid's edition (مكتبة ابن الجزري), transcribed page by page from the printed book. It replaces the me7me7/Shatibiya text, which follows a different edition.

## Layout rules of this edition
- 118 pages, 10 bayts per page (page 118 has 3). Page N holds bayts 10N-9 to 10N, so the page of any bayt is ceil(n / 10).
- Headings (bab and surah titles, the basmala on page 1, the closing line on page 118) sit between rows and don't use a bayt slot.
- Each row is one bayt: sadr on the right, ajuz on the left.
- The book prints only the last bayt number on each page, e.g. (١٠).

## Colours
| Colour | Meaning |
| --- | --- |
| black | the poet's words |
| blue | Quranic words. In the idgham and makharij chapters the book also prints letter lists and some technical terms in this colour |
| red | rumuz (code letters, often a single letter inside a word), the separating wāw, names of readers and transmitters, emphasis |

## File shape
```json
{
  "meta": { "title": "…", "edition": "…", "colors": {…}, "encoding": {…} },
  "pages": [
    { "page": 1, "items": [
      { "type": "heading", "markup": "…", "text": "…", "segments": [ … ] },
      { "type": "bayt", "n": 1,
        "sadr": { "markup": "…", "text": "…", "segments": [ … ], "words": [ … ] },
        "ajuz": { … },
        "review_notes": [ "…" ] }
    ]}
  ]
}
```

Each half-line (`sadr`, `ajuz`) has these fields:
- `markup`: the text with tags. `{q}…{/q}` marks blue, `{r}…{/r}` marks red, `{fn:N}` is a footnote marker, and `<GAP>` is a deliberate wide gap.
- `text`: plain text with full harakat and no tags. Use this for display when colour isn't needed.
- `segments`: the text split into runs, each with a colour: `{"text": "…", "color": "black|blue|red"}`. Footnote markers appear as `{"footnote": "٤٥"}`. Render the runs in order, right to left. A run can be a single letter in the middle of a word, so draw a word's runs as one joined string (an AttributedString in SwiftUI) or the Arabic letter-joining breaks.
- `words`: plain words, each with a `normalized` form for voice matching. The normalized form has harakat and marks stripped, alif forms unified, ى turned into ي, and ة into ه.

`review_notes` lists the 37 spots still open after proofreading: mostly a small nun that carries its own vowel, a mark that may be a misprint in the book, or a colour that's hard to tell apart. Show them in a debug view only.

Every page was transcribed from the scan, then proofread against it independently; the proofreading pass made 212 corrections.

## Encoding
- The text is Unicode NFC.
- Quranic words use Uthmani spelling: dagger alif U+0670, round sukun U+06DF on an extra alif, and maddah U+0653.
- Silah after a pronoun is U+06E5 (small waw) or U+06E6 (small ya).
- U+06E8 after a word marks the book's small nun, which shows a tanween joining the next word.
- Every sukun is the standard U+0652, including where the book uses the open Uthmani shape.
- Fonts: these marks render correctly in Amiri, Amiri Quran and KFGQPC Uthmanic Hafs. Test U+06E8, U+06DF and U+0670 on device.
