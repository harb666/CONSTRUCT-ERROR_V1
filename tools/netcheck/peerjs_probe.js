// Probe the public PeerJS server (0.peerjs.com) with message variants, to
// see which ones it relays and which make it drop the connection.
// Run: node tools/netcheck/peerjs_probe.js   (needs the `ws` package)
const WebSocket = require('ws');
const URL = process.env.SIGNAL || 'wss://0.peerjs.com:443/peerjs';
const rnd = () => Math.random().toString(36).slice(2, 10);
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

function client(id, headers) {
  return new Promise((resolve) => {
    const token = rnd();
    const ws = new WebSocket(`${URL}?key=peerjs&id=${id}&token=${token}&version=1.5.4`, { headers });
    const c = { id, ws, got: [], closed: null, open: false };
    ws.on('message', (d) => { const m = JSON.parse(d.toString()); c.got.push(m); if (m.type === 'OPEN') { c.open = true; resolve(c); } });
    ws.on('close', (code, reason) => { c.closed = `${code} ${reason}`; resolve(c); });
    ws.on('error', (e) => { c.closed = 'error ' + e.message; resolve(c); });
    setTimeout(() => resolve(c), 8000);
  });
}

async function trial(name, headers, msgOf) {
  const a = await client('ce-probe-a-' + rnd(), headers);
  const b = await client('ce-probe-b-' + rnd(), headers);
  if (!a.open || !b.open) { console.log(`${name}: no OPEN (a ${a.closed} / b ${b.closed})`); return; }
  b.ws.send(JSON.stringify(msgOf(a.id)));
  await sleep(2500);
  const delivered = a.got.filter(m => m.type !== 'OPEN');
  console.log(`${name}: sender ${b.closed ? 'DROPPED (' + b.closed + ')' : 'ok'}; receiver got ${JSON.stringify(delivered)}`);
  a.ws.close(); b.ws.close();
}

(async () => {
  const origin = { Origin: 'https://harb666.github.io' };
  const ours = (dst) => ({ type: 'OFFER', dst, payload: { k: 'join', v: 1 } });
  const peerjsLike = (dst) => ({ type: 'OFFER', dst, payload: { sdp: { type: 'offer', sdp: 'x' }, type: 'data', connectionId: 'dc_' + rnd(), browser: 'chrome', label: 'x', reliable: true, serialization: 'json' } });
  const peerjsLikeWithOurs = (dst) => ({ type: 'OFFER', dst, payload: { k: 'join', v: 1, type: 'data', connectionId: 'dc_' + rnd(), sdp: { type: 'offer', sdp: 'x' } } });
  const answer = (dst) => ({ type: 'ANSWER', dst, payload: { k: 'welcome', id: 2 } });
  const candidate = (dst) => ({ type: 'CANDIDATE', dst, payload: { k: 'ice', m: '0', i: 0, n: 'candidate:1' } });
  await trial('ours (no origin)', {}, ours);
  await trial('ours (origin)', origin, ours);
  await trial('peerjs-like (origin)', origin, peerjsLike);
  await trial('peerjs-like + ours (origin)', origin, peerjsLikeWithOurs);
  await trial('answer (origin)', origin, answer);
  await trial('candidate (origin)', origin, candidate);
  process.exit(0);
})();
