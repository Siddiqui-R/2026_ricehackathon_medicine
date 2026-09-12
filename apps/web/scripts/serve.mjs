// Purpose: Serve a built web client and proxy its authenticated requests to the local Swift API.
// Inputs: dist assets, optional PORT/HOST, and a loopback REVA_API_ORIGIN.
// Outputs: A same-origin browser application (/, /demo, /login, /signup, /app) with bounded API forwarding.
// Side effects: Opens one HTTP listener and forwards explicitly allowed API routes only.

import { createServer, request as requestHTTP } from 'node:http';
import { createReadStream } from 'node:fs';
import { realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// MARK: - Explicit listener/destination configuration prevents an arbitrary URL proxy
const root = await realpath(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../dist'));
const api = new URL(process.env.REVA_API_ORIGIN || 'http://127.0.0.1:8080');
if (
  api.protocol !== 'http:' ||
  !['localhost', '127.0.0.1', '[::1]'].includes(api.hostname) ||
  api.username ||
  api.password ||
  api.pathname !== '/' ||
  api.search ||
  api.hash
)
  throw new Error('REVA_API_ORIGIN must be a loopback HTTP origin.');
const port = Number(process.env.PORT || 4173);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be a valid TCP port.');
const host = process.env.HOST || '127.0.0.1';
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
  '.gz': 'application/gzip',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

// MARK: - Parse only origin-form targets; never let request text select the upstream authority
function parseTarget(target) {
  if (
    typeof target !== 'string' ||
    target.length > 4096 ||
    !target.startsWith('/') ||
    target.startsWith('//') ||
    /[\\#\u0000-\u0020\u007f]/u.test(target)
  )
    throw new Error('Invalid request target.');
  const query = target.indexOf('?');
  const rawPath = query < 0 ? target : target.slice(0, query);
  const pathname = decodeURIComponent(rawPath);
  if (
    /%2f|%5c/iu.test(rawPath) ||
    /[\\\u0000-\u001f\u007f]/u.test(pathname) ||
    pathname.split('/').some((segment) => segment === '.' || segment === '..')
  )
    throw new Error('Invalid request path.');
  return { pathname, forwardPath: target };
}

// MARK: - Explicit API methods and byte budgets mirror the current Swift routes
// Auth bodies are capped at 16 KiB by the server; logout routes carry no body at all.
function apiRoute(pathname) {
  if (pathname === '/health' || pathname === '/v1/providers') return { GET: 0 };
  if (pathname === '/v1/auth/signup' || pathname === '/v1/auth/login') return { POST: 16 * 1024 };
  if (pathname === '/v1/auth/session') return { GET: 0 };
  if (pathname === '/v1/auth/logout' || pathname === '/v1/auth/logout-all') return { POST: 0 };
  if (pathname === '/v1/auth/password') return { PUT: 16 * 1024 };
  if (pathname === '/v1/auth/account') return { DELETE: 16 * 1024 };
  if (pathname === '/v1/state') return { GET: 0, PUT: 4 * 1024 * 1024, DELETE: 0 };
  if (pathname === '/v1/ai/summarize') return { POST: 256 * 1024 };
  if (pathname === '/v1/ai/prepare') return { POST: 1024 * 1024 };
  if (pathname === '/v1/audio/transcribe') return { POST: 16 * 1024 * 1024 };
  if (/^\/v1\/attachments\/[A-Za-z0-9_-]{1,80}$/u.test(pathname))
    return { GET: 0, PUT: 16 * 1024 * 1024, DELETE: 0 };
  return null;
}

// MARK: - Validate the complete bounded body before any upstream side effect is possible
function readBody(incoming, maximum) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let bytes = 0;
    let failed = false;
    incoming.on('data', (chunk) => {
      if (failed) return;
      bytes += chunk.length;
      if (bytes > maximum) {
        failed = true;
        chunks.length = 0;
        reject(new Error('limit'));
      } else chunks.push(chunk);
    });
    incoming.on('end', () => {
      if (!failed) resolve(Buffer.concat(chunks, bytes));
    });
    incoming.on('error', reject);
    incoming.on('aborted', () => reject(new Error('aborted')));
  });
}

// MARK: - Only compiled assets, bundled fictional data and the five public application routes are readable
const appRoutes = new Set(['/', '/demo', '/login', '/signup', '/app']);
function appRoute(pathname) {
  return appRoutes.has(pathname.length > 1 ? pathname.replace(/\/+$/u, '') : pathname);
}
function publicAsset(pathname) {
  if (appRoute(pathname) || pathname === '/index.html' || pathname === '/reva.svg') return true;
  const parts = pathname.split('/').slice(1);
  if (parts.some((part) => !part || part.startsWith('.'))) return false;
  const extensions = {
    assets: ['.js', '.mjs', '.css', '.svg', '.png', '.jpg', '.jpeg', '.webp', '.woff', '.woff2'],
    demo: ['.json', '.png', '.jpg', '.jpeg', '.pdf', '.txt'],
    ocr: ['.js', '.wasm', '.gz'],
  };
  return Object.hasOwn(extensions, parts[0]) && extensions[parts[0]].includes(path.extname(pathname));
}

