#!/usr/bin/env python3
"""Run:  python3 ios/tools/build_support.py [--archive PATH]

Builds showroom and help data for the Salini app from the 2026-10-06 site archive.

dealers.json → CatalogMedia/dealers.json
  * phones are parsed from the visible label, never from the archived tel: URL (28+ URLs glue
    several numbers together; Belarusian numbers were stored with a wrong +7 prefix);
  * every number becomes its own valid tel: link, extensions are kept as separate text;
  * missing coordinates stay null (the dealer is listed without a map pin);
  * the per-dealer "exposition" list is kept as published; source_pages are ignored because they
    only say where the dealer widget appeared, not what the dealer has in stock.
main-faq.txt → CatalogMedia/help.json (sections and questions as published).
"""
import argparse, hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = Path("/Users/daviddoronin/Documents/ChatGPT/Salini/research/site-audit-2026-10-06")  # default, as build_catalog.py; override with --archive
OUT = ROOT / "ios/Salini/CatalogMedia"


# Full number length (digits, with country code) by prefix; Russia also appears as 8….
LENGTHS = [("375", 12), ("374", 11), ("996", 12), ("971", 12), ("966", 12), ("7", 11), ("8", 11)]


def phones(label: str):
    """Split a label like '+7 (495) 203-44-11 +7 (965) 211-88-88 доб. 2' into numbers."""
    main, ext = label.split("доб", 1) if "доб" in label else (label, "")
    ext = re.sub(r"[^\d,; ]", "", ext).strip(" ,;")
    out, digits = [], ""
    expected = None
    for ch in main:
        if ch.isdigit():
            if not digits:
                expected = None
            digits += ch
            if expected is None and len(digits) >= 3:
                expected = next((n for code, n in LENGTHS if digits.startswith(code)), 11)
            if expected and len(digits) == expected:
                out.append(digits)
                digits = ""
        elif ch == "+" and digits:
            digits = ""  # a dangling fragment before a new number is dropped
    result = []
    for d in out:
        if len(d) == 11 and d[0] == "8":
            d = "7" + d[1:]
        code = next((c for c, n in LENGTHS if d.startswith(c) and len(d) == n), None)
        if code is None:
            continue
        if code == "7":
            display = f"+7 ({d[1:4]}) {d[4:7]}-{d[7:9]}-{d[9:11]}"
        elif code == "375":
            display = f"+375 ({d[3:5]}) {d[5:8]}-{d[8:10]}-{d[10:12]}"
        else:
            rest = d[len(code):]
            display = f"+{code} {rest[:2]} {rest[2:5]} {rest[5:]}"
        result.append({"display": display, "tel": "tel:+" + d})
    if ext and result:
        result[-1]["extension"] = ext.replace(";", ",").replace(" ", "")
    return result


def hours(text: str):
    m = re.search(r"Показать телефон\s+(.*?)\s+(?:сайт|Есть экспозиция|Нет экспозиции|Официальный|Салон|$)", text)
    if not m:
        return None
    h = re.sub(r"\s+", " ", m.group(1)).strip()
    return h.replace("ПН. - ПТ.", "Пн–Пт").replace("СБ.", "· Сб").replace("ВСК.", "· Вс") or None


def dealers(catalog_urls):
    raw = json.load(open(ARCHIVE / "inventory/dealers.json"))
    out, fixed = [], 0
    for d in raw:
        contacts = d.get("contacts") or []
        nums, site = [], None
        for c in contacts:
            if c["url"].startswith("tel:"):
                parsed = phones(c["label"])
                if len(parsed) != 1 or parsed[0]["tel"] != c["url"]:
                    fixed += 1
                nums += parsed
            elif c["url"].startswith("http"):
                site = c["url"]
        lat, lon = d.get("latitude"), d.get("longitude")
        text = d.get("text", "")
        expo = []
        for e in d.get("exposition") or []:
            link = e.get("link", "")
            expo.append({"name": e.get("name", "").strip(), "productId": catalog_urls.get(link.rstrip("/") + "/")})
        # 14 archived dealers have no id: a stable local id from name + address keeps them.
        source_id = str(d["id"]) if d.get("id") is not None else None
        local = "local-" + hashlib.sha1(f"{d['name'].strip()}|{d['address'].strip()}".encode()).hexdigest()[:12]
        out.append({
            "id": source_id or local,
            "sourceId": source_id,
            "name": d["name"].strip(),
            "city": d["address"].split(",")[0].strip(),
            "address": d["address"].strip(),
            "latitude": float(lat) if lat else None,
            "longitude": float(lon) if lon else None,
            "phones": nums,
            "website": site,
            "hours": hours(text),
            "hasExposition": "Есть экспозиция" in text,
            "isDistributor": "Официальный дистрибьютор" in text,
            "exposition": expo,
        })
    return out, fixed


def help_sections():
    lines = [l.strip() for l in open(ARCHIVE / "text/main-faq.txt", encoding="utf-8")]
    start = lines.index("FAQ", lines.index("Акции") if "Акции" in lines else 0)
    i = lines.index("Все", start) + 1
    names = []
    while lines[i] and lines[i] not in names and not lines[i].endswith("?"):
        names.append(lines[i])
        i += 1
        if lines[i] == names[0]:
            break
    sections, current, question = [], None, None
    for line in lines[i:]:
        if line.startswith("Используя сайт Salini"):
            break
        if not line:
            continue
        if line in names:
            current = {"title": line, "items": []}
            sections.append(current)
            question = None
        elif line.endswith("?") and current is not None:
            question = {"q": line, "a": ""}
            current["items"].append(question)
        elif question is not None:
            question["a"] += ("\n" if question["a"] else "") + line
    return [s for s in sections if s["items"]]


def main():
    global ARCHIVE
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, default=ARCHIVE,
                        help="site-audit-2026-10-06 folder (inventory/dealers.json, text/main-faq.txt)")
    ARCHIVE = parser.parse_args().archive
    catalog = json.load(open(OUT / "catalog.json"))
    urls = {p["url"].rstrip("/") + "/": p["id"] for p in catalog["products"]}
    ds, fixed = dealers(urls)
    json.dump({"snapshot": catalog.get("snapshot"), "dealers": ds}, open(OUT / "dealers.json", "w"), ensure_ascii=False, indent=1)
    hs = help_sections()
    json.dump({"snapshot": catalog.get("snapshot"), "source": "https://salini-srl.com/faq/", "sections": hs},
              open(OUT / "help.json", "w"), ensure_ascii=False, indent=1)
    print(f"dealers {len(ds)} · rewritten phone contacts {fixed} · without coordinates "
          f"{sum(1 for d in ds if d['latitude'] is None)} · help sections {len(hs)} · "
          f"questions {sum(len(s['items']) for s in hs)} · local ids {sum(1 for d in ds if d['sourceId'] is None)}")
    assert len({d["id"] for d in ds}) == len(ds), "dealer ids must be unique"


if __name__ == "__main__":
    sys.exit(main())
