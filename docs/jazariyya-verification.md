# al-Muqaddimah al-Jazariyyah — transcription & verification notes

**Source of layout/ordering:** `source/Tuhfah + Jazariyya.pdf`, pages 20–30
(the poem; pages 16–19 are front matter — the isnad and Ibn al-Jazari's bio,
then the title page).

**Source of text:** transcribed by hand with full harakat into
`Tools/sources/jazariyya.txt`, checked bayt-by-bayt against the rendered PDF
pages. Same reason as Tuhfa: the PDF's text layer is not extractable.

**Layout:** 10 bayts per page (our layout), giving **11 pages** for 109 bayts.

## The bayt count: 107 vs 109

The PDF numbers **109** bayts, but bayts **107 and 109** are printed **in
brackets `[ ]`** with a footnote: «البيتان اللذان بين حاصرتين من زيادات بعض
العلماء، وليسا من أصل المنظومة» — they are scholarly additions, **not part of
the original matn**. Removing them leaves **107** bayts, which is what the matn
itself states (bayt 107: «أَبْيَاتُهَا قَافٌ وَزَايٌ فِي الْعَدَدْ» → ق=100, ز=7).

**Current choice:** all 109 are included (faithful to your PDF), brackets
stripped. The two additions are:
- **107** — «أَبْيَاتُهَا قَافٌ وَزَايٌ فِي الْعَدَدْ / مَنْ يُحْسِنِ التَّجْوِيدَ يَظْفَرْ بِالرَّشَدْ»
- **109** — «عَلَى النَّبِيِّ الْمُصْطَفَى وَآلِهِ / وَصَحْبِهِ وَتَابِعِي مِنْوَالِهِ»

**To use the traditional 107-bayt matn:** delete those two lines from
`Tools/sources/jazariyya.txt`, then rebuild + validate. Tell me and I'll do it.

## The سُكِّنَا → سَكَنَا change

Applied at your request (same as Tuhfa). One instance only:
- **Bayt 25** — PDF: «وَاوٌ وَيَاءٌ **سُكِّنَا** وَانْفَتَحَا» → now «وَاوٌ وَيَاءٌ **سَكَنَا** وَانْفَتَحَا».

Other similar-looking words were left alone (they're different words): bayt 39
«إِنْ سَكَنَا», bayt 41 «حَيْثُ سَكَنَتْ», bayt 50 «إِنْ سَكَنْ», bayt 63 «إِنْ تَسْكُنْ».

## Please double-check these chapters

The rasm (orthography) chapters are dense with quoted Qur'anic words and are the
most error-prone to transcribe by eye. Please check them closely against the PDF:
- **باب المقطوع والموصول** — bayts 79–93 (pages 27–29 of the PDF)
- **باب التاءات** — bayts 94–100 (page 29)

Any correction is a one-line edit in `Tools/sources/jazariyya.txt` followed by
`build_matn.py` + `validate_matn.py`.

## Babs (17)

| bab id          | title                                        | bayts   |
|-----------------|----------------------------------------------|---------|
| `muqaddima`     | المقدمة                                       | 1–8     |
| `makharij`      | باب مخارج الحروف                              | 9–19    |
| `sifat`         | باب صفات الحروف                              | 20–26   |
| `tajwid`        | باب التجويد                                   | 27–33   |
| `tarqiq`        | باب الترقيق وبعض التنبيهات                    | 34–40   |
| `raaat`         | باب الراءات                                   | 41–43   |
| `lamat`         | باب اللامات وتنبيهات متفرقة                   | 44–51   |
| `dad-zaa`       | باب الضاد والظاء                             | 52–61   |
| `mim-nun`       | باب الميم والنون المشددتين والميم الساكنة     | 62–64   |
| `nun-sakinah`   | باب أحكام النون الساكنة والتنوين              | 65–68   |
| `madd`          | باب المد                                      | 69–72   |
| `waqf-ibtida`   | باب معرفة الوقف والابتداء                     | 73–78   |
| `maqtu-mawsul`  | باب المقطوع والموصول                          | 79–93   |
| `taaat`         | باب التاءات                                   | 94–100  |
| `hamz-wasl`     | باب همز الوصل                                 | 101–103 |
| `waqf-awakhir`  | باب الوقف على أواخر الكلم                     | 104–105 |
| `khatimah`      | الخاتمة                                       | 106–109 |
