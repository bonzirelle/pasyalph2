import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createPreviewServer} from './serve-preview.mjs';

test('Release preview serves Flutter assets, routes and health without debug dependencies',async()=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'pasyalph-preview-'));
  await fs.writeFile(path.join(root,'index.html'),'<title>PasyalPH</title>');
  await fs.writeFile(path.join(root,'main.dart.js'),'console.log("ready")');
  await fs.writeFile(path.join(root,'app.wasm'),new Uint8Array([0,97,115,109]));
  const server=createPreviewServer(root);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  try{
    const page=await fetch(base+'/settings');assert.equal(page.status,200);assert.equal(page.headers.get('permissions-policy'),'geolocation=(self)');assert.match(await page.text(),/PasyalPH/);
    const js=await fetch(base+'/main.dart.js');assert.equal(js.status,200);assert.match(js.headers.get('content-type'),/javascript/);assert.equal(js.headers.get('cache-control'),'no-store');
    assert.equal((await fetch(base+'/app.wasm')).headers.get('content-type'),'application/wasm');
    assert.equal((await fetch(base+'/missing.js')).status,404);
    assert.equal((await fetch(base,{method:'POST'})).status,405);
    assert.equal((await fetch(base+'/%2e%2e%5csecret.txt')).status,403);
    assert.equal((await fetch(base+'/%00')).status,400);
    assert.equal(await(await fetch(base+'/main.dart.js',{method:'HEAD'})).text(),'');
    assert.deepEqual(await(await fetch(base+'/__pasyalph_health')).json(),{app:'PasyalPH',mode:'release'});
  }finally{
    await new Promise(resolve=>server.close(resolve));
    const cleanupPath=path.resolve(root);
    if(path.dirname(cleanupPath)!==path.resolve(os.tmpdir())||!path.basename(cleanupPath).startsWith('pasyalph-preview-'))throw Error('Unexpected temporary test directory');
    await fs.rm(cleanupPath,{recursive:true,force:true});
  }
});
