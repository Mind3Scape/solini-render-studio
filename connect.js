const statusText=document.getElementById('status'),detail=document.getElementById('detail'),retry=document.getElementById('retry'),openLink=document.getElementById('open');
const invite=new URLSearchParams(location.hash.slice(1)).get('invite')||'';
// This private visitor key stays in this browser. Shared links contain only the invitation.
let visitor;
try{visitor=localStorage.getItem('salini-visitor-key');}catch{}
if(!visitor){visitor=btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');try{localStorage.setItem('salini-visitor-key',visitor);}catch{}}
let checking=false,timer;
async function connect(){
  if(checking)return;checking=true;retry.disabled=true;openLink.hidden=true;clearTimeout(timer);
  try{
    const config=await fetch('./connection.json?v='+Date.now(),{cache:'no-store',signal:AbortSignal.timeout(6000)}).then(r=>{if(!r.ok)throw Error();return r.json();});
    const url=new URL(config.url);
    if(url.protocol!=='https:'||!/^[-a-z0-9]+\.trycloudflare\.com$/.test(url.hostname)||url.pathname!=='/'||url.port||url.username||url.password)throw Error();
    const health=await fetch(new URL('/health',url),{credentials:'omit',cache:'no-store',signal:AbortSignal.timeout(7000)}).then(r=>{if(!r.ok)throw Error();return r.json();});
    if(health.app!=='salini-online'||!health.online)throw Error();
    url.hash=new URLSearchParams({invite,visitor}).toString();
    statusText.textContent='Студия готова';detail.textContent='Подключаемся к обработке на Mac…';document.getElementById('dot').style.background='#618a65';
    openLink.href=url.href;openLink.hidden=false;
    location.replace(url.href);
  }catch{
    statusText.textContent='Обработчик сейчас недоступен';detail.textContent='Mac владельца может быть выключен или спать. Повторим подключение через 30 секунд.';document.getElementById('dot').style.background='#b89d69';
    timer=setTimeout(connect,30000);
  }finally{checking=false;retry.disabled=false;}
}
retry.onclick=connect;connect();
