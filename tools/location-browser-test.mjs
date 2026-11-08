// Only run against the isolated Chrome test profile on port 9225.
// These are simulated test coordinates, never a fallback in the application.
import assert from 'node:assert/strict';
import fs from 'node:fs';
const origin='http://localhost:3000';
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const tab=await(await fetch('http://localhost:9225/json/new?about:blank',{method:'PUT'})).json();
const ws=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
let sequence=0;const pending=new Map(),exceptions=[];
ws.onmessage=event=>{const m=JSON.parse(event.data);if(m.id){const p=pending.get(m.id);if(!p)return;clearTimeout(p.timer);pending.delete(m.id);if(m.error)p.reject(m.error);else p.resolve(m.result);}else if(m.method==='Runtime.exceptionThrown')exceptions.push(m.params);};
const command=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(Error(`${method} timed out`));},20000);pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params}));});
const evaluate=async expression=>{const r=await command('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true,userGesture:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.text);return r.result.value;};
const labels=()=>evaluate("Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join('\\n')+' '+document.body.innerText");
async function waitFor(check,message){for(let i=0;i<30;i++){if(await check())return;await pause(500);}throw Error(message);}
async function click(label,fallback){
  const point=await evaluate(`(()=>{const items=Array.from(document.querySelectorAll('[aria-label],[role="button"],flt-semantics')).filter(e=>e.getAttribute('aria-label')===${JSON.stringify(label)}||e.textContent.trim()===${JSON.stringify(label)});const e=items.filter(e=>{const r=e.getBoundingClientRect();return r.width&&r.height;}).at(-1);if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
  assert.ok(point||fallback,`Control not found: ${label}`);const p=point??fallback;
  await command('Input.dispatchMouseEvent',{type:'mousePressed',...p,button:'left',clickCount:1});
  await command('Input.dispatchMouseEvent',{type:'mouseReleased',...p,button:'left',clickCount:1});
}
try{
  await command('Page.enable');await command('Runtime.enable');await command('Network.enable');
  await command('Network.clearBrowserCache');
  await command('Emulation.setDeviceMetricsOverride',{width:1100,height:850,deviceScaleFactor:1,mobile:false});
  await command('Browser.setPermission',{permission:{name:'geolocation'},setting:'granted',origin});
  await command('Emulation.setGeolocationOverride',{latitude:14.5995,longitude:120.9842,accuracy:25});
  await command('Page.navigate',{url:origin});
  await waitFor(()=>evaluate("!!document.querySelector('flutter-view')"),'Flutter did not initialize');
  await pause(7000);
  await evaluate("document.querySelector('flt-semantics-placeholder')?.click()");
  await pause(700);
  await click('Map',{x:496,y:788});await pause(1000);
  await click('Use my location',{x:729,y:319});
  await waitFor(async()=>(await labels()).includes('Your current location'),'The app did not show the granted location');
  const granted=await command('Page.captureScreenshot',{format:'png'});fs.mkdirSync('artifacts',{recursive:true});fs.writeFileSync('artifacts/location-granted.png',Buffer.from(granted.data,'base64'));
  await command('Browser.setPermission',{permission:{name:'geolocation'},setting:'denied',origin});
  await click('Use my location',{x:729,y:319});
  await waitFor(async()=>(await labels()).includes('Location access is blocked'),'A blocked browser permission did not show recovery guidance');
  assert.match(await labels(),/Try again/);
  await command('Browser.setPermission',{permission:{name:'geolocation'},setting:'granted',origin});
  await click('Try again');
  await waitFor(async()=>!(await labels()).includes('Location access is blocked'),'Location retry did not recover');
  assert.match(await labels(),/Your current location/);assert.equal(exceptions.length,0);
  const result={granted:true,denied:true,retry:true,runtimeExceptions:exceptions.length,simulatedCoordinates:{latitude:14.5995,longitude:120.9842}};
  fs.writeFileSync('artifacts/location-browser.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){fs.mkdirSync('artifacts',{recursive:true});fs.writeFileSync('artifacts/location-browser-failure.json',JSON.stringify({error:String(error),labels:await labels().catch(()=>''),exceptions},null,2));throw error;}
finally{ws.close();}
