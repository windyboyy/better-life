#!/usr/bin/env python3
"""Extract IELTS-tagged words from the ECDICT SQLite database into a compact JSON
for the app to bundle and seed offline. Data never needs to be fully read into
anything heavy: this streams rows from sqlite and writes JSON to disk.

Usage: python3 extract_ielts.py <ecdict.db> <out.json>
"""
import sys
import json
import sqlite3


def clean(s):
    return (s or "").strip()


def main():
    if len(sys.argv) != 3:
        print("usage: extract_ielts.py <ecdict.db> <out.json>", file=sys.stderr)
        sys.exit(2)

    db_path, out_path = sys.argv[1], sys.argv[2]
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row

    # tag is space-separated; match the 'ielts' token. Order by frequency so the
    # most common words come first (good default study order).
    rows = con.execute(
        """
        SELECT word, phonetic, translation, pos, collins, oxford, tag, bnc, frq
        FROM stardict
        WHERE tag LIKE '%ielts%'
        ORDER BY (CASE WHEN frq > 0 THEN frq ELSE 999999 END) ASC
        """
    )

    out = []
    for r in rows:
        word = clean(r["word"])
        if not word:
            continue
        out.append({
            "word": word,
            "phonetic": clean(r["phonetic"]),
            "translation": clean(r["translation"]),  # Chinese gloss, may be multiline
            "pos": clean(r["pos"]),                   # part-of-speech ratios e.g. "n:50/v:50"
            "collins": r["collins"] or 0,             # Collins star rating 0-5
            "oxford": r["oxford"] or 0,               # in Oxford 3000 (0/1)
            "bnc": r["bnc"] or 0,                     # BNC frequency rank
            "frq": r["frq"] or 0,                     # contemporary corpus rank
        })

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    print(f"wrote {len(out)} IELTS words -> {out_path}")


if __name__ == "__main__":
    main()
