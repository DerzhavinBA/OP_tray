const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../plugin/com.openproject.tray.sdPlugin/static/inspector.js'), 'utf8');
function inspector(context, initial) {
  const elements = {};
  for (const id of ['logo','marker','exe','logoValue','markerValue','reset','connection','iconStyle','position','glow','radius','glowValue','radiusValue','previewLogo','previewMarker']) elements[id] = {value:'',textContent:'',style:{},events:{},addEventListener(name,handler){this.events[name]=handler;}};
  let ws;
  class FakeSocket {
    static OPEN = 1;
    constructor() { this.readyState = 1; this.messages = []; ws = this; }
    send(message) { this.messages.push(JSON.parse(message)); }
  }
  const sandbox = {document:{getElementById:id=>elements[id]},WebSocket:FakeSocket};
  vm.createContext(sandbox); vm.runInContext(source,sandbox);
  sandbox.connectElgatoStreamDeckSocket(1234,context,'registerPropertyInspector','{}',JSON.stringify({payload:{settings:initial}}));
  ws.onopen();
  return {elements,ws};
}
const a = inspector('a', {}), b = inspector('b',{logoSize:40,markerSize:10,custom:'preserved'});
assert.equal(a.elements.logo.value,85); assert.equal(a.elements.marker.value,20);
a.elements.logo.value='100'; a.elements.marker.value='35'; a.elements.logo.events.input();
assert.deepEqual(a.ws.messages.at(-1),{event:'setSettings',context:'a',payload:{logoSize:100,markerSize:35,exePath:'',iconStyle:'classic',markerPosition:'bottom-right',glow:0,cornerRadius:0}});
assert.equal(b.elements.logo.value,40); assert.equal(b.elements.marker.value,10);
b.elements.exe.value='C:\\Folder with spaces\\OpenProjectTray.exe'; b.elements.exe.events.change();
assert.equal(b.ws.messages.at(-1).payload.custom,'preserved');
a.elements.reset.events.click(); assert.equal(a.ws.messages.at(-1).payload.logoSize,85); assert.equal(a.ws.messages.at(-1).payload.markerSize,20);
const reopened=inspector('b',b.ws.messages.at(-1).payload); assert.equal(reopened.elements.logo.value,40); assert.equal(reopened.elements.exe.value,b.elements.exe.value);
b.ws.onmessage({data:JSON.stringify({event:'didReceiveSettings',payload:{settings:{logoSize:30,markerSize:8}}})});
assert.equal(b.elements.logo.value,30); assert.equal(b.elements.marker.value,8);
console.log('PASS inspector: defaults, live updates, independent buttons, reset, persisted settings, path');
a.elements.iconStyle.value='orbit';a.elements.position.value='top-left';a.elements.glow.value='70';a.elements.radius.value='25';a.elements.iconStyle.events.change();
const styled=inspector('a',a.ws.messages.at(-1).payload);
assert.equal(styled.elements.iconStyle.value,'orbit');assert.equal(styled.elements.position.value,'top-left');assert.equal(styled.elements.glow.value,70);assert.equal(styled.elements.radius.value,25);
assert.equal(styled.elements.previewMarker.style.left,'4%');assert.equal(styled.elements.previewMarker.style.top,'4%');
console.log('PASS inspector: icon, marker corner, glow and rounding persist');
