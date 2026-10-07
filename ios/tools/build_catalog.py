#!/usr/bin/env python3
"""Build the app's offline catalog from the 6 Oct 2026 public-site audit.

Inputs
  research/site-audit-2026-10-06/inventory/products.json   (in git)
  <archive>/raw/pages/*.html, <archive>/assets/images/*      (local archive, not in git)

Outputs  (ios/Salini/CatalogMedia, bundled as a folder resource)
  catalog.json   — one record per unique public product_id
  images/<id>.jpg — the card's first official product photograph, max 1100 px

Images (imageSource = exact URL, imageRole = gallery | hero):
  * candidates — the product's OWN gallery (sliders #product-slider2 / #product-slider inside the
    card's `card-content` block, before the configurator; related-product cards are never read)
    plus the page hero, but only when that hero file (by content, SHA-256) is not the hero of any
    other card — a shared banner is a family image (a sink page can carry the bath's hero);
  * among the candidates a studio product shot wins (>= 70 % of the frame border one plain,
    near-neutral tone; gallery first on ties); with no studio shot, the first own gallery photo;
  * no own gallery in the archive and no unique hero -> no photo. The page hero is always kept
    as `editorialSource` and never shown as the product.

Rules (see research/native-evolution-2026-10-07/OPUS-CONSULT.md):
  * variants, articles, prices and weights come only from the product's own
    configurator DOM (options-inner panels and data-tab-content="optN" spec blocks);
    "similar products" cards further down the page are never read;
  * anything not present in the source stays null and is shown as "по запросу";
  * no text is generated; descriptions are the page's own meta description.

Run:  python3 ios/tools/build_catalog.py [--archive PATH] [--no-images]
"""
import argparse
import hashlib
import html
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / 'research/site-audit-2026-10-06/inventory/products.json'
DEFAULT_ARCHIVE = Path('/Users/daviddoronin/Documents/ChatGPT/Salini/research/site-audit-2026-10-06')
OUT = ROOT / 'ios/Salini/CatalogMedia'
SNAPSHOT = '2026-10-06'

CATEGORY = {
    'vanny': 'Ванны', 'rakoviny': 'Раковины', 'dushevye-poddony': 'Душевые поддоны',
    'stoleshnitsy': 'Столешницы', 'mebel-dlya-vannoy': 'Мебель', 'salini-essentials': 'Мебель',
    'zerkala': 'Зеркала', 'unitazy-i-bide': 'Унитазы и биде', 'aksessuary': 'Аксессуары',
    'komplektuyushchie': 'Комплектующие', 'chistyashchie-sredstva': 'Уход',
}
SUBCATEGORY = {
    'otdelnostoyashchie': 'Отдельностоящие', 'vstraivaemye': 'Встраиваемые', 'uglovye': 'Угловые',
    'pristennye': 'Пристенные', 'nakladnye': 'Накладные', 'podvesnye': 'Подвесные',
    'napolnye': 'Напольные', 'poluvstraivaemye': 'Полувстраиваемые',
    'dopolnitelnye-vozmozhnosti': 'Опции и кастомизация', 'donnye-klapany': 'Донные клапаны',
    'sifony': 'Сифоны', 'kronshteyny': 'Кронштейны', 'gres': 'Керамогранит', 'costa': 'Costa',
    'oasi': 'Oasi', 'ombra-mirror': 'Ombra', 'armonia-mirror': 'Armonia', 'mebel-dlya-vannoy': 'Мебель',
}
MATERIAL = {'s_stone': 'sStone', 's_sense': 'sSense', 'mdf': 'mdf', 'solid_surface': 'solidSurface',
            'gelcoat': 'gelcoat'}
# Official USDZ files present in the archive, matched to exact catalogue names.
MODELS = {
    'НОЭМИ 170': 'Noemi-170', 'СОФИЯ 170': 'Sofia-170_Corona-fbx', 'СОФИЯ 165': 'Sofia-165_Corona-fbx',
    'СОФИЯ 185': 'Sofia-185_Corona-fbx', 'СОФИЯ 150': 'Sofia-150-2015-Corona-fbx', 'МОНА 170': 'Mona-170',
    'ОРНЕЛЛА 170х75': 'Ornella-170x75', 'КАСКАТА 180x80': 'Cascata-180x80', 'НИНФЕЯ': 'Ninfea',
    'ЛУЧЕ 170': 'Luce', 'GRECA 180': 'Greca', 'АЛЬДА 160х70': 'Alda-160-70',
    'ОРЛАНДА 160x70': 'Orlanda-160x70',
}
# The four products of the original prototype keep their ids through this mapping.
LEGACY = {'20645': 'aria', '30897': 'opera', '1120': 'greca', '30919': 'opera-top'}