// MARK: - Shared error path reveals no upstream configuration or request content
function failure(response, status, reason) {
  if (response.headersSent) {
    response.destroy();
    return;
  }
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify({ error: true, reason }));
}
const server = createServer(async (incoming, response) => {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('Cache-Control', 'no-store');
  let pathname, forwardPath;
  try {
    ({ pathname, forwardPath } = parseTarget(incoming.url));
  } catch {
    failure(response, 400, 'Invalid request path.');
    return;
  }

  // MARK: - Same-origin provider/state proxy retains auth and CAS metadata, with finite time and bytes
  if (pathname === '/health' || pathname.startsWith('/v1/')) {
    const route = apiRoute(pathname);
    if (!route) {
      failure(response, 404, 'API route not found.');
      incoming.resume();
      return;
    }
    if (!Object.hasOwn(route, incoming.method)) {
      failure(response, 405, 'Method not supported.');
      incoming.resume();
      return;
    }
    const headers = {};
    for (const name of ['authorization', 'content-type', 'x-filename', 'accept'])
      if (incoming.headers[name]) headers[name] = incoming.headers[name];
    const maximum = route[incoming.method];
    if (Number(incoming.headers['content-length'] || 0) > maximum) {
      failure(response, 413, 'Request exceeds this route’s byte limit.');
      incoming.resume();
      return;
    }
    let body;
    try {
      body = await readBody(incoming, maximum);
    } catch (error) {
      failure(response, error.message === 'limit' ? 413 : 400, 'Request body could not be accepted.');
      incoming.resume();
      return;
    }
    if (incoming.aborted || response.destroyed) return;
    if (body.length || ['POST', 'PUT'].includes(incoming.method))
      headers['content-length'] = String(body.length);
    const upstream = requestHTTP(api, { path: forwardPath, method: incoming.method, headers }, (result) => {
      if (result.statusCode >= 300 && result.statusCode < 400) {
        result.resume();
        failure(response, 502, 'The Reva server returned an unsupported redirect.');
        return;
      }
      const forwarded = { 'cache-control': 'no-store' };
      for (const name of [
        'content-type',
        'content-length',
        'x-state-revision',
        'x-filename',
        'content-disposition',
        'retry-after',
        'etag',
      ])
        if (result.headers[name]) forwarded[name] = result.headers[name];
      response.writeHead(result.statusCode || 502, forwarded);
      result.pipe(response);
      result.on('error', () => response.destroy());
    });
    const deadline = setTimeout(() => {
      upstream.destroy();
      failure(response, 504, 'The Reva server request timed out. Your local copy remains available.');
    }, 115000);
    deadline.unref();
    upstream.on('error', () =>
      failure(response, 502, 'The Reva server is unavailable. Start it and check your connection.'),
    );
    response.on('close', () => {
      clearTimeout(deadline);
      upstream.destroy();
    });
    incoming.on('aborted', () => upstream.destroy());
    upstream.end(body);
    return;
  }

  // MARK: - Static assets stay inside the built directory and never expose source or local patient files
  if (!['GET', 'HEAD'].includes(incoming.method)) {
    failure(response, 405, 'Method not supported.');
    return;
  }
  if (!publicAsset(pathname)) {
    failure(response, 404, 'File not found.');
    return;
  }
  try {
    const candidate = path.resolve(root, '.' + (appRoute(pathname) ? '/index.html' : pathname));
    const file = await realpath(candidate);
    const metadata = await stat(file);
    if (!file.startsWith(root + path.sep) || !metadata.isFile()) {
      failure(response, 404, 'File not found.');
      return;
    }
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; worker-src 'self' blob:; connect-src 'self' blob:; frame-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
    );
    response.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
    response.setHeader('Content-Length', String(metadata.size));
    if (incoming.method === 'HEAD') {
      response.end();
      return;
    }
    const stream = createReadStream(file);
    stream.on('error', () => failure(response, 500, 'File could not be read.'));
    stream.pipe(response);
  } catch {
    failure(response, 404, 'File not found.');
  }
});

// MARK: - Listener lifetime and predictable local preview address
server.requestTimeout = 120000;
server.listen(port, host, () => console.log(`Reva web: http://${host}:${port} (Swift API ${api.origin})`));
for (const signal of ['SIGINT', 'SIGTERM'])
  process.once(signal, () => {
    server.close();
    server.closeIdleConnections();
  });
