// Purpose: Exercise the production wrapper against isolated synthetic loopback HTTP servers.
// Inputs: A copied wrapper, temporary built assets and explicitly constructed request targets/bodies.
// Outputs: Assertions for fixed destinations, route/static allowlists, safe headers and body limits.
// Side effects: Creates temporary fixtures and loopback listeners; kills its child and removes fixtures.

import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer, request } from 'node:http';
import { copyFile, mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

// MARK: - Bounded listener/request helpers never resolve arbitrary network destinations
async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}
async function close(server) {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}
async function unusedPort() {
  const reservation = createServer();
  const port = await listen(reservation);
  await close(reservation);
  return port;
}
function send(port, target, { method = 'GET', headers = {}, body, chunks } = {}) {
  return new Promise((resolve, reject) => {
    const outgoing = request(
      { hostname: '127.0.0.1', port, path: target, method, headers, agent: false },
      (incoming) => {
        const parts = [];
        incoming.on('data', (chunk) => parts.push(chunk));
        incoming.on('error', reject);
        incoming.on('end', () =>
          resolve({ status: incoming.statusCode, headers: incoming.headers, bytes: Buffer.concat(parts) }),
        );
      },
    );
    outgoing.setTimeout(3000, () => outgoing.destroy(new Error('Test request timed out.')));
    outgoing.on('error', reject);
    if (chunks) for (const chunk of chunks) outgoing.write(chunk);
    outgoing.end(body);
  });
}
async function stopChild(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = once(child, 'exit');
  child.kill('SIGTERM');
  const deadline = setTimeout(() => child.kill('SIGKILL'), 1500);
  deadline.unref();
  try {
    await exited;
  } finally {
    clearTimeout(deadline);
  }
}

