// Keep visible feedback available even if a later script fails to load or initialize.
(() => {
 const show=message=>{const el=document.querySelector('#feedback');if(el){el.textContent=message;el.classList.add('error');}};
 const waiting=()=>show('Passkey controls have not finished loading. Refresh this page; email sign-in remains available.');
 for(const id of ['manage-passkeys','passkey-signin','passkey-create','passkey-refresh']){const el=document.getElementById(id);if(el)el.onclick=waiting;}
 window.addEventListener('error',event=>{if(event.target?.tagName==='SCRIPT')show('Part of the page could not load. Refresh this page to load the updated controls.');else if(event.error)show('A page error stopped a control. Refresh the page and try again; email sign-in is still available.');},true);
})();
