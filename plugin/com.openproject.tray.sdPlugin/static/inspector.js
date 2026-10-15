'use strict';
let socket, inspectorId, settings = {};
const byId = id => document.getElementById(id);
function refresh() {
  byId('logo').value = settings.logoSize ?? 85;
  byId('marker').value = settings.markerSize ?? 20;
  byId('exe').value = settings.exePath || '';
  byId('iconStyle').value = settings.iconStyle || 'classic';
  byId('position').value = settings.markerPosition || 'bottom-right';
  byId('glow').value = settings.glow ?? 0;
  byId('radius').value = settings.cornerRadius ?? 0;
  labels();
}
function labels() {
  byId('logoValue').textContent = byId('logo').value + '%';
  byId('markerValue').textContent = byId('marker').value + '%';
  byId('glowValue').textContent = byId('glow').value + '%';
  byId('radiusValue').textContent = byId('radius').value + '%';
  const logo = byId('previewLogo'), marker = byId('previewMarker');
  logo.className = 'logo ' + byId('iconStyle').value;
  logo.style.width = logo.style.height = byId('logo').value + '%';
  logo.style.borderRadius = byId('radius').value + '%';
  logo.style.fontSize = (Number(byId('logo').value) * (byId('iconStyle').value === 'orbit' ? .31 : .4)) + 'px';
  marker.style.width = marker.style.height = byId('marker').value + '%';
  const position = byId('position').value;
  marker.style.top = position.startsWith('top') ? '4%' : 'auto';
  marker.style.bottom = position.startsWith('bottom') ? '4%' : 'auto';
  marker.style.left = position.endsWith('left') ? '4%' : 'auto';
  marker.style.right = position.endsWith('right') ? '4%' : 'auto';
  marker.style.boxShadow = '0 0 6px rgba(150,150,150,' + Number(byId('glow').value)/100 + ')';
}
function save() {
  settings = {...settings, logoSize: Number(byId('logo').value), markerSize: Number(byId('marker').value), exePath: byId('exe').value.trim(), iconStyle: byId('iconStyle').value, markerPosition: byId('position').value, glow: Number(byId('glow').value), cornerRadius: Number(byId('radius').value)};
  labels();
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({event:'setSettings', context:inspectorId, payload:settings}));
}
function connectElgatoStreamDeckSocket(port, uuid, registerEvent, info, actionInfo) {
  inspectorId = uuid;
  const action = typeof actionInfo === 'string' ? JSON.parse(actionInfo) : actionInfo;
  settings = action.payload.settings || {};
  refresh();
  socket = new WebSocket('ws://127.0.0.1:' + port);
  socket.onopen = () => { socket.send(JSON.stringify({event:registerEvent, uuid})); byId('connection').textContent = 'Изменения сохраняются автоматически'; };
  socket.onclose = () => { byId('connection').textContent = 'Нет связи. Откройте настройки кнопки заново.'; };
  socket.onmessage = message => {
    const data = JSON.parse(message.data);
    if (data.event.replace(/^_/, '') === 'didReceiveSettings') { settings = data.payload.settings || {}; refresh(); }
  };
}
byId('logo').addEventListener('input', save);
byId('marker').addEventListener('input', save);
byId('glow').addEventListener('input', save);
byId('radius').addEventListener('input', save);
byId('iconStyle').addEventListener('change', save);
byId('position').addEventListener('change', save);
byId('exe').addEventListener('change', save);
byId('reset').addEventListener('click', () => { byId('logo').value = 85; byId('marker').value = 20; save(); });
