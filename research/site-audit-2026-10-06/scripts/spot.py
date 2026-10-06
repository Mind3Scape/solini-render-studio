from crawl import *
urls=['/about-company/','/cooperation/','/dostavka-i-oplata/','/service/','/faq/','/contacts/','/e_learning/','/gallery/','/mebel-dlya-vannoy/','/where-buy/russia/','/sale/','/new/','/zerkala/','/collection/opera/','/rakoviny/podvesnye/laguna/','/vanny/otdelnostoyashchie/aria/','/stoleshnitsy/']
rows=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
 for rec,ll,aa in ex.map(fetch,[BASE+x for x in urls]):rows.append(rec);print(rec['url'],rec.get('status'),flush=True)
(ROOT/'inventory/spot-pages.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
for r in rows:
 if not r.get('text_file'):continue
 t=(ROOT/r['text_file']).read_text(); lines=t.splitlines(); start=next((i for i,l in enumerate(lines[30:],30) if l.lower()=='главная'),80)
 (ROOT/'text'/('spot-'+urlparse(r['url']).path.strip('/').replace('/','_')+'.txt')).write_text('\n'.join(lines[start:]))
