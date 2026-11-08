import fs from 'node:fs';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const tab=await(await fetch('http://localhost:9225/json/new?about:blank',{method:'PUT'})).json();
if(!tab)throw Error('No isolated browser tab found');
const ws=new WebSocket(tab.webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
let sequence=0;const pending=new Map(),events=[];
ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);if(m.error)p.reject(m.error);else p.resolve(m.result);}else if(['Runtime.exceptionThrown','Network.loadingFailed','Log.entryAdded'].includes(m.method)||(m.method==='Runtime.consoleAPICalled'&&m.params.type==='error')){events.push(m);}};
const command=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
await command('Page.enable');await command('Runtime.enable');await command('Network.enable');await command('Log.enable');
await command('Network.clearBrowserCache');
await command('Emulation.setDeviceMetricsOverride',{width:1100,height:850,deviceScaleFactor:1,mobile:false});
await command('Page.navigate',{url:'http://localhost:3000/'});
let ready=false;
for(let i=0;i<35;i++){await sleep(1000);const r=await command('Runtime.evaluate',{expression:"!!document.querySelector('flutter-view, flt-glass-pane')",returnByValue:true});if(r.result.value){ready=true;break;}}
await sleep(8000);
const mapMode=process.argv.includes('--map');
if(mapMode){
  await command('Input.dispatchMouseEvent',{type:'mousePressed',x:496,y:788,button:'left',clickCount:1});
  await command('Input.dispatchMouseEvent',{type:'mouseReleased',x:496,y:788,button:'left',clickCount:1});
  await sleep(6000);
}
const dom=await command('Runtime.evaluate',{expression:'document.body.innerHTML.slice(0,2500)',returnByValue:true});
const screenshot=await command('Page.captureScreenshot',{format:'png'});fs.mkdirSync('artifacts',{recursive:true});fs.writeFileSync(mapMode?'artifacts/map-browser.png':'artifacts/browser-preview.png',Buffer.from(screenshot.data,'base64'));
const errors=events.filter(e=>e.method==='Runtime.exceptionThrown'||e.method==='Runtime.consoleAPICalled'||(e.method==='Log.entryAdded'&&e.params.entry.level==='error')).length;
fs.writeFileSync('artifacts/browser-smoke.json',JSON.stringify({ready,errors,events,dom:dom.result.value},null,2));console.log(JSON.stringify({ready,errors,events:events.map(e=>e.params)}));
ws.close();if(!ready||errors>0)process.exitCode=1;