def text(s):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', s or ''))).strip()


def number(s):
    s = (s or '').replace(',', '.').replace('\xa0', '').strip()
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v.is_integer() else v


def measure(s):
    """A number, or {"min","max"} for ranges written on the card («1715-2015», «900 - 1785»)."""
    v = text(s).replace(',', '.')
    m = re.fullmatch(r'(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)', v)
    if m:
        return {'min': number(m.group(1)), 'max': number(m.group(2))}
    return number(v)


def price(v):
    """Prices: a missing or zero value means «по запросу», never a free item."""
    n = number(v) if v not in (None, '') else None
    return n if isinstance(n, (int, float)) and n > 0 else None


def scalar(v):
    return v if isinstance(v, (int, float)) else None


def finish(coating):
    c = (coating or '').lower()
    if c.startswith('глянц'):
        return 'gloss'
    if c.startswith('мат'):
        return 'matte'
    return None


def display_name(name):
    """«ОРНЕЛЛА КИТ 170х75» → «Орнелла Кит 170×75»; Latin words keep their case."""
    words = []
    for w in name.split():
        if re.fullmatch(r'[А-ЯЁ-]+', w) and len(w) > 1:
            words.append(w[0] + w[1:].lower())
        else:
            words.append(w)
    out = ' '.join(words)
    return re.sub(r'(\d)\s*[xхХ]\s*(\d)', r'\1×\2', out)


def element_at(page, start):
    """The full element (balanced <div>…</div>) that opens at or before `start`."""
    open_tag = page.rfind('<div', 0, start + 1)
    if open_tag < 0:
        return ''
    depth, i = 0, open_tag
    for m in re.finditer(r'<div\b|</div>', page[open_tag:]):
        depth += 1 if m.group(0) == '<div' else -1
        if depth == 0:
            return page[open_tag:open_tag + m.end()]
    return page[open_tag:]


def configurator_end(page, start):
    """First landmark after the configurator: spec table or similar-product cards."""
    ends = [page.find(marker, start) for marker in
            ('class="table-content__item', 'catalog-card', 'card-content__info-table')]
    ends = [e for e in ends if e > start]
    return min(ends) if ends else len(page)


def panels_from(page):
    """Configurator panels per material: the default article plus named colour articles."""
    panels = {}
    starts = [m.start() for m in re.finditer(r'data-tab3-panel="options-inner"', page)]
    for n, pos in enumerate(starts):
        nxt = starts[n + 1] if n + 1 < len(starts) else len(page)
        seg = page[pos:min(nxt, configurator_end(page, pos))]
        m = re.search(r'data-material="([a-z_]+)"', seg)
        if not m or m.group(1) in panels:
            continue
        colours, seen = [], set()
        for tag in re.findall(r'<button[^>]*data-articule-tab="[^"]+"[^>]*>', seg):
            sku = re.search(r'data-articule-tab="([^"]+)"', tag).group(1).strip()
            ttl = re.search(r"data-opt-ttl=[\"']([^\"']*)[\"']", tag)
            title = ttl.group(1).strip() if ttl else ''
            if title in ('', 'RALCUST') or sku.endswith('F'):
                title = 'Цвет RAL на заказ' if sku.endswith('F') or title == 'RALCUST' else title
            if sku and sku not in seen and title and title not in {c['title'] for c in colours}:
                seen.add(sku)
                colours.append({'title': title, 'sku': sku})
        skus = [c['sku'] for c in colours]
        base = next((x for x in skus if not x.endswith('F')), None)
        panels[m.group(1)] = {'base': base, 'custom': next((x for x in skus if x.endswith('F')), None),
                              'colours': colours}
    return panels


def sku_finish(sku):
    """Salini article suffix: …G = глянцевое S-Sense, …M… = матовое исполнение."""
    core = re.sub(r'(F|H|N)+$', '', sku or '')
    if core.endswith('G'):
        return 'gloss'
    if core.endswith('M') or core.endswith('MN') or 'M' in core[-2:]:
        return 'matte'
    return None


