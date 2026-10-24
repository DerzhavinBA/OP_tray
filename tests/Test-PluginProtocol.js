// Real plugin EXE + fake StreamDock WebSocket + isolated controller. No WSL.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const {spawn,execFileSync}=require('node:child_process');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const sandbox=path.join(root,'build/obj/protocol-'+crypto.randomUUID());
const plugin=path.join(sandbox,'plugin');
// Optional package path verifies an already installed plugin in the same isolated fixture.
const packageSource=process.argv[2]||path.join(root,'dist/OpenProjectTray-portable/plugin/com.openproject.tray.sdPlugin');
fs.cpSync(packageSource,plugin,{recursive:true});
const bridge=fs.readFileSync(path.join(root,'src/Bridge.cs'),'utf8').replace('"OpenProjectTray." + WindowsIdentity.GetCurrent().User.Value',JSON.stringify('OpenProjectTray.Test.'+crypto.randomUUID()));
fs.writeFileSync(path.join(sandbox,'Bridge.cs'),bridge);
fs.writeFileSync(path.join(plugin,'connection.json'),JSON.stringify({exePath:path.join(sandbox,'MockLauncher.exe')}));
const csc=path.join(process.env.WINDIR,'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
execFileSync(csc,['/nologo','/target:library','/out:'+path.join(plugin,'bin/OpenProjectTray.Shared.dll'),'/r:System.Drawing.dll','/r:System.Web.Extensions.dll',path.join(sandbox,'Bridge.cs'),path.join(root,'src/PluginSupport.cs')],{windowsHide:true});
execFileSync(csc,['/nologo','/target:exe','/out:'+path.join(sandbox,'PluginHost.exe'),'/r:System.Web.Extensions.dll',path.join(sandbox,'Bridge.cs'),path.join(__dirname,'PluginHost.cs')],{windowsHide:true});
execFileSync(csc,['/nologo','/target:winexe','/out:'+path.join(sandbox,'MockLauncher.exe'),'/r:System.Web.Extensions.dll',path.join(sandbox,'Bridge.cs'),path.join(__dirname,'MockLauncher.cs')],{windowsHide:true});
let host,child,wire,buffer=Buffer.alloc(0),connections=0;
const received=[],hostLines=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(fn,label,ms=12000){const deadline=Date.now()+ms;while(Date.now()<deadline){const result=fn();if(result)return result;await delay(30);}throw new Error('Timeout: '+label);}
function send(value){const body=Buffer.from(JSON.stringify(value));let header;if(body.length<126)header=Buffer.from([0x81,body.length]);else{header=Buffer.alloc(4);header[0]=0x81;header[1]=126;header.writeUInt16BE(body.length,2);}wire.write(Buffer.concat([header,body]));}
function parse(chunk){buffer=Buffer.concat([buffer,chunk]);while(buffer.length>=2){let len=buffer[1]&127,offset=2;const masked=!!(buffer[1]&128);if(len===126){if(buffer.length<4)return;len=buffer.readUInt16BE(2);offset=4;}else if(len===127){if(buffer.length<10)return;len=Number(buffer.readBigUInt64BE(2));offset=10;}if(buffer.length<offset+(masked?4:0)+len)return;let mask;if(masked){mask=buffer.subarray(offset,offset+4);offset+=4;}const data=Buffer.from(buffer.subarray(offset,offset+len));if(masked)for(let i=0;i<data.length;i++)data[i]^=mask[i%4];const opcode=buffer[0]&15;buffer=buffer.subarray(offset+len);if(opcode===1)received.push(JSON.parse(data.toString()));}}
const server=http.createServer();
server.on('upgrade',(req,socket)=>{const accept=crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');wire=socket;buffer=Buffer.alloc(0);connections++;socket.on('data',parse);socket.on('error',()=>{});});
function appear(context,logoSize,markerSize){send({event:'willAppear',context,payload:{settings:{logoSize,markerSize}}});}
function latest(context){return received.filter(x=>x.event==='setImage'&&x.context===context).at(-1)?.payload.image;}
async function publish(state){host.stdin.write(state+'\n');await until(()=>hostLines.includes('published:'+state),'publish '+state);}
(async()=>{
 try{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  host=spawn(path.join(sandbox,'PluginHost.exe'),[],{windowsHide:true});
  host.stdout.on('data',data=>hostLines.push(...data.toString().trim().split(/\r?\n/)));
  await until(()=>hostLines.includes('ready'),'host ready');
  child=spawn(path.join(plugin,'bin/OpenProjectPlugin.exe'),['-port',String(server.address().port),'-pluginUUID','fixture','-registerEvent','registerPlugin','-info','{}'],{windowsHide:true});
  await until(()=>received.find(x=>x.event==='registerPlugin'&&x.uuid==='fixture'),'registration');
  appear('a',85,20);appear('b',30,8);
  await until(()=>latest('a')&&latest('b'),'initial images');
  await delay(1400);
  const a=latest('a'),b=latest('b');assert.notEqual(a,b);
  send({event:'didReceiveSettings',context:'a',payload:{settings:{logoSize:100,markerSize:35}}});
  await until(()=>latest('a')!==a,'live size change');assert.equal(latest('b'),b);
  console.log('PASS real plugin: registration, two buttons, independent live sizes');
  const animStart=received.length;
  send({event:'didReceiveSettings',context:'a',payload:{settings:{iconStyle:'orbit',markerPosition:'top-left',glow:80,cornerRadius:30}}});
  await delay(750);
  assert.ok(new Set(received.slice(animStart).filter(x=>x.event==='setImage'&&x.context==='a').map(x=>x.payload.image)).size>=3);
  assert.equal(latest('b'),b);
  send({event:'willDisappear',context:'a',payload:{}});
  await delay(250);
  const hiddenFrames=received.filter(x=>x.event==='setImage'&&x.context==='a').length;
  send({event:'didReceiveSettings',context:'a',payload:{settings:{iconStyle:'orbit'}}});
  await delay(500);
  assert.equal(received.filter(x=>x.event==='setImage'&&x.context==='a').length,hiddenFrames);
  appear('a',100,35);
  send({event:'didReceiveSettings',context:'a',payload:{settings:{logoSize:100,markerSize:35}}});
  await delay(300);
  console.log('PASS real plugin: animation frames on selected button only');
  send({event:'keyDown',context:'a',payload:{}});send({event:'keyDown',context:'b',payload:{}});
  await until(()=>hostLines.includes('activate'),'activation');await delay(1500);
  assert.equal(hostLines.filter(x=>x==='activate').length,1);
  const yellow=latest('a');await publish('ErrorBusy');
  await until(()=>latest('a')!==yellow,'error overrides busy');
  console.log('PASS real plugin: activate once, busy guard, error color');
  await publish('Running');const red=latest('a');await until(()=>latest('a')!==red,'running color');
  const green=latest('a');
  host.stdin.write('exit\n');await until(()=>host.exitCode!==null,'host exit');
  await until(()=>latest('a')!==green,'connection loss clears green');
  await delay(2200);assert.equal(fs.existsSync(path.join(sandbox,'launched')),false);
  console.log('PASS real plugin: closed application stays closed');
  send({event:'keyDown',context:'a',payload:{}});
  await until(()=>fs.existsSync(path.join(sandbox,'launched')),'launch on black button');
  await delay(2500);
  assert.equal(fs.readFileSync(path.join(sandbox,'launched'),'utf8'),'--background');
  assert.equal(fs.existsSync(path.join(sandbox,'launch-activations')),false);
  console.log('PASS real plugin: first offline click launches only application');
  send({event:'keyDown',context:'b',payload:{}});
  await until(()=>fs.existsSync(path.join(sandbox,'launch-activations')),'second click activates');
  assert.equal(fs.readFileSync(path.join(sandbox,'launch-activations'),'utf8'),'activate\n');
  const previous=connections;wire.destroy();await until(()=>connections>previous,'reconnection');
  appear('a',100,35);await delay(400);assert.equal(hostLines.filter(x=>x==='activate').length,1);
  console.log('PASS real plugin: reconnect without repeating migration');
 }finally{fs.writeFileSync(path.join(sandbox,'exit-launcher'),'yes');if(child)child.kill();if(host&&host.exitCode===null)host.kill();if(wire)wire.destroy();server.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
