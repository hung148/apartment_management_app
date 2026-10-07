'use strict';
// Serves the local test build (build/local-web) at http://localhost:5300 and
// forwards Firebase calls to the emulators on this computer, so the page only
// ever talks to its own address (some browsers, like the Claude browser pane,
// block a page from calling other localhost ports). Started by tool\local.ps1.
// Node built-ins only. Ports match firebase.local.json.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PORT = 5300;
const ROOT = path.resolve('build/local-web');
const ROUTES = [
  ['/identitytoolkit.googleapis.com/', 9199],
  ['/securetoken.googleapis.com/', 9199],
  ['/emulator/', 9199],
  ['/google.firestore.v1.Firestore/', 8180],
  ['/demo-canho360/', 5101],
];
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.webp': 'image/webp', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
  '.frag': 'application/octet-stream', '.map': 'application/json',
};

function forward(req, res, port) {
  const upstream = http.request(
    { host: '127.0.0.1', port, method: req.method, path: req.url, headers: { ...req.headers, host: `127.0.0.1:${port}` } },
    reply => { res.writeHead(reply.statusCode, reply.headers); reply.pipe(res); },
  );
  upstream.on('error', e => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' });
    res.end(`Emulator on port ${port} is not reachable: ${e.message}`);
  });
  req.pipe(upstream);
}

function serveFile(req, res) {
  const urlPath = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  let file = path.join(ROOT, urlPath);
  if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    const index = path.join(file, 'index.html');
    // Unknown paths fall back to the app (it uses #/ addresses anyway).
    file = fs.existsSync(index) ? index : path.join(ROOT, 'index.html');
  }
  res.writeHead(200, { 'content-type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream', 'cache-control': 'no-cache' });
  if (path.basename(file) === 'index.html') {
    // FlutterFire restores a remembered sign-in while Firebase starts, before
    // the app can call useAuthEmulator, so that first check would go to the
    // real Google servers and fail. In this LOCAL page only, every request
    // meant for Google's sign-in servers is sent to this server instead, which
    // forwards it to the Auth emulator (same paths).
    const hint = '<script>(function(){var f=window.fetch,g=/^https:\\/\\/(identitytoolkit|securetoken)\\.googleapis\\.com\\//;'
      + 'window.fetch=function(i,o){var u=typeof i==="string"?i:(i&&i.url);'
      + 'if(u&&g.test(u)){var n=location.origin+"/"+u.slice(8);i=typeof i==="string"?n:new Request(n,i);}'
      + 'return f.call(this,i,o);};})();</script>';
    return res.end(fs.readFileSync(file, 'utf8').replace('<head>', '<head>' + hint));
  }
  fs.createReadStream(file).pipe(res);
}

if (!fs.existsSync(path.join(ROOT, 'index.html'))) {
  console.error(`No local build in ${ROOT}. Run tool\\local.ps1 (it builds first).`);
  process.exit(1);
}
http.createServer((req, res) => {
  const route = ROUTES.find(([prefix]) => req.url.startsWith(prefix));
  if (route) forward(req, res, route[1]); else serveFile(req, res);
}).listen(PORT, '127.0.0.1', () => {
  console.log(`Local app: http://localhost:${PORT}   (Ctrl+C to stop; after app changes run tool\\local.ps1 again)`);
});
