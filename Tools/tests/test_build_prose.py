import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # Tools/

SRC = """% id = t
% title = عنوان
% titleLatin = t
% author = مؤلف
% subject = hadith
% kind = prose

@ 1 | الحديث الأول
عَنْ عُمَرَ قَالَ: «إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ»
= رواه البخاري ومسلم

@ 2 | الحديث الثاني
عَنْ أَبِي هُرَيْرَةَ
= رواه مسلم
"""

def main():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "t.txt"); out = os.path.join(d, "t.json")
        open(src, "w", encoding="utf-8").write(SRC)
        subprocess.run([sys.executable, os.path.join(ROOT, "build_matn.py"), src, out], check=True)
        doc = json.load(open(out, encoding="utf-8"))

    assert doc["kind"] == "prose", doc.get("kind")
    assert doc["baytCount"] == 2, doc["baytCount"]
    assert doc["pages"] == [] and doc["babs"] == []
    assert doc["pageCount"] == 0 and doc["baytsPerPage"] == 0
    hs = doc["hadiths"]; assert len(hs) == 2, len(hs)

    h1 = hs[0]
    assert h1["number"] == 1 and h1["title"] == "الحديث الأول"
    assert h1["takhrij"] == "رواه البخاري ومسلم"
    roles = {w["text"]: w["role"] for w in h1["body"]}
    assert roles["عَنْ"] == "isnad"
    assert roles.get("إِنَّمَا") == "matn"
    assert all("«" not in w["text"] and "»" not in w["text"] for w in h1["body"]), \
        [w["text"] for w in h1["body"]]
    matn_words = [w for w in h1["body"] if w["role"] == "matn"]
    assert matn_words and all(w["norm"] for w in matn_words)
    print("OK")

if __name__ == "__main__":
    main()
