"""Static contracts between the redesigned pages/ + web/ markup and code that is not redesigned.

Pure standard library: no server, no models, no network.
"""
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAGES, WEB = ROOT / 'pages', ROOT / 'web'
# pages/connect.js must stay byte-identical; update only together with a reviewed change.
CONNECT_SHA256 = '4c209b88928596b6afaf714e5353784405cbb811e05d6aa13aa374c587e52e69'


class Elements(HTMLParser):
    def __init__(self):
        super().__init__()
        self.items = []

    def handle_starttag(self, tag, attrs):
        self.items.append((tag, dict(attrs)))


def elements(path):
    parser = Elements()
    parser.feed(path.read_text())
    return parser.items


def ids(items):
    return {a['id']: (t, a) for t, a in items if 'id' in a}


def test_connect_script_and_endpoint_file_are_untouched():
    assert hashlib.sha256((PAGES / 'connect.js').read_bytes()).hexdigest() == CONNECT_SHA256
    assert 'url' in json.loads((PAGES / 'connection.json').read_text())


def test_pages_keeps_the_connection_contract():
    items = elements(PAGES / 'index.html')
    found = ids(items)
    for name in ('status', 'detail', 'dot', 'retry', 'open'):
        assert name in found, name
    assert 'hidden' in found['open'][1], '#open must start hidden; connect.js reveals it only when healthy'
    assert found['retry'][0] == 'button'
    assert ('script', {'src': './connect.js'}) in items
    assert ('meta', {'name': 'robots', 'content': 'noindex'}) in items
    assert ('meta', {'name': 'referrer', 'content': 'no-referrer'}) in items
    css = (PAGES / 'style.css').read_text()
    assert '[hidden]' in css and 'display: none !important' in css
    # connect.js paints the dot inline; the stylesheet maps both states in hex and rgb() serialisations.
    script = (PAGES / 'connect.js').read_text()
    for hex_colour, rgb in (('618a65', '97, 138, 101'), ('b89d69', '184, 157, 105')):
        assert '#' + hex_colour in script
        assert f'[style*="{hex_colour}"]' in css and f'[style*="{rgb}"]' in css


def test_no_third_party_requests_and_small_assets():
    for path in (PAGES / 'index.html', PAGES / 'style.css', WEB / 'index.html', WEB / 'style.css'):
        text = path.read_text()
        assert not re.search(r'(src|href)\s*=\s*["\']?(https?:)?//', text), path
        assert not re.search(r'url\(\s*["\']?(https?:)?//', text), path
        assert '@import' not in text and 'fonts.googleapis' not in text, path
    for folder, limit in ((PAGES / 'assets', 2_000_000), (WEB / 'assets', 1_000_000)):
        files = list(folder.iterdir())
        assert files and sum(f.stat().st_size for f in files) <= limit, folder
    for _, attrs in elements(PAGES / 'index.html') + elements(WEB / 'index.html'):
        for key in ('src', 'srcset'):
            if key in attrs and attrs[key].lstrip('./').startswith('assets/'):
                assert (PAGES if './' in attrs[key] else WEB).joinpath(attrs[key].lstrip('./').lstrip('/')).exists()


def test_web_markup_keeps_every_id_and_data_hook_used_by_scripts():
    found = ids(elements(WEB / 'index.html'))
    used = set()
    for script in ('app.js', 'online.js'):
        text = (WEB / script).read_text()
        used |= set(re.findall(r"\$\('([a-z0-9-]+)'\)", text))
        used |= set(re.findall(r"getElementById\('([a-z0-9-]+)'\)", text))
        used |= {m for m in re.findall(r"querySelector(?:All)?\('#([a-z0-9-]+)", text)}
    created_by_script = {'invite-code'}
    missing = sorted(used - set(found) - created_by_script)
    assert not missing, missing
    items = elements(WEB / 'index.html')
    modes = [a['data-mode'] for t, a in items if t == 'button' and 'data-mode' in a]
    looks = [a['data-look'] for t, a in items if t == 'button' and 'data-look' in a]
    assert modes == ['gentle', 'studio', 'daylight', 'warm', 'dramatic', 'highkey']
    assert looks == ['neutral', 'warm', 'cool', 'vivid', 'soft', 'contrast']
    # online.js prepends to .header-right and rewrites the first two plain paragraphs of #about.
    html = (WEB / 'index.html').read_text()
    assert 'class="header-right"' in html
    about = re.search(r'<dialog id="about">(.*?)</dialog>', html, re.S).group(1)
    assert len(re.findall(r'<p(?! class="eyebrow")[ >]', about)) >= 2


def test_online_index_string_replacements_still_apply():
    source = (ROOT / 'salini' / 'online_app.py').read_text()
    body = re.search(r"def index\(\):(.*?)return HTMLResponse", source, re.S).group(1)
    pairs = re.findall(r"\.replace\('((?:[^'\\]|\\.)*)','((?:[^'\\]|\\.)*)'\)", body)
    assert len(pairs) >= 7
    html = (WEB / 'index.html').read_text()
    for old, _ in pairs:
        assert html.count(old) == 1, f'replacement source must occur exactly once: {old!r}'


def test_glass_has_fallbacks_and_motion_is_optional():
    for css in ((PAGES / 'style.css').read_text(), (WEB / 'style.css').read_text()):
        assert '@supports not' in css and 'backdrop-filter' in css
        assert 'prefers-reduced-motion: reduce' in css
        assert 'prefers-reduced-transparency: reduce' in css
        assert 'focus-visible' in css
