from crawl import *
from urllib.parse import unquote,quote
import threading,os
LOCK=threading.Lock();TOTAL=0;LIMIT=4_000_000_000;MAXFILE=100_000_000;SHAS={}
IMG={'.jpg','.jpeg','.png','.webp'}
def main():
 global TOTAL
 for f in (ROOT/'assets').glob('*/*'):
  if not f.is_file():continue
  sha=hashlib.sha256(f.read_bytes()).hexdigest()
  if sha in SHAS:
   if f.stat().st_ino!=SHAS[sha].stat().st_ino:
    f.unlink();os.link(SHAS[sha],f)
  else:SHAS[sha]=f;TOTAL+=f.stat().st_size
 print('EXISTING UNIQUE MB',round(TOTAL/1e6),flush=True)
 pages=json.loads((ROOT/'inventory/pages.json').read_text())
 if (ROOT/'inventory/spot-pages.json').exists():pages+=json.loads((ROOT/'inventory/spot-pages.json').read_text())
 assets=json.loads((ROOT/'inventory/assets.json').read_text());byurl={x['url']:x for x in assets};chosen={};omitted=[];palettes={}
 for a in assets:
  u=a['url'];h=urlparse(u).netloc;ext=a['extension'];base=unquote(urlparse(u).path).split('/')[-1]
  if h not in ['salini-srl.com','cdn-salini.storage.yandexcloud.net']:continue
  if ext in {'.pdf','.usdz','.zip','.max','.xlsx','.svg','.css'}:
   if ext=='.pdf' and ('palitra' in base.lower() or base in ['S_Stone.pdf','S-Sence-glyanec-new.pdf']):
    if base.lower() in palettes:omitted.append({'url':u,'reason':'repeated_palette_filename','representative_url':palettes[base.lower()]});continue
    palettes[base.lower()]=u
   chosen[u]=a
 for p in pages:
  if p.get('status')!=200 or not p.get('raw'):continue
  soup=BeautifulSoup((ROOT/p['raw']).read_bytes(),'html.parser')
  candidates=[]
  for x in soup.select('meta[property="og:image"],meta[itemprop="image"]'):
   if x.get('content'):candidates.append(normalize(x['content'],p['url']))
  body=soup.select_one('[data-product-id]') or soup.select_one('.catalog') or soup
  for x in body.select('img,[style]'):
   for k in ['data-src','src','data-original']:
    if x.get(k):candidates.append(normalize(x[k],p['url']))
   for v in re.findall(r'url\([\'\"]?([^\)\'\"]+)',x.get('style','')):candidates.append(normalize(v,p['url']))
  # Product main + representative gallery; all imagery from key brand and collection pages.
  budget=6 if soup.select_one('[data-product-id]') else 18 if p['kind'] in ['home','collection'] or any(z in p['url'] for z in ['/gallery/','/about-company/','/cooperation/']) else 4
  for u in dict.fromkeys(candidates):
   if not u:continue
   ext=pathlib.Path(urlparse(u).path).suffix.lower()
   if ext not in IMG or urlparse(u).netloc not in ['salini-srl.com','cdn-salini.storage.yandexcloud.net']:continue
   if any(z in u.lower() for z in ['logo','icon','blank','placeholder']):continue
   a=byurl.get(u,{'url':u,'extension':ext,'source_pages':[p['url']],'role':'representative_image'})
   chosen[u]=a;budget-=1
   if budget<=0:break
 # Font files referenced by saved public CSS, for archive/reference.
 for css in (ROOT/'assets').glob('style-*.css'):
  for v in re.findall(r'url\([\'\"]?([^\)\'\"]+)',css.read_text(errors='replace')):
   if pathlib.Path(urlparse(v).path).suffix in ['.woff','.woff2']:
    u=normalize(v,BASE+'/local/templates/main/app.css');chosen[u]={'url':u,'extension':pathlib.Path(v).suffix,'role':'font_reference','source_pages':[BASE+'/']}
 selected=sorted(chosen.values(),key=lambda a:0 if a["extension"] in IMG else 1);(ROOT/'inventory/asset-selection.json').write_text(json.dumps({'policy':'All direct public documents and models except repeated palette filenames; up to 6 representative images/product, 18/brand or collection or project; original URLs preserved. 100 MB per file, 4 GB unique-byte total safety caps.','selected':len(selected),'omitted_repeated_palettes':omitted},ensure_ascii=False,indent=2))
 print('SELECTED',len(selected),collections.Counter(x['extension'] for x in selected),flush=True)
 manifest=[]
 def download(a):
  global TOTAL
  u=a['url'];ext=a['extension'];cat='documents' if ext in ['.pdf','.xlsx'] else 'models' if ext in ['.usdz','.max','.zip'] else 'brand' if ext in ['.svg','.css','.woff','.woff2'] else 'images'
  base=re.sub(r'[^A-Za-z0-9._-]+','_',unquote(urlparse(u).path).split('/')[-1])[:140];name=hashlib.sha256(u.encode()).hexdigest()[:12]+'-'+base;path=ROOT/'assets'/cat/name;path.parent.mkdir(exist_ok=True,parents=True)
  if path.exists():return {**a,'local':str(path.relative_to(ROOT)),'bytes':path.stat().st_size,'status':'downloaded','sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
  try:
   with LOCK:
    if TOTAL>=LIMIT-1000000:return {**a,'status':'skipped_total_cap'}
   r=requests.get(u,timeout=(15,45),stream=True)
   if r.status_code!=200:return {**a,'status':'http_'+str(r.status_code)}
   size=int(r.headers.get('content-length',0))
   if size>MAXFILE:return {**a,'status':'skipped_large','advertised_bytes':size}
   data=bytearray()
   for chunk in r.iter_content(131072):
    data.extend(chunk)
    if len(data)>MAXFILE:return {**a,'status':'skipped_large','bytes_read':len(data)}
   ct=r.headers.get('content-type','')
   if 'html' in ct and ext!='.html':return {**a,'status':'unexpected_html','content_type':ct}
   sha=hashlib.sha256(data).hexdigest()
   with LOCK:
    if sha in SHAS:os.link(SHAS[sha],path)
    else:
     if TOTAL+len(data)>LIMIT:return {**a,'status':'skipped_total_cap'}
     TOTAL+=len(data);path.write_bytes(data);SHAS[sha]=path
   return {**a,'status':'downloaded','local':str(path.relative_to(ROOT)),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'content_type':ct}
  except Exception as e:return {**a,'status':'error','error':str(e)}
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
  for r in ex.map(download,selected):
   manifest.append(r)
   if len(manifest)%50==0:
    print('DOWNLOADED',len(manifest),'MB',round(TOTAL/1e6),flush=True);(ROOT/'inventory/downloads.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 (ROOT/'inventory/downloads.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2));print('DONE',len(manifest),TOTAL,collections.Counter(x['status'] for x in manifest),flush=True)
if __name__=='__main__':main()
