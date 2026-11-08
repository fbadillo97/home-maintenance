const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('passkeys.js','utf8');
function environment({supported=true}={}){
 const nodes=new Map(),calls=[],events=new Map();let nativeError=null,held=null,resolveHeld,accepted=0,generation=0;
 function el(id){if(!nodes.has(id))nodes.set(id,{textContent:'',disabled:false,hidden:false,open:false,children:[],classList:{toggle(){}},replaceChildren(){this.children=[];},append(...children){this.children.push(...children);},showModal(){this.open=true;},close(){this.open=false;events.get(id+':close')?.();},addEventListener:(name,fn)=>events.set(id+':'+name,fn)});return nodes.get(id);}
 const buffer=values=>new Uint8Array(values).buffer;
 const credential={id:'synthetic-credential',rawId:buffer([4,5,6]),type:'public-key',getClientExtensionResults:()=>({}),response:{clientDataJSON:buffer([1,2,3]),attestationObject:buffer([7,8]),authenticatorData:buffer([9]),signature:buffer([10]),userHandle:buffer([11]),getTransports:()=>['internal']}};
 const native=async options=>{calls.push({native:options});if(nativeError)throw nativeError;if(held){const h=held;held=null;await h;}return credential;};
 const window={isSecureContext:true,PublicKeyCredential:supported?function(){}:null,confirm:text=>{calls.push({confirm:text});return true;}};
 const navigator={credentials:{create:native,get:native}};
 const context=vm.createContext({window,navigator,document:{querySelector:el,createElement:()=>({children:[],append(...x){this.children.push(...x);}})},AbortController,Uint8Array,ArrayBuffer,atob:v=>Buffer.from(v,'base64').toString('binary'),btoa:v=>Buffer.from(v,'binary').toString('base64'),String,Boolean,Error});
 vm.runInContext(source,context);
 const bridge={ready:()=>true,getGeneration:()=>generation,notify:text=>calls.push({notice:text}),acceptSession:async()=>{accepted++;return true;},request:async(path,body,auth,method)=>{calls.push({path,body,auth,method});if(path.endsWith('/options'))return {challenge_id:'synthetic-challenge',options:{challenge:'AQID',rpId:'fbadillo97.github.io',rp:{id:'fbadillo97.github.io',name:'Fixture'},user:{id:'BAUG',name:'fixture@example.invalid',displayName:'Fixture'},pubKeyCredParams:[{type:'public-key',alg:-7}]}};if(path.endsWith('/registration/verify'))return {id:'synthetic-key'};if(path.endsWith('/authentication/verify'))return {access_token:'synthetic-access',refresh_token:'synthetic-refresh',expires_in:3600};if(method==='DELETE')return {};return {passkeys:[{id:'synthetic-key',friendly_name:'Fixture manager'}]};}};
 const api=window.homePasskeys;api.init(bridge);
 return {api,el,calls,accepted:()=>accepted,error:value=>{nativeError=value;},hold(){held=new Promise(resolve=>{resolveHeld=resolve;});},release:()=>resolveHeld?.(),settle:async()=>{for(let i=0;i<4;i++)await new Promise(resolve=>setImmediate(resolve));}};
}
(async()=>{
 let env=environment();await env.el('#passkey-create').onclick();assert.ok(env.el('#passkey-message').textContent.includes('Sign in'));assert.equal(env.calls.length,0);
 env.api.sync(true);await env.el('#passkey-create').onclick();let request=env.calls.find(c=>c.path?.endsWith('/registration/verify'));assert.equal(request.auth,true);assert.equal(request.body.challenge_id,'synthetic-challenge');assert.equal(request.body.credential.response.clientDataJSON,'AQID');assert.equal(request.body.credential.response.attestationObject,'Bwg');assert.equal(env.accepted(),0);
 const native=env.calls.find(c=>c.native).native;assert.deepEqual([...new Uint8Array(native.publicKey.challenge)],[1,2,3]);assert.deepEqual([...new Uint8Array(native.publicKey.user.id)],[4,5,6]);
 env.el('#manage-passkeys').onclick();await env.settle();const row=env.el('#passkey-list').children[0];await row.children[1].onclick();assert.ok(env.calls.some(c=>c.method==='DELETE'&&c.auth===true));assert.ok(env.calls.some(c=>c.confirm?.includes('wishlist')));
 env=environment();await env.el('#passkey-signin').onclick();request=env.calls.find(c=>c.path?.endsWith('/authentication/verify'));assert.equal(request.auth,false);assert.equal(request.body.credential.response.authenticatorData,'CQ');assert.equal(request.body.credential.response.signature,'Cg');assert.equal(env.accepted(),1);
 env=environment();env.error({name:'NotAllowedError'});await env.el('#passkey-signin').onclick();assert.ok(env.el('#passkey-signin-message').textContent.includes('cancelled'));assert.ok(!env.calls.some(c=>c.path?.endsWith('/verify')));
 env=environment();env.hold();const pending=env.el('#passkey-signin').onclick();await env.settle();env.api.clear();env.release();await pending;assert.ok(!env.calls.some(c=>c.path?.endsWith('/verify')),'Cancelled operation verified a credential');assert.equal(env.accepted(),0);
 env=environment({supported:false});assert.equal(env.el('#passkey-signin').disabled,true);assert.ok(env.el('#passkey-signin-message').textContent.includes('email'));
 console.log('PASS passkeys: approved enrollment, binary challenge/credential conversion, authenticated listing/removal, shared-account warning, sign-in, cancellation, stale-operation rejection and unsupported-browser email fallback.');
})().catch(error=>{console.error(error);process.exitCode=1;});
