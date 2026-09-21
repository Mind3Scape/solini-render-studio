const $ = id => document.getElementById(id);
const state = {upload:null, crop:null, original:null, job:null, mode:'gentle', busy:false, editing:false,
  draft:null, full:false, after:false, split:50, zoom:1, pan:{x:0,y:0}, width:1, height:1, models:[], token:0, revision:0, restored:0,
  colorStyle:'neutral', colorStrength:60, amount:100, lookSaving:false, lookPending:false, lookRevision:0};
let pollTimer, clockTimer, lookTimer, drag = null;

async function api(path, options={}) {
  const response = await fetch(path, options);
  if (!response.ok) {
    let data; try { data = await response.json(); } catch { data = {}; }
    throw new Error(typeof data.detail === 'string' ? data.detail : `Не удалось выполнить запрос (${response.status}).`);
  }
  return response.json();
}
function error(message='') { $('error').textContent=message; $('error').hidden=!message; }
function status(message) { $('status-text').textContent=message; }
function loadImage(url) { return new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(new Error('Не удалось открыть изображение.'));im.src=url;}); }
function croppedURL() {
  const [x,y,w,h]=state.crop, canvas=document.createElement('canvas');
  canvas.width=w;canvas.height=h;canvas.getContext('2d').drawImage(state.original,x,y,w,h,0,0,w,h);
  return canvas.toDataURL('image/png');
}
function resetZoom(){state.zoom=1;state.pan={x:0,y:0};positionPlane();}
function positionPlane(){
  if(!state.upload)return;
  const fit=Math.min(($('viewport').clientWidth-30)/state.width,($('viewport').clientHeight-30)/state.height);
  const w=state.width*fit,h=state.height*fit,plane=$('plane');
  plane.style.width=`${w}px`;plane.style.height=`${h}px`;
  plane.style.transform=`translate(calc(-50% + ${state.pan.x}px),calc(-50% + ${state.pan.y}px)) scale(${state.zoom})`;
  $('zoom-fit').textContent=state.zoom===1?'Вписать':`${Math.round(state.zoom*100)}%`;
  $('viewport').classList.toggle('pannable',state.zoom>1&&!state.editing);
  if(state.editing)drawCrop();
}
function setSplit(value){
  state.split=Math.min(100,Math.max(0,value));
  $('after-layer').style.clipPath=`inset(0 0 0 ${state.split}%)`;
  $('divider').style.left=`${state.split}%`;$('split-range').value=state.split;
}
function controls(){
  const has=!!state.upload;
  $('crop-controls').hidden=!has;$('empty').hidden=has;$('plane').hidden=!has;
  const selected=state.models.find(m=>m.key===$('model').value);
  $('generate').disabled=!has||state.busy||state.editing||state.lookSaving||state.lookPending||!!selected?.blocker;
  $('view-document').disabled=!has||state.editing;
  ['zoom-in','zoom-out','zoom-fit'].forEach(id=>$(id).disabled=!has||state.editing);
  ['upload-btn','replace-btn','empty-upload','crop-btn','reset-crop','model','resolution','seed','note'].forEach(id=>$(id).disabled=state.busy||!!state.editing||state.lookSaving||state.lookPending);
  document.querySelectorAll('#modes button').forEach(b=>b.disabled=state.busy||selected?.task==='upscale');
  if(selected?.task==='upscale')$('note').disabled=true;
  $('cancel').hidden=!state.busy;
  document.body.classList.toggle('busy',state.busy);
  $('view-crop').classList.toggle('active',!state.full);
  $('view-document').classList.toggle('active',state.full);
  $('crop-toolbar').hidden=!state.editing;
  $('crop-toolbar').querySelector('span').textContent=state.editing==='restore'?'Обведите деталь для восстановления':'Обведите рендер мышью';
  $('crop-apply').textContent=state.editing==='restore'?'Вернуть оригинал':'Применить';
  $('crop-overlay').hidden=!state.editing;
  $('viewport').classList.toggle('crop-mode',state.editing);
  const compare=state.after&&!state.editing;
  ['after-layer','divider','side-labels','comparison-controls'].forEach(id=>$(id).hidden=!compare);
  $('downloads').hidden=!state.job||!state.after||state.busy;
  $('repair-controls').hidden=!state.after||state.busy||!!state.editing;
  $('restore-btn').disabled=$('restore-reset').disabled=state.lookSaving||state.lookPending;
  $('downloads').classList.toggle('saving',state.lookSaving||state.lookPending);
  $('more-export').disabled=state.lookSaving||state.lookPending;
  document.querySelectorAll('#downloads a, #export-dialog a').forEach(el=>el.setAttribute('aria-disabled',String(state.lookSaving||state.lookPending)));
  document.querySelectorAll('#looks button, #color-strength, #amount').forEach(el=>el.disabled=state.busy||!!state.editing);
  $('restore-reset').hidden=!state.restored;
  if(has){
    const [x,y,w,h]=state.crop;
    $('image-size').textContent=`${state.upload.width} × ${state.upload.height} px`;
    $('upload-title').textContent=state.upload.name;
    $('upload-sub').textContent='Изображение загружено';
    $('image-label').textContent=state.upload.name;
    const isCrop=x!==0||y!==0||w!==state.upload.width||h!==state.upload.height;
    $('reset-crop').hidden=!isCrop;
    $('crop-hint').textContent=isCrop?`Область обработки: ${w} × ${h} px. Остальной лист сохранится.`:'Если загружен лист согласования, выделите только картинку изделия.';
  }
}
async function showImages(preserveZoom=false){
  const token=++state.token;
  const full=state.full||state.editing==='crop';
  let before=full?state.upload.url:croppedURL(),after=null;
  if(state.job&&state.after&&!state.editing){
    before=full?state.upload.url:`/api/jobs/${state.job}/files/before.png`;
    after=`/api/jobs/${state.job}/files/${full?'document.png':'after.png'}?v=${state.revision}`;
  }
  if(state.editing==='restore')before=`/api/jobs/${state.job}/files/after.png?v=${state.revision}`;
  const im=await loadImage(before);
  const ai=after?await loadImage(after):null;
  if(token!==state.token)return;
  $('before-image').src=im.src;
  if(ai)$('after-image').src=ai.src;
  state.width=im.naturalWidth;state.height=im.naturalHeight;
  controls();if(preserveZoom)positionPlane();else resetZoom();setSplit(state.split);
}
function remember(){
  try{localStorage.setItem('salini-session',JSON.stringify({upload:state.upload,crop:state.crop,job:state.job,after:state.after}));}catch{}
}
async function acceptUpload(info){
  state.original=await loadImage(info.url);state.upload=info;
  state.crop=[0,0,info.width,info.height];state.job=null;state.after=false;state.full=false;state.editing=false;
  state.restored=0;
  $('elapsed').textContent='';error();await showImages();remember();
  status('Выделите рендер внутри листа или обработайте изображение целиком.');
}
async function upload(file){
  if(!file||state.busy||state.lookSaving||state.lookPending)return;
  error();status('Загрузка изображения…');
  if(file.size>40*1024*1024){error('Файл должен быть меньше 40 МБ.');return;}
  const data=new FormData();data.append('file',file);
  try{await acceptUpload(await api('/api/uploads',{method:'POST',body:data}));}
  catch(e){error(e.message);status('Выберите другое изображение.');}
  $('file').value='';
}
['upload-btn','replace-btn','empty-upload'].forEach(id=>$(id).onclick=()=>$('file').click());
$('file').onchange=e=>upload(e.target.files[0]);
let dragDepth=0;
document.addEventListener('dragenter',e=>{e.preventDefault();if(e.dataTransfer.types.includes('Files')&&!state.busy){dragDepth++;$('drop-overlay').hidden=false;}});
document.addEventListener('dragover',e=>e.preventDefault());
document.addEventListener('dragleave',e=>{e.preventDefault();if(--dragDepth<=0){dragDepth=0;$('drop-overlay').hidden=true;}});
document.addEventListener('drop',e=>{e.preventDefault();dragDepth=0;$('drop-overlay').hidden=true;upload(e.dataTransfer.files[0]);});

