import sys,pathlib,json,re,hashlib,time,datetime,concurrent.futures,collections
from urllib.parse import urljoin,urlparse,urldefrag
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'.deps'))
import requests
from bs4 import BeautifulSoup
BASE='https://salini-srl.com'
ASSET_EXT={'.jpg','.jpeg','.png','.webp','.svg','.gif','.pdf','.zip','.rar','.7z','.3ds','.max','.obj','.fbx','.dwg','.dxf','.step','.stp','.glb','.gltf','.usdz','.mp4','.webm','.woff','.woff2','.ttf','.css','.js','.xlsx','.docx'}
EXCLUDE=('/personal/','/profile','/fileUpdate','/dompdf-test.php','/bitrix/','/admin','/search/','/auth/','/en/','/it/')
CAT={'vanny','rakoviny','mebel-dlya-vannoy','zerkala','unitazy-i-bide','dushevye-poddony','aksessuary','komplektuyushchie','stoleshnitsy','salini-essentials','chistyashchie-sredstva'}
def clean(s):return re.sub(r'\s+',' ',s or '').strip()
def normalize(u,base=BASE):
 u=urldefrag(urljoin(base,u.strip()))[0]
 return u if urlparse(u).scheme in ('http','https') else None
def kind(u):
 p=urlparse(u).path.strip('/').split('/');x=p[0]
 return 'home' if not x else ('catalog' if len(p)<3 else 'product_or_family') if x in CAT else 'collection' if x=='collection' else 'article' if x=='blog' and len(p)>1 else 'content'
def eligible(u):
 p=urlparse(u)
 return p.netloc=='salini-srl.com' and not p.query and not any(p.path.startswith(x) for x in EXCLUDE) and pathlib.Path(p.path).suffix.lower() not in ASSET_EXT and not p.path.endswith('.php')
def fetch(u):
 ident=hashlib.sha256(u.encode()).hexdigest()[:16];fn='raw/pages/'+ident+'.html';tn='text/'+ident+'.txt';t=time.time()
 try:
  r=requests.get(u,timeout=35,headers={'User-Agent':'Salini-design-research/1.0 (public content audit)'})
  data=r.content;(ROOT/fn).write_bytes(data)
  rec={'url':u,'final_url':r.url,'status':r.status_code,'seconds':round(time.time()-t,2),'bytes':len(data),'raw':fn,'text_file':tn,'kind':kind(u),'fetched_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
  if 'html' not in r.headers.get('Content-Type',''):rec['non_html']=r.headers.get('Content-Type');return rec,[],[]
  s=BeautifulSoup(data,'html.parser');head=s.head
  rec.update(title=clean(s.title.get_text()) if s.title else '',h1=[clean(x.get_text(' ')) for x in s.find_all('h1')],description=next((x.get('content','') for x in s.select('meta[name="description"]')),None),canonical=next((x.get('href') for x in s.select('link[rel="canonical"]')),None))
  links=[];assets={}
  def asset(v,tag,role,label=''):
   uu=normalize(v,r.url)
   if not uu:return
   ext=pathlib.Path(urlparse(uu).path).suffix.lower()
   if ext in ASSET_EXT:assets[uu]={'url':uu,'extension':ext,'role':role,'label':label,'source_page':u}
  for a in s.find_all('a',href=True):
   uu=normalize(a['href'],r.url)
   if uu:links.append({'url':uu,'label':clean(a.get_text(' '))});asset(uu,'a','download_or_link',clean(a.get_text(' ')))
  for el in s.find_all(True):
   for attr in ['src','data-src','data-original','poster','href','data-file','data-model']:
    if el.get(attr):asset(el.get(attr),el.name,el.name,el.get('alt',''))
   for attr in ['srcset','data-srcset']:
    for part in (el.get(attr) or '').split(','):
     if part.strip():asset(part.strip().split()[0],el.name,el.name,el.get('alt',''))
   for v in re.findall(r'url\([\'\"]?([^\)\'\"]+)',el.get('style','')):asset(v,el.name,'background')
  # Public asset URLs embedded in scripts / JSON, excluding arbitrary endpoints.
  for v in re.findall(r'(?:https?://|/upload/|/local/)[^\s"\'<>\\]+',r.text):
   if pathlib.Path(urlparse(v).path).suffix.lower() in ASSET_EXT:asset(v,'embedded','embedded')
  rec['links']=links;rec['assets']=list(assets)
  rec['forms']=[{'action':f.get('action'),'method':f.get('method'),'fields':[{'name':e.get('name'),'type':e.get('type',e.name),'placeholder':e.get('placeholder'),'required':e.has_attr('required')} for e in f.select('input,textarea,select') if e.get('type')!='hidden']} for f in s.find_all('form')]
  rec['json_ld']=[x.get_text() for x in s.select('script[type="application/ld+json"]')]
  rec['image_count']=len(s.find_all('img'));rec['images_missing_alt']=sum(not x.get('alt') for x in s.find_all('img'))
  for e in s(['script','style','noscript','svg']):e.decompose()
  txt='\n'.join(clean(x) for x in s.get_text('\n').splitlines() if clean(x));(ROOT/tn).write_text(txt)
  rec['text_chars']=len(txt)
  return rec,[l['url'] for l in links if eligible(l['url'])],list(assets.values())
 except Exception as e:return {'url':u,'error':str(e),'kind':kind(u)},[],[]

def main():
 seeds=json.loads((ROOT/'inventory/sitemap-urls.json').read_text());todo=set(x for x in seeds if eligible(x))|{BASE+'/'};seen=set();pages=[];assets={}
 while todo:
  batch=sorted(todo-seen);todo=set()
  if not batch:break
  print('BATCH',len(batch),flush=True)
  with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
   for rec,links,aa in ex.map(fetch,batch):
    seen.add(rec['url']);pages.append(rec)
    for a in aa:
     k=a['url']
     if k not in assets:assets[k]={**a,'source_pages':[]}
     if a['source_page'] not in assets[k]['source_pages']:assets[k]['source_pages'].append(a['source_page'])
    todo.update(x for x in links if x not in seen)
    if len(pages)%25==0:print('pages',len(pages),'assets',len(assets),'last',rec['url'],flush=True)
  (ROOT/'inventory/pages.json').write_text(json.dumps(pages,ensure_ascii=False,indent=2))
  (ROOT/'inventory/assets.json').write_text(json.dumps(list(assets.values()),ensure_ascii=False,indent=2))
  if len(seen)>1000:print('safety page cap',len(seen));break
 print('DONE',len(pages),len(assets),collections.Counter(p.get('status','error') for p in pages),flush=True)
 requests.get(BASE+'/robots.txt',timeout=20)
 (ROOT/'raw/robots.txt').write_bytes(requests.get(BASE+'/robots.txt',timeout=20).content)
if __name__=='__main__':main()