def variants_from(record, page):
    """One variant per sellable (material, finish, price) from the configurator data.

    Articles come from the material's own panel and are attached only to the finish they
    encode; an execution without an article on the page keeps sku = null.
    """
    panels = panels_from(page)
    found, seen = [], set()
    for bv in record.get('base_variants') or []:
        mat, fin = bv.get('material'), finish(bv.get('coating-tab'))
        key = (mat, fin, bv.get('base-price'))
        if not mat or key in seen:
            continue
        seen.add(key)
        panel = panels.get(mat, {})
        same = [k for k in seen if k[0] == mat]
        base = panel.get('base')
        sku = base if base and (len(same) == 1 or sku_finish(base) == fin) else None
        found.append({
            'material': MATERIAL.get(mat, mat), 'finish': fin, 'sku': sku,
            'customColourSku': panel.get('custom') if sku else None,
            'colours': panel.get('colours', []) if sku else [],
            'price': price(bv.get('base-price')),
        })
    # A later variant of the same material may be the one the default article encodes.
    for mat, panel in panels.items():
        mine = [v for v in found if v['material'] == MATERIAL.get(mat, mat)]
        if panel.get('base') and not any(v['sku'] == panel['base'] for v in mine):
            match = next((v for v in mine if v['finish'] == sku_finish(panel['base'])), None)
            if match:
                match.update(sku=panel['base'], customColourSku=panel.get('custom'), colours=panel['colours'])
    return found


def specs_from(page):
    """Spec blocks of the main card only, keyed by material tab (optN → material)."""
    tabs = {}
    for a, b in re.findall(r'data-material(?:-tab)?="(s_[a-z]+)"[^>]*?data-tab="(opt\d+)"', page):
        tabs.setdefault(b, MATERIAL[a])
    for b, a in re.findall(r'data-tab="(opt\d+)"[^>]*?data-material(?:-tab)?="(s_[a-z]+)"', page):
        tabs.setdefault(b, MATERIAL[a])
    blocks = {}
    elements = [(m.group(1), element_at(page, m.start()))
                for m in re.finditer(r'data-tab-content="(opt\d+)"', page)]
    if not elements:
        first = page.find('card-content__info-table-inner')
        if first >= 0:
            # The main card's table sits in its own .table-content container.
            container = page.rfind('table-content', 0, first)
            elements = [(None, element_at(page, container if container >= 0 else first))]
    for tab, seg in elements:
        spec = {}
        for code, val in re.findall(r'data-code="([a-z_]+)"[^>]*>.*?data-value="([^"]*)"', seg, re.S):
            spec[code] = number(val)
        for ttl, val in re.findall(r'<div class="ttl">([^<]+)</div>\s*<div class="value"[^>]*>([^<]*)</div>', seg):
            t = text(ttl).lower()
            key = {'длина, мм': 'length', 'ширина, мм': 'width', 'высота, мм': 'height',
                   'глубина, мм': 'depth', 'диаметр, мм': 'diameter', 'тип': 'type',
                   'вес, кг': 'weight', 'вес с упаковкой, кг': 'weight_pack'}.get(t)
            if key and key not in spec:
                spec[key] = text(val) if key == 'type' else measure(val)
        if spec:
            # Tabs without a material (e.g. mirror shapes) keep the card's first, default block.
            blocks.setdefault(tabs.get(tab) if tab else None, spec)
    return blocks


def documents(downloads):
    """Deduplicated by URL; passports/drawings/models separated from paid options."""
    out, seen = [], set()
    for d in downloads:
        url = d.get('url')
        if not url or url in seen:
            continue
        seen.add(url)
        label = (d.get('label') or 'Документ').strip()
        low = label.lower()
        kind = ('passport' if 'паспорт' in low else 'drawing' if 'размер' in low or 'чертеж' in low or 'чертёж' in low
                else 'model' if '3d' in low else 'presentation' if 'презентац' in low
                else 'option' if 'изготовлен' in low or 'вырез' in low or 'отверсти' in low else 'other')
        out.append({'label': label, 'url': url, 'kind': kind})
    return out


def gallery_images(page):
    """Photos of the card's own product gallery, in page order (never related-product cards)."""
    start = page.find('class="card-content"')
    if start < 0:
        return []
    stops = [i for i in (page.find('data-tab-content-container="options"', start),
                         page.find('class="card-content__table-head"', start),
                         page.find('catalog-card', start)) if i > 0]
    end = min(stops) if stops else len(page)
    urls = []
    for sid in ('product-slider2', 'product-slider'):
        m = re.search(r'id="%s"' % sid, page[start:end])
        if not m:
            continue
        seg_start = start + m.end()
        seg_end = page.find('<button', seg_start)
        for u in re.findall(r'<img src="([^"]+)"', page[seg_start:seg_end if seg_end > 0 else end]):
            if u not in urls:
                urls.append(u)
    return urls


