from crawl import *
from urllib.parse import unquote
pages=json.loads((ROOT/'inventory/pages.json').read_text());products=[];dealers=[];externals=[];filters=[];media=[]
for p in pages:
 if p.get('status')!=200 or not p.get('raw') or p.get('non_html'):continue
 s=BeautifulSoup((ROOT/p['raw']).read_bytes(),'html.parser');card=s.select_one('.card-body')
 if card:
  title=s.select_one('[data-product-title]');buy=s.select_one('[data-articule-elem]');art=s.select_one('[data-articule]');stat=s.select_one('[data-remains-val]')
  params=[]
  for x in card.select('.item[data-code],.with-ico__content,.info__item'):
   v=x.select_one('[data-value],.value,.info__value');tt=x.select_one('.ttl,.info__ttl')
   if v and tt:params.append({'key':x.get('data-code'),'label':clean(tt.get_text()),'value':v.get('data-value') or clean(v.get_text()),'text':clean(v.get_text())})
  opts=[]
  for x in card.select('[data-base-price]'):
   opts.append({k.replace('data-',''):v for k,v in x.attrs.items() if k.startswith('data-')})
  rec={'url':p['url'],'product_id':card.get('data-product-id'),'name':clean(title.get_text()) if title else p['h1'],'category_path':urlparse(p['url']).path.strip('/').split('/')[:-1],'initial_article':clean(art.get_text()) if art else (buy.get('data-articule-elem') if buy else None),'initial_price_rub':buy.get('data-price') if buy else None,'availability_text':clean(stat.get_text()) if stat else None,'technical_fields':params,'base_variants':opts,'has_inline_configurator':bool(s.select_one('.options-block')),'materials':sorted(set(x.get('data-material') for x in card.select('[data-material]'))),'downloads':[x for x in p.get('links',[]) if any(z in x['label'].lower() for z in ['модель','паспорт','техническ','черт','презентац','инструк','прайс'])],'images':[x.get('content') for x in s.select('meta[itemprop="image"],meta[property="og:image"]') if x.get('content')],'source_html':p['raw']}
  products.append(rec)
 for x in s.select('[data-placemark]'):
  tt=x.select_one('.buy-page__title');lk=x.select_one('[data-item-id]');exp=x.get('data-placemark-exposition')
  try:exp=json.loads(exp or '[]')
  except:pass
  dealers.append({'source_page':p['url'],'id':lk.get('data-item-id') if lk else None,'name':clean(tt.get_text()) if tt else None,'address':x.get('data-placemark'),'latitude':x.get('data-lat'),'longitude':x.get('data-long'),'store_type':x.get('data-store-type'),'exposition':exp,'contacts':[{'label':clean(a.get_text()),'url':a['href']} for a in x.select('a[href]')],'text':clean(x.get_text(' '))})
 for l in p.get('links',[]):
  if urlparse(l['url']).netloc in ['disk.yandex.ru','disk.360.yandex.ru','rutube.ru','salini.club','www.youtube.com','youtu.be']:externals.append({**l,'source_page':p['url']})
 for x in s.select('[data-fancybox-video],video,iframe'):
  media.append({'source_page':p['url'],'tag':x.name,'attrs':{k:v for k,v in x.attrs.items() if k in ['href','src','data-src','data-fancybox-video','poster']}})
 if p['kind']=='catalog':
  filters.append({'url':p['url'],'fields':[{k:v for k,v in x.attrs.items() if k.startswith('data-')} for x in s.select('[data-filter-field],[data-range-range]')],'selects':[{'label':x.get('data-select-placeholder'),'options':[clean(o.get_text()) for o in x.select('option')]} for x in s.find_all('select')]})
# URL aliases are retained, but count unique product IDs separately.
for fn,data in [('products.json',products),('dealers-initial-pages.json',dealers),('external-resources.json',externals),('filter-schema.json',filters),('embedded-media.json',media)]:
 (ROOT/'inventory'/fn).write_text(json.dumps(data,ensure_ascii=False,indent=2))
summary={'fetched_urls':len(pages),'status_counts':dict(collections.Counter(str(x.get('status','error')) for x in pages)),'page_types':dict(collections.Counter(x['kind'] for x in pages)),'product_pages':len(products),'unique_product_ids':len(set(x['product_id'] for x in products if x['product_id'])),'product_ids_note':'Public card records, not full SKU count; includes options / accessories.','initial_dealer_records':len(dealers),'external_yandex_links':len(set(x['url'] for x in externals if 'disk.' in x['url'])),'asset_urls':len(json.loads((ROOT/'inventory/assets.json').read_text())),'top_level_urls':dict(collections.Counter(urlparse(x['url']).path.strip('/').split('/')[0] or '/' for x in pages))}
(ROOT/'inventory/summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2));print(json.dumps(summary,ensure_ascii=False,indent=2))