// MARK: - The wrapper uses temporary dist assets and a mock API; no real owner state is involved
test(
  'production wrapper keeps requests inside its configured loopback boundary',
  { timeout: 30_000 },
  async (t) => {
    const temporary = await mkdtemp(path.join(tmpdir(), 'reva-wrapper-test-'));
    const requests = [];
    let trapHits = 0;
    const trap = createServer((_incoming, response) => {
      trapHits += 1;
      response.end('This destination must never receive a request.');
    });
    const upstream = createServer((incoming, response) => {
      const chunks = [];
      incoming.on('data', (chunk) => chunks.push(chunk));
      incoming.on('end', () => {
        requests.push({
          target: incoming.url,
          method: incoming.method,
          headers: incoming.headers,
          body: Buffer.concat(chunks),
        });
        if (incoming.url === '/health?redirect=1') {
          response.writeHead(302, { Location: 'http://outside.invalid/private' });
          response.end();
          return;
        }
        const status = incoming.url.startsWith('/v1/state') && incoming.method === 'PUT' ? 409 : 200;
        response.writeHead(status, {
          'Content-Type': 'application/json',
          'X-State-Revision': '9',
          'X-Filename': 'synthetic-original.pdf',
          'Set-Cookie': 'synthetic-cookie=discard-me',
          'Access-Control-Allow-Origin': '*',
          'X-Content-Type-Options': 'invalid-upstream-value',
          'X-Unrelated-Upstream-Header': 'discard-me',
          'Cache-Control': 'public, max-age=86400',
        });
        response.end(JSON.stringify({ synthetic: true }));
      });
    });
    let child;
    t.after(async () => {
      if (child) await stopChild(child);
      await Promise.all([close(upstream), close(trap)]);
      await rm(temporary, { recursive: true, force: true });
    });
    const [upstreamPort, trapPort, webPort] = await Promise.all([
      listen(upstream),
      listen(trap),
      unusedPort(),
    ]);
    await mkdir(path.join(temporary, 'scripts'));
    await mkdir(path.join(temporary, 'dist', 'assets'), { recursive: true });
    await mkdir(path.join(temporary, 'dist', 'demo'));
    await mkdir(path.join(temporary, 'dist', 'ocr', 'core'), { recursive: true });
    await copyFile(
      fileURLToPath(new URL('./serve.mjs', import.meta.url)),
      path.join(temporary, 'scripts', 'serve.mjs'),
    );
    await Promise.all([
      writeFile(
        path.join(temporary, 'dist', 'index.html'),
        '<!doctype html><title>Synthetic Reva wrapper test</title>',
      ),
      writeFile(path.join(temporary, 'dist', 'assets', 'app.js'), '/* synthetic compiled fixture */'),
      writeFile(
        path.join(temporary, 'dist', 'assets', 'app.js.map'),
        '{"synthetic":"source map must not be served"}',
      ),
      writeFile(path.join(temporary, 'dist', 'demo', 'seed.json'), '{"synthetic":true}'),
      writeFile(path.join(temporary, 'dist', 'ocr', 'core', 'fixture.wasm'), Buffer.from([0, 97, 115, 109])),
      writeFile(path.join(temporary, 'dist', 'private-settings.txt'), 'synthetic private fixture'),
      writeFile(path.join(temporary, 'dist', 'assets', '.hidden.txt'), 'synthetic hidden fixture'),
      writeFile(path.join(temporary, 'outside.txt'), 'synthetic outside fixture'),
    ]);
    // A Windows directory junction exercises the same realpath escape without a symlink privilege.
    // Both fixtures stay inside this test's temporary directory, outside its public dist directory.
    const escapeTarget = process.platform === 'win32' ? '/assets/escape/private.js' : '/assets/escape.js';
    if (process.platform === 'win32') {
      await mkdir(path.join(temporary, 'outside'));
      await writeFile(path.join(temporary, 'outside', 'private.js'), 'synthetic outside fixture');
      await symlink(
        path.join(temporary, 'outside'),
        path.join(temporary, 'dist', 'assets', 'escape'),
        'junction',
      );
    } else {
      await symlink(path.join(temporary, 'outside.txt'), path.join(temporary, 'dist', 'assets', 'escape.js'));
    }
    child = spawn(process.execPath, [path.join(temporary, 'scripts', 'serve.mjs')], {
      cwd: temporary,
      env: {
        PATH: process.env.PATH,
        HOST: '127.0.0.1',
        PORT: String(webPort),
        REVA_API_ORIGIN: `http://127.0.0.1:${upstreamPort}`,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await new Promise((resolve, reject) => {
      const deadline = setTimeout(() => reject(new Error('Wrapper startup timed out.')), 5000);
      let output = '';
      const failed = (code) => {
        clearTimeout(deadline);
        reject(new Error(`Wrapper exited before startup: ${code}. ${output}`));
      };
      child.once('exit', failed);
      child.once('error', (error) => {
        clearTimeout(deadline);
        reject(error);
      });
      child.stderr.on('data', (chunk) => {
        output += chunk;
      });
      child.stdout.on('data', (chunk) => {
        output += chunk;
        if (output.includes('Reva web:')) {
          clearTimeout(deadline);
          child.removeListener('exit', failed);
          resolve();
        }
      });
    });

    // MARK: - Absolute and malformed targets fail before either upstream can receive credentials
    await t.test('rejects absolute URL authorities, traversal and malformed targets', async () => {
      const before = requests.length;
      for (const target of [
        `http://127.0.0.1:${trapPort}/v1/state`,
        `http://127.0.0.1:${trapPort}/health`,
        `//127.0.0.1:${trapPort}/v1/state`,
        '/%2f%2f127.0.0.1/v1/state',
        '/%5cexternal/v1/state',
        '/v1/../v1/state',
        '/v1/%2e%2e/v1/state',
        '/demo/%2e%2e/private-settings.txt',
        '/v1/state#fragment',
        '/v1/%ZZ',
        '/v1/%00state',
      ]) {
        const result = await send(webPort, target, {
          headers: { Authorization: 'Bearer synthetic-test-token' },
        });
        assert.equal(result.status, 400, target);
      }
      assert.equal(requests.length, before);
      assert.equal(trapHits, 0);
    });

    // MARK: - Auth, exact binary bodies, query strings and CAS metadata survive safe forwarding
    await t.test('forwards exact auth/body/path while stripping cookies and unsafe headers', async () => {
      const body = Buffer.from([0, 255, 7, 12]);
      const result = await send(webPort, '/v1/attachments/synthetic_id?part=one%20two', {
        method: 'PUT',
        headers: {
          Host: `127.0.0.1:${trapPort}`,
          Authorization: 'Bearer synthetic-test-token',
          'Content-Type': 'application/pdf',
          'Content-Length': String(body.length),
          'X-Filename': 'synthetic.pdf',
          Cookie: 'private=discard',
          'Proxy-Authorization': 'discard',
          'X-Forwarded-Host': 'outside.invalid',
        },
        body,
      });
      assert.equal(result.status, 200);
      const forwarded = requests.at(-1);
      assert.equal(forwarded.target, '/v1/attachments/synthetic_id?part=one%20two');
      assert.equal(forwarded.headers.authorization, 'Bearer synthetic-test-token');
      assert.equal(forwarded.headers['x-filename'], 'synthetic.pdf');
      assert.equal(forwarded.headers.host, `127.0.0.1:${upstreamPort}`);
      assert.equal(forwarded.headers.cookie, undefined);
      assert.equal(forwarded.headers['proxy-authorization'], undefined);
      assert.equal(forwarded.headers['x-forwarded-host'], undefined);
      assert.deepEqual(forwarded.body, body);
      assert.equal(result.headers['x-state-revision'], '9');
      assert.equal(result.headers['x-filename'], 'synthetic-original.pdf');
      assert.equal(result.headers['cache-control'], 'no-store');
      assert.equal(result.headers['x-content-type-options'], 'nosniff');
      assert.equal(result.headers['referrer-policy'], 'no-referrer');
      assert.equal(result.headers['set-cookie'], undefined);
      assert.equal(result.headers['access-control-allow-origin'], undefined);
      assert.equal(result.headers['x-unrelated-upstream-header'], undefined);
      assert.equal(trapHits, 0);
      const conflict = await send(webPort, '/v1/state', {
        method: 'PUT',
        body: '{"synthetic":true}',
        headers: { 'Content-Type': 'application/json' },
      });
      assert.equal(conflict.status, 409);
      assert.equal(conflict.headers['x-state-revision'], '9');
    });

    // MARK: - Method/route rules and complete-body bounds prevent unintended upstream dispatch
    await t.test('accepts only current API routes and methods', async () => {
      const before = requests.length;
      for (const [target, method, status] of [
        ['/v1/unknown', 'GET', 404],
        ['/v1/state', 'POST', 405],
        ['/v1/providers', 'PUT', 405],
        ['/v1/ai/summarize', 'GET', 405],
        ['/health', 'DELETE', 405],
        ['/v1/state', 'OPTIONS', 405],
        ['/v1/attachments/a.b', 'GET', 404],
        ['/v1/booking/call', 'POST', 404],
        ['/v1/booking/call/synthetic_id', 'GET', 404],
        ['/v1/auth/unknown', 'POST', 404],
        ['/v1/auth/login', 'GET', 405],
        ['/v1/auth/session', 'POST', 405],
        ['/v1/auth/account', 'GET', 405],
      ])
        assert.equal((await send(webPort, target, { method })).status, status, `${method} ${target}`);
      assert.equal(requests.length, before);
      for (const [target, method] of [
        ['/health', 'GET'],
        ['/v1/providers', 'GET'],
        ['/v1/state', 'DELETE'],
        ['/v1/ai/summarize', 'POST'],
        ['/v1/ai/prepare', 'POST'],
        ['/v1/audio/transcribe', 'POST'],
        ['/v1/attachments/synthetic_id', 'DELETE'],
        ['/v1/auth/signup', 'POST'],
        ['/v1/auth/login', 'POST'],
        ['/v1/auth/session', 'GET'],
        ['/v1/auth/logout', 'POST'],
        ['/v1/auth/logout-all', 'POST'],
        ['/v1/auth/password', 'PUT'],
        ['/v1/auth/account', 'DELETE'],
      ])
        assert.equal((await send(webPort, target, { method })).status, 200, `${method} ${target}`);
      assert.equal(
        (
          await send(webPort, '/v1/auth/login', {
            method: 'POST',
            headers: { 'Content-Length': String(16 * 1024 + 1) },
          })
        ).status,
        413,
      );
      assert.equal((await send(webPort, '/v1/auth/logout', { method: 'POST', body: 'x' })).status, 413);
    });
    await t.test('rejects declared and chunked excess bodies before forwarding any bytes', async () => {
      const before = requests.length;
      assert.equal(
        (
          await send(webPort, '/v1/attachments/synthetic_id', {
            method: 'PUT',
            headers: { 'Content-Length': String(16 * 1024 * 1024 + 1) },
          })
        ).status,
        413,
      );
      assert.equal(
        (
          await send(webPort, '/v1/state', {
            method: 'PUT',
            headers: { 'Content-Length': String(4 * 1024 * 1024 + 1) },
          })
        ).status,
        413,
      );
      assert.equal(
        (
          await send(webPort, '/v1/auth/login', {
            method: 'POST',
            chunks: [Buffer.alloc(8 * 1024), Buffer.alloc(8 * 1024 + 1)],
          })
        ).status,
        413,
      );
      assert.equal(
        (await send(webPort, '/health', { body: 'x', headers: { 'Content-Length': '1' } })).status,
        413,
      );
      assert.equal(requests.length, before);
      const boundary = Buffer.alloc(16 * 1024, 65);
      assert.equal(
        (await send(webPort, '/v1/auth/login', { method: 'POST', chunks: [boundary] })).status,
        200,
      );
      assert.deepEqual(requests.at(-1).body, boundary);
    });
    await t.test('does not expose an upstream redirect destination', async () => {
      const result = await send(webPort, '/health?redirect=1');
      assert.equal(result.status, 502);
      assert.equal(result.headers.location, undefined);
      assert.equal(trapHits, 0);
    });

    // MARK: - Compiled assets retain browser security headers and realpath confinement
    await t.test('serves only public compiled/demo assets with safe types and HEAD behavior', async () => {
      for (const [target, type] of [
        ['/', 'text/html; charset=utf-8'],
        ['/demo', 'text/html; charset=utf-8'],
        ['/demo/', 'text/html; charset=utf-8'],
        ['/login', 'text/html; charset=utf-8'],
        ['/signup', 'text/html; charset=utf-8'],
        ['/app', 'text/html; charset=utf-8'],
        ['/app/', 'text/html; charset=utf-8'],
        ['/assets/app.js', 'text/javascript'],
        ['/demo/seed.json', 'application/json'],
        ['/ocr/core/fixture.wasm', 'application/wasm'],
      ]) {
        const result = await send(webPort, target);
        assert.equal(result.status, 200);
        assert.equal(result.headers['content-type'], type);
        assert.equal(result.headers['x-content-type-options'], 'nosniff');
        assert.match(result.headers['content-security-policy'], /connect-src 'self' blob:/);
        assert.match(result.headers['content-security-policy'], /frame-ancestors 'none'/);
      }
      const head = await send(webPort, '/index.html?version=1', { method: 'HEAD' });
      assert.equal(head.status, 200);
      assert.equal(head.bytes.length, 0);
      assert.ok(Number(head.headers['content-length']) > 0);
      for (const target of [
        '/account',
        '/app/records',
        '/demo/records',
        '/private-settings.txt',
        '/assets/.hidden.txt',
        '/assets/app.js.map',
        escapeTarget,
        '/assets',
        '/demo/missing.pdf',
        '/scripts/serve.mjs',
        '/__proto__/file.js',
        '/constructor/file.js',
        '/toString/file.js',
      ])
        assert.equal((await send(webPort, target)).status, 404, target);
      assert.equal((await send(webPort, '/index.html', { method: 'POST' })).status, 405);
    });
  },
);
