const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const code=fs.readFileSync('app.js','utf8');
const clone=v=>JSON.parse(JSON.stringify(v));
const sample={equipment:[{id:'fixture-equipment',name:'Synthetic appliance',manufacturer:'Fixture',category:'Kitchen',model:'A1',serial_number:'000123',notes:'<script>unsafe</script>',warranty_status:'unknown',evidence:{},revision:1}],tasks:[],task_equipment:[],history:[],history_equipment:[],attention:[{id:'fixture-attention',equipment_id:'fixture-equipment',question:'Synthetic follow-up',status:'open',resolution:'',revision:1}],documents:[],document_equipment:[]};
function environment({signedIn=true,allowed=true}={}){
 const nodes=new Map(),events=new Map(),storage=new Map(),calls=[],fixture=clone(sample);let formValues={},writeFailure=false,hold=null,release;
 const state={allowed,writeFailure,fixture,calls};
 function element(selector){if(!nodes.has(selector))nodes.set(selector,{value:'',innerHTML:'',textContent:'',hidden:false,disabled:false,inert:false,open:false,dataset:{},classList:{toggle(){}},querySelector:s=>element(selector+' '+s),addEventListener:(name,fn)=>events.set(selector+':'+name,fn),setAttribute(name,value){this[name]=value;},removeAttribute(name){delete this[name];},showModal(){this.open=true;},close(){this.open=false;},select(){},click(){}});return nodes.get(selector);}
 const pages=['home','equipment','record','schedule','history'].map(name=>{const el=element('page-'+name);el.dataset.page=name;return el;});
 const nav=['home','equipment','schedule','history'].map(name=>{const el=element('nav-'+name);el.hash='#'+name;return el;});
 if(signedIn)storage.set('badillo-session',JSON.stringify({access_token:'synthetic-access',refresh_token:'synthetic-refresh',expires_at:Date.now()/1000+10000,user:{email:'fixture@example.invalid'}}));
 const document={querySelector:element,querySelectorAll:selector=>selector==='[data-page]'?pages:selector==='nav a'?nav:[],createElement:tag=>element('created-'+tag),addEventListener:(name,fn)=>events.set('document:'+name,fn)};
 const window={addEventListener:(name,fn)=>events.set('window:'+name,fn),scrollTo(){}};
 const location={hash:'#home',href:'https://example.invalid/home-maintenance/',pathname:'/home-maintenance/',search:''};
 const fetch=async(url,options={})=>{
  calls.push({url,options});
  const good=body=>({ok:true,status:200,json:async()=>clone(body)});
  if(url==='config.json')return good({supabaseUrl:'https://backend.invalid',publishableKey:'synthetic-key'});
  if(url.includes('/auth/v1/user'))return good({id:'synthetic-user',email:'fixture@example.invalid'});
  if(url.endsWith('/rpc/home_access'))return good(state.allowed);
  if(url.endsWith('/rpc/home_save_equipment')){if(state.writeFailure)return {ok:false,status:409,json:async()=>({message:'Changed elsewhere. Reopen the latest record.',code:'40001'})};const p=JSON.parse(options.body);Object.assign(fixture.equipment[0],p.p_values);fixture.equipment[0].revision++;return good(fixture.equipment[0]);}
  if(url.includes('/rest/v1/home_')){if(hold){const h=hold;hold=null;await h;}const name=url.split('/rest/v1/home_')[1].split('?')[0];return good(fixture[name]||[]);}
  return good({});
 };
 const context=vm.createContext({fetch,console,document,window,location,URL,URLSearchParams,Blob,Date,Intl,AbortController,JSON,Math,Number,String,Object,Array,Set,Map,Promise,crypto:{randomUUID:()=> '77777777-7777-4777-8777-777777777777'},navigator:{clipboard:{writeText:async()=>{}}},history:{replaceState(){}},localStorage:{getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},FormData:class{constructor(){return Object.entries(formValues);}},setTimeout:()=>1,clearTimeout(){},queueMicrotask,atob:value=>Buffer.from(value,'base64').toString('binary')});
 vm.runInContext(code+';globalThis.testAPI={get:()=>data,isAllowed:()=>authorized,load,openEditor,openReview,render,acceptPasskeySession};',context);
 return {api:context.testAPI,element,state,calls,storage,events,settle:async()=>{for(let i=0;i<5;i++)await new Promise(resolve=>setImmediate(resolve));},form:values=>{formValues=values;},holdNextRead(){hold=new Promise(resolve=>{release=resolve;});},release:()=>release?.()};
}
(async()=>{
 let env=environment({signedIn:false});await env.settle();assert.equal(env.api.isAllowed(),false);assert.ok(!env.calls.some(c=>c.url.includes('/rest/v1/')),'Signed-out page requested private data');
 const passkeySession={access_token:'synthetic-passkey',refresh_token:'synthetic-refresh',expires_in:3600};
 await assert.rejects(()=>env.api.acceptPasskeySession({access_token:'incomplete'}));assert.equal(env.api.isAllowed(),false);
 assert.equal(await env.api.acceptPasskeySession(passkeySession),true);assert.equal(env.api.get().equipment.length,1);
 let denied=environment({signedIn:false,allowed:false});await denied.settle();assert.equal(await denied.api.acceptPasskeySession(passkeySession),false);assert.equal(denied.api.get().equipment.length,0);assert.ok(!denied.calls.some(c=>c.url.includes('/rest/v1/home_')));
 env=environment({allowed:false});await env.settle();assert.equal(env.api.isAllowed(),false);assert.ok(!env.calls.some(c=>c.url.includes('/rest/v1/home_')),'Unapproved page requested tables');
 env=environment();await env.settle();assert.equal(env.api.isAllowed(),true,env.element('#feedback').textContent);assert.equal(env.api.get().equipment.length,1);assert.equal(env.element('#application').hidden,false);
 env.api.openEditor('equipment','fixture-equipment');assert.equal(env.element('#editor').open,true);assert.ok(env.element('#editFields').innerHTML.includes('&lt;script&gt;unsafe&lt;/script&gt;'),'Text inserted as executable markup');
 env.form({name:'Edited fixture',serial_number:'000123',notes:'Unsaved form note',warranty_status:'unknown'});env.state.writeFailure=true;await env.element('#editForm').onsubmit({preventDefault(){},target:{}});assert.equal(env.element('#editor').open,true);assert.ok(env.element('#editError').textContent.includes('Changed elsewhere'));assert.equal(env.api.get().equipment[0].name,'Synthetic appliance');
 env.state.writeFailure=false;await env.element('#editForm').onsubmit({preventDefault(){},target:{}});assert.equal(env.element('#editor').open,false);assert.equal(env.api.get().equipment[0].name,'Edited fixture');assert.equal(env.api.get().equipment[0].serial_number,'000123');
 const writesBefore=env.calls.filter(c=>c.url.endsWith('/rpc/home_save_equipment')).length;env.api.openReview('fixture-attention');env.element('#rough').value='rough fixture response';env.element('#prepareReview').onclick();assert.ok(env.element('#reviewText').value.includes('rough fixture response'));assert.ok(env.element('#reviewText').value.includes('Do not apply changes yet'));assert.equal(env.calls.filter(c=>c.url.endsWith('/rpc/home_save_equipment')).length,writesBefore);assert.deepEqual([...env.storage.keys()],['badillo-session']);
 env.holdNextRead();const reload=env.api.load();await env.settle();await env.element('#logout').onclick();assert.equal(env.api.isAllowed(),false);assert.equal(env.api.get().equipment.length,0);assert.equal(env.element('#review').open,false);assert.equal(env.element('#reviewText').value,'');env.release();await reload;await env.settle();assert.equal(env.api.get().equipment.length,0,'Late response restored private records');assert.equal(env.element('#application').hidden,true);
 console.log('PASS: signed-out/unapproved no-data paths, approved loading, safe text, form conflict retention, saved reload, serial zeros, review isolation, auth-only storage, sign-out cleanup and delayed-response rejection.');
})().catch(error=>{console.error(error);process.exitCode=1;});
