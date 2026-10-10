(() => {
 'use strict';
 const $ = id => document.getElementById(id);
 const canvas = $('scene'), ctx = canvas.getContext('2d', {alpha:false});
 const W=1536,H=1024,DURATION=42;
 const imageNames={room:'workshop.png',loaded:'carrier-loaded.png',empty:'carrier-empty.png'};
 const images={}, pins={quality:document.querySelector('.pin.quality'),packing:document.querySelector('.pin.packing'),carrier:document.querySelector('.pin.carrier')};
 const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 let playing=!reduced,time=0,last=0,zoom=1,targetZoom=1,follow=true,selected=null,art=false;
 let dims={w:1,h:1,dpr:1},camera={x:755,y:510},drawTransform={s:1,x:0,y:0};
 const options={carrier:true,shadows:true,activity:true,route:true};
 const S={hidden:{x:350,y:280},quality:{x:523,y:441},exit:{x:1800,y:1150}};
 const mix=(a,b,t)=>a+(b-a)*t;
 const ease=t=>{t=Math.max(0,Math.min(1,t));return t*t*t*(t*(t*6-15)+10)};
 const point=(a,b,t)=>({x:mix(a.x,b.x,t),y:mix(a.y,b.y,t)});
 function cycle(t){
  if(t<3.5)return {p:point(S.hidden,S.quality,ease(t/3.5)),loaded:true,stage:0,label:'Выход из зоны контроля',desc:'Партия 024 · 2 изделия · S-Stone',progress:t/8.5};
  if(t<8.5)return {p:S.quality,loaded:true,stage:0,label:'Проверка поверхности',desc:'Партия 024 · контрольная точка пройдена',progress:t/8.5,scan:(t-3.5)/5};
  if(t<21)return {p:point(S.quality,S.exit,ease((t-8.5)/12.5)),loaded:true,stage:1,label:'Партия направляется на упаковку',desc:'Партия 024 · движение в выделенном коридоре',progress:(t-8.5)/12.5};
  if(t<24.5)return {p:S.exit,loaded:false,stage:2,label:'Изделия переданы на упаковку',desc:'Партия 024 · следующий участок за границей кадра',progress:(t-21)/3.5};
  if(t<37)return {p:point(S.exit,S.hidden,ease((t-24.5)/12.5)),loaded:false,stage:2,label:'Пустая платформа возвращается',desc:'2 изделия переданы · возвращение к линии контроля',progress:1};
  return {p:S.hidden,loaded:false,stage:0,label:'Подготовка следующего цикла',desc:'Повтор учебного сценария · движения синхронизированы',progress:0};
 }
 function resize(){const r=canvas.getBoundingClientRect();dims={w:r.width,h:r.height,dpr:Math.min(devicePixelRatio||1,2)};canvas.width=Math.round(r.width*dims.dpr);canvas.height=Math.round(r.height*dims.dpr)}
 new ResizeObserver(resize).observe(canvas);
 function screen(p){return {x:p.x*drawTransform.s+drawTransform.x,y:p.y*drawTransform.s+drawTransform.y}}
 function positionPin(el,p,offset=0){const q=screen(p);el.style.left=q.x+'px';el.style.top=q.y+offset+'px';el.style.opacity=(q.x<20||q.x>dims.w-20||q.y<90||q.y>dims.h-235)?'0':'1';el.style.pointerEvents=el.style.opacity==='0'?'none':'auto'}
 function route(state){if(!options.route||art)return;ctx.save();ctx.lineWidth=1.6;ctx.strokeStyle='rgba(45,94,86,.22)';ctx.setLineDash([4,8]);ctx.beginPath();ctx.moveTo(536,475);ctx.lineTo(1440,976);ctx.stroke();ctx.setLineDash([]);if(state.stage===1){const p=state.p;const pulse=(Math.sin(time*2)+1)/2;ctx.strokeStyle=`rgba(79,120,103,${.2+pulse*.08})`;ctx.lineWidth=1;ctx.beginPath();ctx.ellipse(p.x,p.y+12,111,26,.49,0,Math.PI*2);ctx.stroke()}ctx.restore()}
 function shadow(p){if(!options.shadows)return;ctx.save();ctx.translate(p.x+14,p.y+8);ctx.rotate(.49);let g=ctx.createRadialGradient(0,0,3,0,0,108);g.addColorStop(0,'rgba(39,41,32,.27)');g.addColorStop(.6,'rgba(41,40,31,.10)');g.addColorStop(1,'rgba(41,40,31,0)');ctx.scale(1,.29);ctx.fillStyle=g;ctx.beginPath();ctx.arc(0,0,108,0,Math.PI*2);ctx.fill();ctx.restore();ctx.save();ctx.translate(p.x+1,p.y+5);ctx.rotate(.49);ctx.scale(1,.32);g=ctx.createRadialGradient(0,0,0,0,0,76);g.addColorStop(0,'rgba(31,33,28,.29)');g.addColorStop(1,'rgba(31,33,28,0)');ctx.fillStyle=g;ctx.beginPath();ctx.arc(0,0,76,0,Math.PI*2);ctx.fill();ctx.restore()}
 function cart(state){if(!options.carrier||art)return;const p=state.p;const size=227;const x=p.x-size*.5,y=p.y-size*.755;shadow(p);ctx.drawImage(state.loaded?images.loaded:images.empty,x,y,size,size);
  if(options.activity){const bx=x+size*.904,by=y+size*.545;const brightness=.35+.65*Math.pow((Math.sin(time*5)+1)/2,4);const g=ctx.createRadialGradient(bx,by,0,bx,by,8);g.addColorStop(0,`rgba(255,186,66,${brightness*.7})`);g.addColorStop(1,'rgba(255,167,37,0)');ctx.fillStyle=g;ctx.fillRect(bx-8,by-8,16,16);ctx.fillStyle=`rgba(255,237,176,${brightness})`;ctx.beginPath();ctx.ellipse(bx,by,1.5,1,0,0,Math.PI*2);ctx.fill();}
 }
 function machinery(){if(!options.activity||art)return;
  // The inspection light is confined to the existing product surface in the plate.
  const q=(Math.sin(time*1.15)+1)/2;ctx.save();ctx.beginPath();ctx.moveTo(325,235);ctx.quadraticCurveTo(365,215,406,222);ctx.quadraticCurveTo(406,243,367,254);ctx.quadraticCurveTo(344,253,325,235);ctx.clip();const x=330+q*73;const g=ctx.createLinearGradient(x-10,220,x+10,250);g.addColorStop(0,'rgba(219,242,248,0)');g.addColorStop(.47,'rgba(231,254,255,.03)');g.addColorStop(.5,'rgba(235,255,255,.62)');g.addColorStop(.53,'rgba(231,254,255,.03)');g.addColorStop(1,'rgba(219,242,248,0)');ctx.fillStyle=g;ctx.fillRect(317,216,104,42);ctx.restore();
  // Equipment LEDs and a restrained moving instrument trace, anchored to the screen.
  ctx.save();ctx.beginPath();ctx.moveTo(485,170);ctx.lineTo(536,183);ctx.lineTo(536,220);ctx.lineTo(485,205);ctx.closePath();ctx.clip();ctx.fillStyle='rgba(34,75,73,.14)';ctx.fillRect(485,170,53,50);ctx.lineWidth=.8;ctx.strokeStyle='rgba(183,224,209,.60)';ctx.beginPath();for(let i=0;i<48;i++){let y=190+i*.24+Math.sin(i*.38-time*3)*2.8;if(i===0)ctx.moveTo(487+i,y);else ctx.lineTo(487+i,y)}ctx.stroke();ctx.restore();
 }
 function occlusion(){
  // Reuse only foreground pixels of the background plate. This is a geometric
  // occlusion mask, not an opacity swap: the cart passes behind the station.
  ctx.save();ctx.beginPath();ctx.moveTo(215,70);ctx.lineTo(510,55);ctx.lineTo(577,175);ctx.lineTo(574,321);ctx.lineTo(537,345);ctx.lineTo(501,355);ctx.lineTo(476,337);ctx.lineTo(449,306);ctx.lineTo(274,345);ctx.lineTo(222,323);ctx.closePath();ctx.clip();ctx.drawImage(images.room,0,0,W,H);ctx.restore();
 }
 function render(){const state=cycle(time);ctx.setTransform(dims.dpr,0,0,dims.dpr,0,0);ctx.fillStyle='#e1e3df';ctx.fillRect(0,0,dims.w,dims.h);
  const base=Math.max(dims.w/W,dims.h/H);const scale=base*zoom;
  const tx=dims.w/2-camera.x*scale,ty=dims.h*.47-camera.y*scale;
  drawTransform={s:scale,x:Math.max(dims.w-W*scale,Math.min(0,tx)),y:Math.max(dims.h-H*scale,Math.min(0,ty))};
  ctx.save();ctx.translate(drawTransform.x,drawTransform.y);ctx.scale(scale,scale);ctx.drawImage(images.room,0,0,W,H);route(state);cart(state);occlusion();machinery();ctx.restore();
  positionPin(pins.quality,{x:530,y:341},-8);positionPin(pins.packing,{x:1190,y:453},-13);positionPin(pins.carrier,{x:state.p.x,y:state.p.y-155},-6);if(art||!options.carrier)pins.carrier.style.opacity='0';
  $('carrierPinText').textContent=state.loaded?'Партия 024 · 2 изделия':'Платформа · возврат';
  $('stageTitle').textContent=state.label;$('stageDetail').textContent=state.desc;
  $('stageEyebrow').textContent=['КОНТРОЛЬ КАЧЕСТВА','В ДВИЖЕНИИ','ПЕРЕДАЧА ИЗДЕЛИЙ'][state.stage];
  $('qualityState').textContent=state.stage===0?'Проверка':'Пройден';
  document.querySelectorAll('.stage-track button').forEach((el,i)=>{el.classList.toggle('active',i<=state.stage);el.querySelector('i').style.transform=`scaleX(${i<state.stage?1:i===state.stage?state.progress:0})`});
  $('timeText').textContent='00:'+String(Math.floor(time)).padStart(2,'0')+' / 00:42';if(document.activeElement!==$('timeline'))$('timeline').value=time;
  $('zoomText').textContent=Math.round(targetZoom*100)+'%';$('zoomIn').disabled=targetZoom>=1.15;$('zoomOut').disabled=targetZoom<=1;
  canvas.dataset.phase=state.stage;canvas.dataset.time=time.toFixed(2);canvas.dataset.loaded=String(state.loaded);canvas.dataset.zoom=zoom.toFixed(3);
 }
 function tick(now){const dt=last?Math.min((now-last)/1000,.07):0;last=now;if(playing&&!document.hidden){time=(time+dt)%DURATION}zoom=mix(zoom,targetZoom,1-Math.exp(-dt*5));const state=cycle(time);
  // Follow is translational only; there is never a rotation or automatic zoom.
  let target={x:755,y:510};if(dims.w<700&&follow){target.x=Math.max(600,Math.min(1015,state.p.x));target.y=510}
  camera.x=mix(camera.x,target.x,1-Math.exp(-dt*1.2));camera.y=mix(camera.y,target.y,1-Math.exp(-dt*1.2));render();requestAnimationFrame(tick)}
 function playState(){document.body.classList.toggle('static-motion',!playing);$('pause').setAttribute('aria-label',playing?'Приостановить':'Продолжить');$('pauseIcon').innerHTML=playing?'<path d="M7 5v10M13 5v10"/>':'<path d="m7 4 8 6-8 6Z"/>'}
 $('pause').onclick=()=>{playing=!playing;playState()};$('restart').onclick=()=>{time=0;playing=true;playState()};$('timeline').oninput=e=>{time=Number(e.target.value);render()};
 document.querySelectorAll('[data-seek]').forEach(el=>el.onclick=()=>{time=Number(el.dataset.seek);render()});
 $('zoomIn').onclick=()=>targetZoom=Math.min(1.15,+(targetZoom+.05).toFixed(2));$('zoomOut').onclick=()=>targetZoom=Math.max(1,+(targetZoom-.05).toFixed(2));
 canvas.addEventListener('wheel',e=>{e.preventDefault();targetZoom=Math.max(1,Math.min(1.15,targetZoom-Math.sign(e.deltaY)*.025))},{passive:false});
 $('follow').onclick=()=>{follow=!follow;$('follow').setAttribute('aria-pressed',String(follow));$('follow').querySelector('span').textContent=follow?'Следим за партией':'Обзор участка'};
 const details={quality:{eyebrow:'УЧАСТОК 04',title:'Контроль качества',body:'Выделенный пост контроля. Движение изделий связано с состоянием партии; выбранное действие остаётся в контексте участка.',metrics:[['Партия','024'],['На платформе','2 изделия'],['Состояние','Контроль / передача']],seek:5},packing:{eyebrow:'СЛЕДУЮЩИЙ ЭТАП',title:'Упаковка',body:'Платформа уходит к следующему участку за границей кадра и возвращается пустой. Разгрузка в этой пробе не показана.',metrics:[['Передача','2 изделия'],['Маршрут','Выделенный коридор'],['Данные','Демонстрация']],seek:21},carrier:{eyebrow:'ТРАНСПОРТНАЯ ПЛАТФОРМА',title:'Партия 024',body:'Изделия движутся вместе с защитной формой. Контактная тень, световой индикатор и маршрут привязаны к одному объекту.',metrics:[['Груз','2 раковины'],['Управление','Учебный цикл'],['Ракурс','Фиксированный']],seek:11}};
 function select(key){selected=key;const d=details[key];$('detailEyebrow').textContent=d.eyebrow;$('detailTitle').textContent=d.title;$('detailBody').textContent=d.body;$('detailMetrics').replaceChildren(...d.metrics.map(([a,b])=>{const div=document.createElement('div');const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=a;dd.textContent=b;div.append(dt,dd);return div}));$('detail').hidden=false;Object.entries(pins).forEach(([k,el])=>el.classList.toggle('active',k===key));$('layerPanel').hidden=true;$('layers').setAttribute('aria-pressed','false')}
 document.querySelectorAll('[data-select]').forEach(el=>el.onclick=()=>select(el.dataset.select));$('detailAction').onclick=()=>{time=details[selected].seek;playing=true;playState();$('detail').hidden=true};$('closeDetail').onclick=()=>{$('detail').hidden=true;Object.values(pins).forEach(x=>x.classList.remove('active'))};
 $('layers').onclick=()=>{$('layerPanel').hidden=!$('layerPanel').hidden;$('layers').setAttribute('aria-pressed',String(!$('layerPanel').hidden));$('detail').hidden=true};
 ['Carrier','Shadows','Activity','Route'].forEach(key=>$('show'+key).onchange=e=>{options[key.toLowerCase()]=e.target.checked;render()});
 $('compare').onclick=()=>{art=!art;document.body.classList.toggle('art',art);$('compare').setAttribute('aria-pressed',String(art));$('compare').textContent=art?'Вернуть живую сцену':'Показать только исходное изображение';render()};
 $('about').onclick=()=>$('info').showModal();$('closeInfo').onclick=()=>$('info').close();$('info').addEventListener('click',e=>{if(e.target===$('info'))$('info').close()});
 document.addEventListener('visibilitychange',()=>{last=0});
 document.addEventListener('keydown',e=>{if(e.code==='Space'&&!['INPUT','BUTTON','TEXTAREA'].includes(document.activeElement.tagName)&&!$('info').open){e.preventDefault();playing=!playing;playState()}});
 Promise.all(Object.entries(imageNames).map(([key,file])=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>{images[key]=im;resolve()};im.onerror=()=>reject(Error(file));im.src=(window.INSIGHT_ASSETS&&window.INSIGHT_ASSETS[file])||'assets/'+file}))).then(()=>{$('loading').remove();resize();playState();requestAnimationFrame(tick)}).catch(error=>{$('loading').className='loading error';$('loading').textContent='Не удалось загрузить '+error.message+'. Откройте автономный файл preview.html.'});
})();
