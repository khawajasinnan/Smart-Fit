// Serves the Flutter web build (frontend/build/web) for the E2E tests on http://localhost:5055.
// Not 5000: that is the port `flutter run -d chrome --web-port 5000` uses for Google sign-in, and a
// developer's own debug app there was picked up by the tests (21 Nov 2026). The tests log in by email.
// (the web OAuth redirect address). Static files only; the app uses #/ routes.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../frontend/build/web/', import.meta.url));
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.woff2': 'font/woff2', '.css': 'text/css', '.ico': 'image/x-icon', '.webp': 'image/webp',
  '.gif': 'image/gif', '.bin': 'application/octet-stream', '.frag': 'application/octet-stream',
};
createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = normalize(join(root, path === '/' ? 'index.html' : path));
  if (!file.startsWith(normalize(root))) { res.writeHead(403); res.end(); return; }
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(body);
  } catch {
    res.writeHead(404); res.end('not found');
  }
}).listen(5055, () => console.log('SmartFit web build on http://localhost:5055'));
