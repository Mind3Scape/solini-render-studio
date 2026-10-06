from crawl import *
from urllib.parse import unquote
pages=json.loads((ROOT/'inventory/pages.json').read_text());known={p['url'] for p in pages};extra=[]
for p in pages:
 if p['url'].rstrip('/') in [BASE+'/gallery',BASE+'/e_learning',BASE+'/blog']:
  links=[l['url'] for l in p.get('links',[]) if 'PAGEN_' in l['url']];nums=[int(re.search(r'PAGEN_\d+=(\d+)',u).group(1)) for u in links if re.search(r'PAGEN_\d+=(\d+)',u)]
  if nums:
   pat=next(re.search(r'PAGEN_\d+',u).group(0) for u in links if 'PAGEN_' in u)
   extra.extend(p['url']+'?'+pat+'='+str(n) for n in range(2,min(max(nums),30)+1))
extra.extend(p['url'] for p in pages if p.get('error'))
assets={a['url']:a for a in json.loads((ROOT/'inventory/assets.json').read_text())}
for round in range(2):
 todo=list(dict.fromkeys(extra));extra=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
  for r,ll,aa in ex.map(fetch,todo):
   pages=[p for p in pages if p['url']!=r['url']];pages.append(r);known.add(r['url']);print('extra',r['url'],r.get('status'),flush=True)
   for u in ll:
    if u not in known and ('/gallery/' in u or '/blog/' in u):extra.append(u)
   for a in aa:
    if a['url'] not in assets:assets[a['url']]={**a,'source_pages':[a['source_page']]}
(ROOT/'inventory/pages.json').write_text(json.dumps(pages,ensure_ascii=False,indent=2));(ROOT/'inventory/assets.json').write_text(json.dumps(list(assets.values()),ensure_ascii=False,indent=2))
print('DONE',len(pages),len(assets),flush=True)
