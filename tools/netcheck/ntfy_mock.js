// A tiny stand-in for ntfy.sh (only what the game uses), for testing co-op
// where ntfy.sh can't be reached: GET /<topic>/ws (WebSocket: an "open"
// event, then every message posted to the topic, keepalives every 45 s)
// and POST /<topic> (the body becomes the message). CORS allowed.
// Run: node tools/netcheck/ntfy_mock.js [port]   (needs the `ws` package)
const http = require('http');
const { WebSocketServer } = require('ws');
const port = parseInt(process.argv[2] || '9100');
const subs = new Map(); // topic -> Set(ws)
let n = 0;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS' };
const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
  const topic = req.url.split('?')[0].replace(/^\/+/, '').split('/')[0];
  if ((req.method === 'POST' || req.method === 'PUT') && topic) {
    let body = '';
    req.on('data', (d) => body += d);
    req.on('end', () => {
      const msg = { id: 'm' + (++n), time: Math.floor(Date.now() / 1000), event: 'message', topic, message: body };
      for (const ws of subs.get(topic) || []) ws.send(JSON.stringify(msg));
      console.log(`post ${topic} (${body.length} bytes) -> ${(subs.get(topic) || new Set()).size} listening`);
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
      res.end(JSON.stringify(msg));
    });
    return;
  }
  res.writeHead(404, cors); res.end();
});
const wss = new WebSocketServer({ noServer: true });
server.on('upgrade', (req, socket, head) => {
  const m = req.url.match(/^\/([-_A-Za-z0-9]{1,64})\/ws/);
  if (!m) return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => {
    const topic = m[1];
    if (!subs.has(topic)) subs.set(topic, new Set());
    subs.get(topic).add(ws);
    ws.send(JSON.stringify({ id: 'o', time: Math.floor(Date.now() / 1000), event: 'open', topic }));
    const ka = setInterval(() => ws.send(JSON.stringify({ event: 'keepalive', topic })), 45000);
    ws.on('close', () => { clearInterval(ka); subs.get(topic).delete(ws); });
    console.log(`listen ${topic}`);
  });
});
server.listen(port, '127.0.0.1', () => console.log(`ntfy mock on ${port}`));
