import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.css':'text/css; charset=utf-8','.wasm':'application/wasm','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.svg':'image/svg+xml','.ico':'image/x-icon','.ttf':'font/ttf','.otf':'font/otf','.woff2':'font/woff2'};
export function createPreviewServer(directory){
  const root=path.resolve(directory);
  return http.createServer((req,res)=>{
    res.setHeader('Cache-Control','no-store');
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Permissions-Policy','geolocation=(self)');
    if(!['GET','HEAD'].includes(req.method)){res.writeHead(405,{'Allow':'GET, HEAD'});res.end();return;}
    let pathname;
    try{pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(pathname.includes('\0'))throw Error();}
    catch{res.writeHead(400);res.end('Invalid URL');return;}
    if(pathname==='/__pasyalph_health'){res.writeHead(200,{'Content-Type':'application/json'});res.end(req.method==='HEAD'?undefined:JSON.stringify({app:'PasyalPH',mode:'release'}));return;}
    let file=path.resolve(root,'.'+pathname);
    if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403);res.end('Forbidden');return;}
    if(file===root||!path.extname(file))file=path.join(root,'index.html');
    fs.stat(file,(error,stat)=>{
      if(error||!stat.isFile()){res.writeHead(404);res.end('Not found');return;}
      res.writeHead(200,{'Content-Type':types[path.extname(file).toLowerCase()]??'application/octet-stream','Content-Length':stat.size});
      if(req.method==='HEAD'){res.end();return;}
      const stream=fs.createReadStream(file);stream.on('error',()=>res.destroy());stream.pipe(res);
    });
  });
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  const root=fileURLToPath(new URL('../build/web/',import.meta.url));
  if(!fs.existsSync(path.join(root,'main.dart.js'))){console.error('Build the Flutter web app first.');process.exitCode=1;}
  else{const server=createPreviewServer(root);server.on('error',error=>{console.error(error.message);process.exitCode=1;});server.listen(3000,'127.0.0.1',()=>console.log('PasyalPH release preview: http://localhost:3000/'));}
}