function point(e){const r=$('plane').getBoundingClientRect();return{x:Math.max(0,Math.min(state.width,Math.round((e.clientX-r.left)/r.width*state.width))),y:Math.max(0,Math.min(state.height,Math.round((e.clientY-r.top)/r.height*state.height))) };}
function drawCrop(){
  const [x,y,w,h]=state.draft||state.crop,el=$('crop-overlay');
  el.style.left=x/state.width*100+'%';el.style.top=y/state.height*100+'%';
  el.style.width=w/state.width*100+'%';el.style.height=h/state.height*100+'%';
  const minimum=state.editing==='restore'?4:64;
  $('crop-apply').disabled=w<minimum||h<minimum;
}
$('crop-btn').onclick=async()=>{state.editing='crop';state.full=false;state.draft=[...state.crop];error();await showImages();};
$('restore-btn').onclick=async()=>{state.editing='restore';state.full=false;state.draft=[0,0,0,0];error();await showImages();status('Обведите изменённую деталь. Её пиксели будут взяты из исходного рендера.');};
$('restore-reset').onclick=()=>restore(null,true);
async function restore(box,reset=false){
  $('crop-apply').disabled=true;$('restore-reset').disabled=true;
  try{
    const result=await api(`/api/jobs/${state.job}/restore`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({box,reset})});
    state.restored=result.restored_regions.length;state.revision=Date.now();state.editing=false;state.draft=null;
    await showImages();await refreshHistory();error();status(reset?'Исправления сброшены. Показан исходный результат AI.':'Деталь восстановлена из оригинала. Проверьте границы участка разделителем.');
  }catch(e){error(e.message);}
  finally{$('restore-reset').disabled=false;if(state.editing)drawCrop();}
}
$('crop-discard').onclick=async()=>{state.editing=false;state.draft=null;await showImages();};
$('crop-apply').onclick=async()=>{
  if(state.editing==='restore'){if(state.draft&&Math.min(state.draft[2],state.draft[3])>=4)await restore([...state.draft]);return;}
  if(!state.draft||state.draft[2]<64||state.draft[3]<64)return;
  const [, , w,h]=state.draft;if(Math.max(w/h,h/w)>4){error('Выделение слишком узкое. Выберите всё изделие вместе с небольшим полем.');return;}
  state.crop=[...state.draft];state.editing=false;state.full=false;state.job=null;state.after=false;
  await showImages();remember();error();status('Область выбрана. Можно начать обработку.');
};
$('reset-crop').onclick=async()=>{state.crop=[0,0,state.upload.width,state.upload.height];state.job=null;state.after=false;state.full=false;await showImages();remember();};
$('viewport').onpointerdown=e=>{
  if(!state.upload||e.target.closest('#crop-toolbar')||e.target.closest('#empty'))return;
  const p=point(e);
  if(state.editing){drag={type:'crop',start:p};state.draft=[p.x,p.y,0,0];drawCrop();}
  else if(e.target.closest('#divider')||state.zoom===1&&state.after){drag={type:'split'};const r=$('plane').getBoundingClientRect();setSplit((e.clientX-r.left)/r.width*100);}
  else if(state.zoom>1){drag={type:'pan',x:e.clientX,y:e.clientY,pan:{...state.pan}};}
  if(drag){e.preventDefault();$('viewport').setPointerCapture(e.pointerId);}
};
$('viewport').onpointermove=e=>{
  if(!drag)return;
  if(drag.type==='crop'){const p=point(e),a=drag.start;state.draft=[Math.min(a.x,p.x),Math.min(a.y,p.y),Math.abs(p.x-a.x),Math.abs(p.y-a.y)];drawCrop();}
  else if(drag.type==='split'){const r=$('plane').getBoundingClientRect();setSplit((e.clientX-r.left)/r.width*100);}
  else{state.pan={x:drag.pan.x+e.clientX-drag.x,y:drag.pan.y+e.clientY-drag.y};positionPlane();}
};
$('viewport').onpointerup=$('viewport').onpointercancel=()=>drag=null;
$('split-range').oninput=e=>setSplit(+e.target.value);
$('split-reset').onclick=()=>setSplit(50);
$('divider-handle').onkeydown=e=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();setSplit(e.key==='Home'?0:e.key==='End'?100:state.split+(e.key==='ArrowLeft'?-5:5));}};
$('zoom-in').onclick=()=>{state.zoom=Math.min(4,state.zoom+.5);positionPlane();};
$('zoom-out').onclick=()=>{state.zoom=Math.max(1,state.zoom-.5);if(state.zoom===1)state.pan={x:0,y:0};positionPlane();};
$('zoom-fit').onclick=resetZoom;
$('view-crop').onclick=async()=>{if(!state.upload||state.editing)return;state.full=false;await showImages();};
$('view-document').onclick=async()=>{if(!state.upload)return;state.full=true;await showImages();};
new ResizeObserver(positionPlane).observe($('viewport'));
document.querySelectorAll('#modes button').forEach(b=>b.onclick=()=>{
  state.mode=b.dataset.mode;
  document.querySelectorAll('#modes button').forEach(x=>{x.classList.toggle('selected',x===b);x.setAttribute('aria-pressed',String(x===b));});
  lightHint();
});
function lightHint(){
  if(state.models.find(m=>m.key===$('model').value)?.task==='upscale'){
    $('mode-hint').textContent='Этот режим улучшает детали. Свет и описание материала не используются; цвет можно менять ползунками.';return;
  }
  const descriptions={gentle:'Сохраняет направление исходного света.',studio:'Боковой студийный свет, блики и выраженные края.',daylight:'Мягкий дневной свет слева и естественные тени.',warm:'Тёплый боковой свет и золотистые блики.',dramatic:'Один боковой источник, глубокие тени и высокий контраст.',highkey:'Яркий рассеянный свет и светлые мягкие тени.'};
  $('mode-hint').textContent=descriptions[state.mode]+' Новый свет применяется при следующей AI-обработке.';
}
function fillModels(){
  const value=$('model').value;$('model').replaceChildren();
  for(const [label,predicate] of [['Редакторы изображений',m=>!!m.engine],['Другие проекты из обзора',m=>!m.engine]]){
    const group=document.createElement('optgroup');group.label=label;
    state.models.filter(predicate).forEach(m=>{const option=document.createElement('option');option.value=m.key;option.textContent=m.name+(m.ready?' · загружена':'')+(m.blocker?' · ограничения':'');group.append(option);});
    $('model').append(group);
  }
  if(state.models.some(m=>m.key===value))$('model').value=value;
}
function modelInfo(){
  const m=state.models.find(m=>m.key===$('model').value);if(!m)return;
  $('model-info').textContent=m.blocker||`${m.description}. ${m.ready?'Загружена · работает офлайн.':`При первой обработке загрузится до ${m.download_gb} ГБ.`}${m.tested?'':' Пробный режим: качество полного прогона ещё не проверено.'}`;
  $('model-info').classList.toggle('blocked',!!m.blocker);$('model-source').href=m.source;
  lightHint();controls();
}
$('model').onchange=()=>{const m=state.models.find(m=>m.key===$('model').value);if(m?.engine==='cpp')$('resolution').value=m.task==='upscale'?1024:512;modelInfo();};
function lookValues(){return {color_style:state.colorStyle,color_strength:state.colorStrength,amount:state.amount};}
function lookControls(){
  document.querySelectorAll('#looks button').forEach(b=>{b.classList.toggle('selected',b.dataset.look===state.colorStyle);b.setAttribute('aria-pressed',String(b.dataset.look===state.colorStyle));});
  $('color-strength').value=state.colorStrength;$('amount').value=state.amount;
  $('color-value').textContent=state.colorStrength+'%';$('amount-value').textContent=state.amount+'%';
}
function loadLook(settings){state.colorStyle=settings.color_style||'neutral';state.colorStrength=settings.color_strength??60;state.amount=settings.amount??100;lookControls();}
function queueLook(){
  lookControls();clearTimeout(lookTimer);state.lookRevision++;
  if(!state.after||!state.job){$('look-status').textContent='Настройки применятся к результату';return;}
  state.lookPending=true;controls();$('look-status').textContent='Применение цвета…';
  lookTimer=setTimeout(saveLook,250);
}
async function saveLook(){
  if(state.lookSaving||!state.lookPending||!state.after)return;
  state.lookSaving=true;controls();const job=state.job;
  try{
    while(state.lookPending&&state.job===job){
      state.lookPending=false;const revision=state.lookRevision;
      await api(`/api/jobs/${job}/look`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(lookValues())});
      if(state.job!==job)return;
      state.revision=Date.now();
      if(revision===state.lookRevision)await showImages(true);
    }
    $('look-status').textContent='Сохранено · без нового запуска AI';error();
  }catch(e){state.lookPending=false;error(e.message);$('look-status').textContent='Не удалось применить настройки';
    try{const data=await api(`/api/jobs/${job}`);loadLook(data.settings);}catch{}
  }finally{state.lookSaving=false;controls();}
}
document.querySelectorAll('#looks button').forEach(b=>b.onclick=()=>{state.colorStyle=b.dataset.look;queueLook();});
$('color-strength').oninput=e=>{state.colorStrength=Number(e.target.value);queueLook();};
$('amount').oninput=e=>{state.amount=Number(e.target.value);queueLook();};
function startClock(created){clearInterval(clockTimer);const tick=()=>{const s=Math.floor(Date.now()/1000-created);$('elapsed').textContent=s<60?`${s} сек`:`${Math.floor(s/60)} мин ${s%60} сек`;};tick();clockTimer=setInterval(tick,1000);}
function setDownloads(key){
  const base=`/api/jobs/${key}/files/`;
  $('download-result').href=base+'after.png?download=true';
  $('export-compare').href=base+'comparison.html?download=true';
  $('export-document').href=base+'document.png?download=true';
  $('export-settings').href=base+'settings.json?download=true';
}
document.querySelectorAll('#downloads a, #export-dialog a').forEach(el=>el.addEventListener('click',e=>{
  if(state.lookSaving||state.lookPending)e.preventDefault();
}));
async function finish(data){
  state.busy=false;clearInterval(clockTimer);clearTimeout(pollTimer);controls();
  if(data.status==='done'){
    state.after=true;setDownloads(data.id);await showImages();remember();
    status('Готово · перетащите разделитель, чтобы проверить детали');
    if(data.elapsed)$('elapsed').textContent=`${Math.round(data.elapsed)} сек`;
    await refreshHistory();const s=await api('/api/status');state.models=s.models;fillModels();modelInfo();$('look-status').textContent='Можно менять без нового запуска AI';
  }else{status(data.message);if(data.status==='failed'){error(data.message);const link=document.createElement('a');link.href=`/api/jobs/${data.id}/files/worker.log?download=true`;link.textContent=' Скачать журнал';link.className='text-button';$('error').append(link);}state.job=null;remember();}
}
async function poll(){
  if(!state.busy||!state.job)return;
  try{const data=await api(`/api/jobs/${state.job}`);status(data.message);if(['done','failed','cancelled'].includes(data.status)){await finish(data);return;}}
  catch(e){status('Связь с приложением прервалась. Переподключение…');}
  pollTimer=setTimeout(poll,1500);
}
$('generate').onclick=async()=>{
  if(!state.upload||state.busy)return;
  error();
  const seed=Number($('seed').value);
  if(!Number.isInteger(seed)||seed<0||seed>4294967295){error('Номер варианта должен быть целым числом от 0 до 4294967295.');return;}
  state.busy=true;state.after=false;state.job=null;state.full=false;state.restored=0;controls();
  try{const data=await api('/api/jobs',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({upload_id:state.upload.id,crop:state.crop,model:$('model').value,mode:state.mode,resolution:Number($('resolution').value),seed,note:$('note').value,...lookValues()})});
    state.job=data.id;remember();startClock(Date.now()/1000);await showImages();poll();
  }catch(e){state.busy=false;controls();error(e.message);status('Обработка не началась.');}
};
$('cancel').onclick=async()=>{if(!state.job)return;try{await api(`/api/jobs/${state.job}/cancel`,{method:'POST'});}catch(e){error(e.message);}};
async function openJob(key, running=false){
  if((state.busy&&!running)||state.lookSaving||state.lookPending)return;
  const data=await api(`/api/jobs/${key}`),settings=data.settings;
  const upload=await api(`/api/uploads/${settings.upload_id}`);
  state.original=await loadImage(upload.url);state.upload=upload;state.crop=settings.crop;state.job=key;
  state.after=data.status==='done';state.full=false;state.editing=false;state.busy=running;state.restored=(settings.restored_regions||[]).length;
  $('model').value=settings.model;$('resolution').value=settings.resolution;$('seed').value=settings.seed;$('note').value=settings.note;
  state.mode=settings.mode;document.querySelectorAll('#modes button').forEach(b=>{b.classList.toggle('selected',b.dataset.mode===state.mode);b.setAttribute('aria-pressed',String(b.dataset.mode===state.mode));});
  lightHint();loadLook(settings);$('look-status').textContent='Можно менять без нового запуска AI';
  setDownloads(key);await showImages();remember();error();modelInfo();
  if(running){startClock(data.created_at);poll();}else{status('Готово · перетащите разделитель, чтобы проверить детали');$('elapsed').textContent=data.elapsed?`${Math.round(data.elapsed)} сек`:'';}
}
async function refreshHistory(){
  const jobs=await api('/api/jobs');$('history').replaceChildren();$('history-section').hidden=!jobs.length;
  jobs.forEach(job=>{const b=document.createElement('button');b.className='history-card';b.title=job.name;
    const img=document.createElement('img');img.src=`/api/jobs/${job.id}/files/after.png`;img.alt='Результат обработки';img.loading='lazy';
    const name=document.createElement('span');name.textContent=state.models.find(m=>m.key===job.model)?.name||job.name;
    const date=document.createElement('small');date.textContent=new Date(job.created_at*1000).toLocaleString('ru-RU',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});
    b.append(img,name,date);b.onclick=()=>openJob(job.id).catch(e=>error(e.message));$('history').append(b);});
}
$('about-btn').onclick=()=>$('about').showModal();$('more-export').onclick=()=>$('export-dialog').showModal();
document.querySelectorAll('dialog .close').forEach(b=>b.onclick=()=>b.closest('dialog').close());
document.querySelectorAll('dialog').forEach(d=>d.addEventListener('click',e=>{if(e.target===d){const r=d.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)d.close();}}));
async function init(){
  try{
    const config=await api('/api/status');state.models=config.models;fillModels();$('model').value=config.recommended_model;modelInfo();
    if(!config.supported)error('Для локальной AI-обработки нужен Mac с чипом Apple (M1 или новее).');
    await refreshHistory();
    if(config.active_job){await openJob(config.active_job,true);return;}
    let saved;try{saved=JSON.parse(localStorage.getItem('salini-session'));}catch{}
    if(saved?.upload){try{if(saved.job&&saved.after){await openJob(saved.job);return;}await acceptUpload(saved.upload);if(saved.crop){state.crop=saved.crop;await showImages();remember();}}catch{localStorage.removeItem('salini-session');}}
  }catch(e){error('Не удалось подключиться к приложению. Откройте «Запустить Salini.command» и обновите страницу.');}
}
init();
