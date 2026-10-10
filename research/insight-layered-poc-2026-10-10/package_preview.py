"""Bundle existing generated assets and code into an offline HTML preview.
No image manipulation, external dependencies or network operations.
"""
from pathlib import Path
import base64
import json

ROOT = Path(__file__).resolve().parent
html = (ROOT / 'index.html').read_text()
html = html.replace('<link rel="stylesheet" href="style.css">', '<style>' + (ROOT / 'style.css').read_text() + '</style>')
assets = {}
for name in ['workshop.png', 'carrier-loaded.png', 'carrier-empty.png']:
    assets[name] = 'data:image/png;base64,' + base64.b64encode((ROOT / 'assets' / name).read_bytes()).decode()
logo = 'data:image/svg+xml;base64,' + base64.b64encode((ROOT / 'assets/salini-logo.svg').read_bytes()).decode()
html = html.replace('assets/salini-logo.svg', logo)
html = html.replace('<script src="scene.js"></script>', '<script>window.INSIGHT_ASSETS=' + json.dumps(assets) + ';</script><script>' + (ROOT / 'scene.js').read_text() + '</script>')
(ROOT / 'preview.html').write_text(html)
print('Offline preview:', ROOT / 'preview.html')
