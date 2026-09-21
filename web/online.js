// Runs only in the separate internet service, never in the desktop app.
window.saliniOnlineReady = (async () => {
  const fragment = new URLSearchParams(location.hash.slice(1));
  const invite = fragment.get('invite');
  const visitor = fragment.get('visitor') || '';
  history.replaceState(null, '', location.pathname);
  let shareURL = '';
  async function login(code) {
    const response = await fetch('/api/session', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({invite:code,visitor})});
    if (!response.ok) throw new Error((await response.json()).detail || 'Не удалось подключиться.');
  }
  async function session() {
    const response = await fetch('/api/session');
    if (!response.ok) throw new Error('Откройте полную ссылку-приглашение от владельца студии.');
    shareURL = (await response.json()).share_url;
  }
  try {
    if (invite) await login(invite);
    await session();
  } catch (initialError) {
    await new Promise(resolve => {
      const dialog = document.createElement('dialog');
      dialog.className = 'invite-dialog';
      dialog.innerHTML = '<p class="eyebrow">SALINI · ВЕБ-СТУДИЯ</p><h2>Вход по приглашению</h2><p>Изображения обрабатываются и сохраняются на Mac владельца сайта. Для входа откройте его полную ссылку или введите код доступа.</p><form><label class="field-label" for="invite-code">Код доступа</label><input id="invite-code" type="password" autocomplete="off" required maxlength="100"><p class="hint" role="alert"></p><button class="primary full" type="submit">Открыть студию</button></form>';
      document.body.append(dialog);dialog.showModal();
      dialog.addEventListener('cancel',event=>event.preventDefault());
      const message=dialog.querySelector('[role=alert]');message.textContent=initialError.message;
      dialog.querySelector('form').onsubmit=async event=>{
        event.preventDefault();const button=dialog.querySelector('button');button.disabled=true;
        try {await login(dialog.querySelector('input').value.trim());await session();dialog.close();dialog.remove();resolve();}
        catch(error){message.textContent=error.message;}
        finally{button.disabled=false;}
      };
    });
  }
  const copy = document.createElement('button');copy.className='text-button';copy.textContent='Ссылка на студию';
  copy.onclick=async()=>{
    try{await navigator.clipboard.writeText(shareURL);copy.textContent='Ссылка скопирована';setTimeout(()=>copy.textContent='Ссылка на студию',2500);}
    catch{const box=document.createElement('dialog');const text=document.createElement('textarea');text.value=shareURL;box.append(text);document.body.append(box);box.showModal();text.select();box.addEventListener('cancel',()=>box.remove());}
  };
  document.querySelector('.header-right').prepend(copy);
  document.querySelector('#about h2').textContent='Студия в браузере. Обработка на Mac.';
  const paragraphs=document.querySelectorAll('#about p:not(.eyebrow)');
  paragraphs[0].textContent='Устанавливать программу не нужно. Исходные изображения и результаты хранятся на Mac владельца сайта; он имеет к ним доступ. Передавайте ссылку-приглашение только тем, кому хотите разрешить обработку.';
  paragraphs[1].textContent='Ваш браузер показывает только вашу историю. Сайт выполняет задания по очереди, пока Mac владельца включён, не спит и подключён к интернету.';
  return true;
})();