def studio_score(path):
    """Share of the frame border that is one plain, near-neutral tone (a studio product shot)."""
    from PIL import Image  # tool-only dependency
    im = Image.open(path).convert('RGB')
    im.thumbnail((96, 96))
    w, h = im.size
    px = im.load()
    ring = [px[x, y] for x in range(w) for y in range(h) if x < 4 or y < 4 or x >= w - 4 or y >= h - 4]
    base = sorted(ring, key=sum)[len(ring) // 2]
    plain = sum(1 for c in ring if max(abs(c[i] - base[i]) for i in range(3)) < 22 and max(c) - min(c) < 24)
    return plain / len(ring)


def local_image(archive, url):
    base = re.sub(r'[^A-Za-z0-9._-]+', '_', unquote(urlparse(url).path).split('/')[-1])[:140]
    name = hashlib.sha256(url.encode()).hexdigest()[:12] + '-' + base
    path = archive / 'assets/images' / name
    return path if path.exists() else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--archive', type=Path, default=DEFAULT_ARCHIVE)
    ap.add_argument('--no-images', action='store_true')
    args = ap.parse_args()
    records = json.load(open(INVENTORY))
    by_id = {}
    for r in records:
        pid = r.get('product_id')
        if not pid and r['category_path'][:1] != ['new']:
            page_path = args.archive / r['source_html']
            page = page_path.read_text(encoding='utf-8', errors='ignore') if page_path.exists() else ''
            m = re.search(r'data-id="(\d+)"[^>]*data-price="([^"]*)"[^>]*data-articule-elem="([^"]*)"', page)
            if m:
                pid = m.group(1)
                r = {**r, 'product_id': pid, 'initial_article': r.get('initial_article') or m.group(3),
                     'initial_price_rub': r.get('initial_price_rub') or m.group(2) or None}
        if not pid:
            continue  # landing pages of "new" items, not sellable cards
        prev = by_id.get(pid)
        if prev is None or len(r.get('base_variants') or []) > len(prev.get('base_variants') or []):
            by_id[pid] = r
    (OUT / 'images').mkdir(parents=True, exist_ok=True)
    products, missing_images, sku_source, hero_fallbacks = [], [], {'html': 0, 'initial': 0}, []
    previous_source, previous_role = {}, {}
    # How many cards carry each page-hero photo: a shared one is a family banner.
    # Compared by file content: the same banner is published under different CDN paths.
    hero_use = {}
    def content(url):
        return hashlib.sha256(local_image(args.archive, url).read_bytes()).hexdigest()
    for rec in by_id.values():
        first = next((u for u in rec.get('images') or [] if 'openpraph' not in u and local_image(args.archive, u)), None)
        if first:
            hero_use[content(first)] = hero_use.get(content(first), 0) + 1
    if (OUT / 'catalog.json').exists():
        for old in json.load(open(OUT / 'catalog.json')).get('products', []):
            previous_source[old['id']] = old.get('imageSource')
            previous_role[old['id']] = old.get('imageRole')
    for pid, r in sorted(by_id.items(), key=lambda kv: int(kv[0])):
        page_path = args.archive / r['source_html']
        page = page_path.read_text(encoding='utf-8', errors='ignore') if page_path.exists() else ''
        variants = variants_from(r, page)
        if variants:
            sku_source['html'] += 1
        else:
            sku_source['initial'] += 1
            mats = r.get('materials') or []
            bv = (r.get('base_variants') or [{}])[0]
            variants = [{
                'material': MATERIAL.get(bv.get('material') or (mats[0] if len(mats) == 1 else ''), None),
                'finish': finish(bv.get('coating-tab')), 'sku': r.get('initial_article'),
                'customColourSku': None, 'colours': [], 'price': price(r.get('initial_price_rub')),
            }]
        specs = specs_from(page)
        # Stable variant id: material + finish + ordinal among equal pairs. Never the price
        # (prices change) and never the article (an article may appear later).
        counts = {}
        for v in variants:
            pair = f"{v['material'] or 'none'}-{v['finish'] or 'none'}"
            counts[pair] = counts.get(pair, 0) + 1
            v['id'] = f"{pair}-{counts[pair]}"
        for v in variants:
            s = specs.get(v['material']) or specs.get(None) or (next(iter(specs.values())) if len(specs) == 1 else {})
            v['weightKg'] = scalar(s.get('weight'))
            v['packedWeightKg'] = scalar(s.get('weight_pack'))
        main_spec = specs.get(variants[0]['material']) or specs.get(None) or (next(iter(specs.values())) if specs else {})
        if not variants[0]['sku'] and r.get('initial_article'):
            variants[0]['sku'] = r['initial_article']
        desc = re.search(r'<meta name="description" content="([^"]*)"', page)
        path = r['category_path']
        cat = CATEGORY.get(path[0], path[0])
        if 'зеркало' in (main_spec.get('type') or '').lower() or path[0] == 'zerkala':
            cat = 'Зеркала'
        sub = SUBCATEGORY.get(path[1]) if len(path) > 1 else None
        avail = (r.get('availability_text') or '').strip()
        qty = re.match(r'(\d+)\s*шт', avail)
        image, chosen, role = None, None, None
        hero = [u for u in r.get('images') or [] if 'openpraph' not in u]
        gallery = gallery_images(page)
        fallback = next((u for u in hero if local_image(args.archive, u)), None)
        if fallback and hero_use.get(content(fallback), 0) > 1:
            fallback = None  # a banner shared by several cards is a family image, not this product
        # Prefer a studio product shot among the card's own photos (gallery first on ties);
        # otherwise the first photo of its own gallery.
        own_photos = [u for u in gallery if local_image(args.archive, u)]
        candidates = own_photos + ([fallback] if fallback else [])
        scored = [(studio_score(local_image(args.archive, u)), -i, u) for i, u in enumerate(candidates)]
        studio = [t for t in scored if t[0] >= 0.7]
        best = max(studio)[2] if studio else (own_photos[0] if own_photos else None)
        own = best if best in own_photos else None
        if best and best == fallback:
            own = None
        if args.no_images:
            # Keep what the existing files were built from.
            if (OUT / 'images' / f'{pid}.jpg').exists():
                image, chosen = f'images/{pid}.jpg', previous_source.get(pid) or own or fallback
                role = previous_role.get(pid) or ('gallery' if chosen == own else 'hero')
        elif own or fallback:
            chosen, role = (own, 'gallery') if own else (fallback, 'hero')
            dest = OUT / 'images' / f'{pid}.jpg'
            if previous_source.get(pid) != chosen or not dest.exists():
                subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '78', '-Z', '1100',
                                str(local_image(args.archive, chosen)), '--out', str(dest)],
                               check=True, capture_output=True)
            image = f'images/{pid}.jpg'
        else:
            missing_images.append(pid)
            stale = OUT / 'images' / f'{pid}.jpg'
            if not args.no_images and stale.exists():
                stale.unlink()
        if role == 'hero':
            hero_fallbacks.append(pid)
        name = r['name'].strip()
        products.append({
            'id': pid, 'legacyId': LEGACY.get(pid), 'siteName': name, 'name': display_name(name),
            'category': cat, 'subcategory': sub, 'isOption': path[1:2] == ['dopolnitelnye-vozmozhnosti'],
            'url': r['url'], 'description': text(desc.group(1))[:420] if desc else None,
            'dimensions': {k: main_spec.get(k) for k in ('length', 'width', 'height', 'depth', 'diameter')},
            'depthToOverflow': scalar(main_spec.get('depth_overflow')), 'type': main_spec.get('type'),
            'variants': variants,
            'availability': {'text': avail or None, 'stockQuantity': int(qty.group(1)) if qty else None,
                             'madeToOrder': avail.startswith('Под заказ')},
            'documents': documents(r.get('downloads') or []),
            'image': image, 'imageSource': chosen if image else None,
            # gallery: the card's own product gallery; hero: page banner (no own gallery archived).
            'imageRole': role if image else None,
            'editorialSource': next((u for u in hero if u != chosen), None),
            'model': MODELS.get(name),
        })
    # Official USDZ models (unchanged files from the archive). Greca already ships in Resources.
    (OUT / 'models').mkdir(exist_ok=True)
    for model in sorted({p['model'] for p in products if p['model'] and p['model'] != 'Greca'}):
        src = next((f for f in (args.archive / 'assets/models').glob('*.usdz')
                    if f.name.split('-', 1)[1].lower() == f'{model}.usdz'.lower()), None)
        dest = OUT / 'models' / f'{model}.usdz'
        if src and not dest.exists():
            dest.write_bytes(src.read_bytes())
        elif not src:
            print(f'missing model {model}', file=sys.stderr)
    catalog = {'snapshot': SNAPSHOT, 'source': 'https://salini-srl.com/', 'products': products}
    (OUT / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')))
    print(json.dumps({'products': len(products), 'variants': sum(len(p['variants']) for p in products),
                      'skuFromHtml': sku_source['html'], 'skuFromInitial': sku_source['initial'],
                      'withImage': sum(1 for p in products if p['image']), 'missingImages': len(missing_images),
                      'withModel': sum(1 for p in products if p['model']),
                      'imageFromGallery': sum(1 for p in products if p['imageRole'] == 'gallery'),
                      'imageFromHeroFallback': hero_fallbacks}, ensure_ascii=False))


if __name__ == '__main__':
    sys.exit(main())
