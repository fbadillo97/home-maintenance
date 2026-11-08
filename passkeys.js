// Native WebAuthn adapter for Supabase Auth's two-step passkey endpoints.
(() => {
 const $=s=>document.querySelector(s);
 let api,allowed=false,pending=false,operation=0,controller=null;
 const supported=()=>Boolean(window.isSecureContext&&window.PublicKeyCredential&&navigator.credentials?.create&&navigator.credentials?.get);
 const text=(value,error=false)=>{for(const id of ['#passkey-message','#passkey-signin-message']){const el=$(id);if(el){el.textContent=value;el.classList.toggle('error',error);}}if(value)api?.notify?.(value,error);};
 function controls(){const available=supported();$('#passkey-signin').disabled=pending;$('#passkey-create').disabled=pending||!allowed;$('#passkey-refresh').disabled=pending||!allowed;}
 function cancel(){operation++;controller?.abort();controller=null;pending=false;controls();}
 function clear(){cancel();allowed=false;$('#passkey-list').replaceChildren();text('');const d=$('#passkey-dialog');if(d.open)d.close();controls();}
 function sync(isAuthorized){allowed=isAuthorized;$('#manage-passkeys').hidden=!allowed;controls();if(!supported())$('#passkey-signin-message').textContent='Passkeys are unavailable in this browser. You can still sign in by email.';}
 const decode=value=>{const raw=value.replace(/-/g,'+').replace(/_/g,'/');const binary=atob(raw+'='.repeat((4-raw.length%4)%4));return Uint8Array.from(binary,c=>c.charCodeAt(0)).buffer;};
 const encode=value=>{const bytes=new Uint8Array(value);let binary='';for(const byte of bytes)binary+=String.fromCharCode(byte);return btoa(binary).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/g,'');};
 function parseOptions(json,registration){
  const native=registration?'parseCreationOptionsFromJSON':'parseRequestOptionsFromJSON';
  if(typeof window.PublicKeyCredential[native]==='function')return window.PublicKeyCredential[native](json);
  const options={...json,challenge:decode(json.challenge)};
  if(registration)options.user={...json.user,id:decode(json.user.id)};
  for(const field of ['excludeCredentials','allowCredentials'])if(json[field])options[field]=json[field].map(item=>({...item,id:decode(item.id)}));
  return options;
 }
 function serialize(credential,registration){
  if(typeof credential.toJSON==='function')return credential.toJSON();
  const response={clientDataJSON:encode(credential.response.clientDataJSON)};
  if(registration){response.attestationObject=encode(credential.response.attestationObject);if(credential.response.getTransports)response.transports=credential.response.getTransports();}
  else {for(const field of ['authenticatorData','signature'])response[field]=encode(credential.response[field]);if(credential.response.userHandle)response.userHandle=encode(credential.response.userHandle);}
  return {id:credential.id,rawId:encode(credential.rawId),type:credential.type,response,clientExtensionResults:credential.getClientExtensionResults(),...(credential.authenticatorAttachment?{authenticatorAttachment:credential.authenticatorAttachment}:{})};
 }
 function reason(error){
  if(error.name==='NotAllowedError')return 'The passkey prompt was cancelled, timed out, or no matching passkey was available. Try again or use email.';
  if(error.name==='AbortError')return 'Passkey request cancelled.';
  if(error.name==='InvalidStateError')return 'This device or password manager may already have a passkey for this account.';
  if(error.name==='SecurityError')return 'The passkey website address did not match. Open the live maintenance site in your browser and check the Supabase passkey domain settings.';
  if(error.name==='NotSupportedError')return 'This browser or device cannot use the requested passkey. Use email sign-in instead.';
  return error.message||'Passkey request failed. Email sign-in is still available.';
 }
 async function run(registration){
  if(pending)return;
  if(!supported()){text('Passkeys are unavailable in this browser. Open this page in your normal browser, or sign in by email.',true);return;}
  if(!api.ready()){text('The page is still loading. Please wait a moment and try again.',true);return;}
  if(registration&&!allowed){text('Sign in with your approved home account before creating a passkey.',true);return;}
  const id=++operation,version=api.getGeneration();pending=true;controller=new AbortController();controls();
  text(registration?'Preparing your new passkey…':'Looking for your passkey…');
  try{
   const phase=registration?'registration':'authentication';
   const options=await api.request('/auth/v1/passkeys/'+phase+'/options',{},registration);
   if(id!==operation||version!==api.getGeneration())return;
   if(!options?.challenge_id||!options?.options)throw Error('The passkey service returned an unexpected response. Email sign-in remains available.');
   const publicKey=parseOptions(options.options,registration);
   text(registration?'Confirm creating the passkey on your device.':'Confirm sign-in on your device.');
   const credential=await navigator.credentials[registration?'create':'get']({publicKey,signal:controller.signal});
   if(id!==operation||version!==api.getGeneration())return;
   if(!credential)throw Error('No passkey was returned by the device. Try again or use email.');
   const verified=await api.request('/auth/v1/passkeys/'+phase+'/verify',{challenge_id:options.challenge_id,credential:serialize(credential,registration)},registration);
   if(id!==operation||version!==api.getGeneration())return;
   if(registration){text('Passkey created. Next time you can sign in with it.');pending=false;controls();await listKeys();text('Passkey created. Next time you can sign in with it.');}
   else{
    const accepted=await api.acceptSession(verified);
    if(id!==operation)return;
    pending=false;controller=null;controls();
    
    if(accepted)api.notify('Signed in with your passkey.');
   }
  }catch(error){if(id===operation)text(reason(error),true);}
  finally{if(id===operation){pending=false;controller=null;controls();}}
 }
 async function listKeys(){
  if(!allowed||pending)return;
  const id=operation,version=api.getGeneration();$('#passkey-list').replaceChildren();text('Loading your passkeys…');
  try{
   const result=await api.request('/auth/v1/passkeys',undefined,true,'GET');
   if(id!==operation||version!==api.getGeneration()||!allowed)return;
   const keys=Array.isArray(result)?result:result?.passkeys;
   if(!Array.isArray(keys))throw Error('The passkey list could not be read. Try Refresh.');
   for(const key of keys){
    const row=document.createElement('div');row.className='management-row';
    const name=document.createElement('span');name.textContent=key.friendly_name||'Saved passkey';
    const remove=document.createElement('button');remove.type='button';remove.textContent='Remove';
    remove.onclick=async()=>{
     if(pending||!allowed)return;
     if(!window.confirm('Remove this passkey from your shared family account? It will also stop working for the wishlist. Email sign-in remains available.'))return;
     const runId=++operation,initialGeneration=api.getGeneration();pending=true;controls();remove.disabled=true;
     try{await api.request('/auth/v1/passkeys/'+encodeURIComponent(key.id),undefined,true,'DELETE');if(runId!==operation||initialGeneration!==api.getGeneration())return;pending=false;controls();await listKeys();text('Passkey removed from this account. You can remove its saved copy from your password manager separately.');}
     catch(error){if(runId===operation)text(reason(error),true);}
     finally{if(runId===operation){pending=false;controls();remove.disabled=false;}}
    };
    row.append(name,remove);$('#passkey-list').append(row);
   }
   text(keys.length?'Your passkeys are listed below.':'No passkeys yet. Choose Create passkey to add one.');
  }catch(error){if(id===operation&&version===api.getGeneration())text(reason(error),true);}
 }
 function init(bridge){
  api=bridge;$('#passkey-signin').onclick=()=>run(false);$('#passkey-create').onclick=()=>run(true);$('#passkey-refresh').onclick=listKeys;
  $('#manage-passkeys').onclick=()=>{if(!allowed)return;$('#passkey-dialog').showModal();listKeys();};
  $('#close-passkeys').onclick=()=>$('#passkey-dialog').close();
  $('#passkey-dialog').addEventListener('close',cancel);
  sync(false);
 }
 window.homePasskeys={init,sync,clear};
})();
