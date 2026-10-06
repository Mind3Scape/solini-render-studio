import json,pathlib
from PIL import Image
ROOT=pathlib.Path(__file__).resolve().parents[1]
archive=ROOT/'research/site-audit-2026-10-06'
dest=ROOT/'ios/Salini/Resources'
candidates=json.loads((archive/'inventory/design-candidates.json').read_text())
manifest=[]
for name,index in [('opera',19),('opera-detail',20),('opera-top',23),('greca',6),('aria',30),('aria-red',31),('interior',42),('stone',38),('production',41),('luce',3),('oriente',12)]:
 a=candidates[index];image=Image.open(archive/a['local']).convert('RGB');image.thumbnail((2000,2000));image.save(dest/(name+'.jpg'),quality=90,optimize=True)
 manifest.append({'asset':name+'.jpg','source_url':a['url'],'source_page':a.get('source_page'),'usage':'Salini concept prototype; original brand image, resized without generative changes'})
allp=json.loads((archive/'inventory/products.json').read_text());out=[]
for path,name,img,desc in [('vanny/otdelnostoyashchie/aria/','Aria','aria','Архитектурная чистота. Мягкий свет. Ванна, которая становится центром вашего пространства.'),('vanny/otdelnostoyashchie/opera/','Opera','opera','Классическая линия в современном прочтении. Выразительный силуэт и спокойная монументальность.'),('vanny/otdelnostoyashchie/greca/180/','Greca','greca','Пластика камня и мягкая геометрия. Коллекция для пространств с собственным характером.'),('rakoviny/nakladnye/opera-top/','Opera Top','opera-top','Скульптурная раковина. Продолжение коллекции Opera в каждой детали.')]:
 p=next(x for x in allp if x['url']=='https://salini-srl.com/'+path)
 dims=[]
 for label in ['Длина, мм','Ширина, мм','Высота, мм']:
  dims.append(next(x['value'] for x in p['technical_fields'] if x['label']==label and x['value']))
 out.append(dict(id=img,name=name,category='Раковины' if 'rakoviny' in path else 'Ванны',subtitle='Накладная раковина' if 'rakoviny' in path else 'Отдельностоящая ванна',dimensions=' × '.join(dims)+' мм',image=img,price=int(p['initial_price_rub']),stonePrice=890000 if img=='aria' else None,article=p['initial_article'],stoneArticle='1051201M' if img=='aria' else None,story=desc,source=p['url']))
(dest/'catalog.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
(ROOT/'ios/ASSET_SOURCES.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print('Prepared',len(manifest),'images,',len(out),'products')
