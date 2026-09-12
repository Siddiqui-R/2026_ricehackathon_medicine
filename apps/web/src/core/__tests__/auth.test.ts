// Purpose: Verify the auth client sends the documented /v1/auth requests and maps every error honestly.
// Inputs: A mock fetch, synthetic session envelopes and SafeErrors-shaped error bodies.
// Outputs: Assertions for request shapes, bearer handling, envelope checks, status mapping and origins.
// Side effects: Test memory only; every fetch is injected and no credential is real.
import { describe, expect, it, vi } from 'vitest';
import { APIError } from '../api.ts';
import {
  apiURL,
  AuthAPI,
  checkedEnvelope,
  emailProblem,
  nameProblem,
  passwordProblem,
  resolveAPIOrigin,
} from '../auth.ts';
import { testUser } from './fixtures.ts';

// MARK: - Fixtures: a valid envelope, JSON responses and a fetch spy that records one call.
const expiresAt = new Date(Date.now() + 30 * 86_400_000).toISOString();
const envelope = () => ({ token: 'synthetic-session-token', expiresAt, user: { ...testUser } });
const json = (value: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
const empty = (status = 204) => new Response(null, { status });
function spy(response: Response) {
  const fetcher = vi.fn<typeof fetch>().mockResolvedValue(response);
  return {
    fetcher,
    call() {
      const [url, options] = fetcher.mock.calls[0];
      const headers = options!.headers as Record<string, string>;
      return { url, options: options!, headers, body: options!.body as string | undefined };
    },
  };
}

// MARK: - Public routes carry JSON bodies and no bearer; bearer routes carry no body unless documented.
describe('auth request shapes', () => {
  it('signs up with a normalized email, trimmed name and the exact password', async () => {
    const { fetcher, call } = spy(json(envelope(), 201));
    const session = await new AuthAPI(null, fetcher).signup({
      email: '  Synthetic.Person@Example.TEST ',
      password: 'correct horse battery',
      name: '  Synthetic Person ',
    });
    expect(session).toEqual(envelope());
    const { url, options, headers, body } = call();
    expect(url).toBe('/v1/auth/signup');
    expect(options).toMatchObject({
      method: 'POST',
      credentials: 'omit',
      redirect: 'error',
      cache: 'no-store',
    });
    expect(headers).toEqual({ 'Content-Type': 'application/json' });
    expect(JSON.parse(body!)).toEqual({
      email: 'synthetic.person@example.test',
      password: 'correct horse battery',
      name: 'Synthetic Person',
    });
  });
  it('logs in with only email and password and returns the checked envelope', async () => {
    const { call, fetcher } = spy(json(envelope()));
    await expect(
      new AuthAPI(null, fetcher).login({
        email: 'Synthetic.Person@example.test',
        password: 'correct horse battery',
      }),
    ).resolves.toEqual(envelope());
    const { url, headers, body } = call();
    expect(url).toBe('/v1/auth/login');
    expect(headers.Authorization).toBeUndefined();
    expect(JSON.parse(body!)).toEqual({
      email: 'synthetic.person@example.test',
      password: 'correct horse battery',
    });
  });
  it.each([
    ['logout', '/v1/auth/logout', (api: AuthAPI) => api.logout()],
    ['logoutAll', '/v1/auth/logout-all', (api: AuthAPI) => api.logoutAll()],
  ])('%s posts the bearer token with no body and accepts 204', async (_name, path, run) => {
    const { call, fetcher } = spy(empty());
    await expect(run(new AuthAPI('synthetic-session-token', fetcher))).resolves.toBeUndefined();
    const { url, options, headers, body } = call();
    expect(url).toBe(path);
    expect(options.method).toBe('POST');
    expect(body).toBeUndefined();
    expect(headers).toEqual({ Authorization: 'Bearer synthetic-session-token' });
  });
  it('changes the password with PUT and both passwords in the body', async () => {
    const { call, fetcher } = spy(empty());
    await new AuthAPI('synthetic-session-token', fetcher).changePassword('old password 1', 'new password 22');
    const { url, options, headers, body } = call();
    expect(url).toBe('/v1/auth/password');
    expect(options.method).toBe('PUT');
    expect(headers).toEqual({
      'Content-Type': 'application/json',
      Authorization: 'Bearer synthetic-session-token',
    });
    expect(JSON.parse(body!)).toEqual({ currentPassword: 'old password 1', newPassword: 'new password 22' });
  });
  it('deletes the account with DELETE and the password in the body', async () => {
    const { call, fetcher } = spy(empty());
    await new AuthAPI('synthetic-session-token', fetcher).deleteAccount('old password 1');
    const { url, options, body } = call();
    expect(url).toBe('/v1/auth/account');
    expect(options.method).toBe('DELETE');
    expect(JSON.parse(body!)).toEqual({ password: 'old password 1' });
  });
  it('describes the presenting session from GET /v1/auth/session', async () => {
    const description = {
      kind: 'account',
      owner: testUser.id,
      user: testUser,
      session: {
        id: 'sess_synthetic',
        createdAt: '2026-09-12T10:00:00Z',
        expiresAt: '2026-10-12T10:00:00Z',
        lastUsedAt: '2026-09-12T10:05:00Z',
      },
    };
    const { call, fetcher } = spy(json(description));
    await expect(new AuthAPI('synthetic-session-token', fetcher).session()).resolves.toEqual(description);
    expect(call().options.method).toBe('GET');
    expect(call().body).toBeUndefined();
  });
  it('refuses bearer routes without a session and never calls fetch', async () => {
    const fetcher = vi.fn<typeof fetch>();
    await expect(new AuthAPI(null, fetcher).logout()).rejects.toThrow('Log in before');
    expect(() => new AuthAPI('  ', fetcher)).toThrow('signed-in session');
    expect(fetcher).not.toHaveBeenCalled();
  });
});

// MARK: - Client-side policy mirrors the server so most mistakes never leave the browser.
describe('local validation', () => {
  it('rejects a short, oversize or email-equal password before any request', async () => {
    const fetcher = vi.fn<typeof fetch>();
    const api = new AuthAPI(null, fetcher);
    await expect(api.signup({ email: 'a@example.test', password: 'short', name: 'A' })).rejects.toThrow(
      'at least 10',
    );
    await expect(
      api.signup({ email: 'a@example.test', password: 'x'.repeat(73), name: 'A' }),
    ).rejects.toThrow('at most 72');
    await expect(
      api.signup({ email: 'long.enough@example.test', password: 'long.enough@example.test', name: 'A' }),
    ).rejects.toThrow('same as the email');
    await expect(api.login({ email: 'not-an-email', password: 'correct horse battery' })).rejects.toThrow(
      'valid email',
    );
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('exposes the same helpers the forms use', () => {
    expect(passwordProblem('correct horse battery')).toBeNull();
    expect(passwordProblem('line\nbreak pass')).toMatch(/line break/);
    expect(emailProblem('')).toMatch(/Enter your email/);
    expect(emailProblem('synthetic.person@example.test')).toBeNull();
    expect(nameProblem('   ')).toMatch(/Enter your name/);
    expect(nameProblem('n'.repeat(81))).toMatch(/at most 80/);
    expect(nameProblem('Synthetic Person')).toBeNull();
  });
  it('requires a different new password for a change', async () => {
    const fetcher = vi.fn<typeof fetch>();
    const api = new AuthAPI('synthetic-session-token', fetcher);
    await expect(api.changePassword('same password 1', 'same password 1')).rejects.toThrow('differs');
    await expect(api.changePassword('', 'new password 22')).rejects.toThrow('current password');
    await expect(api.deleteAccount('')).rejects.toThrow('Enter your password');
    expect(fetcher).not.toHaveBeenCalled();
  });
});

// MARK: - Envelopes are checked field by field; an expired or partial one is refused.
describe('session envelope checks', () => {
  it('accepts the documented envelope and nothing less', () => {
    expect(checkedEnvelope(envelope())).toEqual(envelope());
    expect(() => checkedEnvelope({ ...envelope(), token: '' })).toThrow('invalid text');
    expect(() => checkedEnvelope({ ...envelope(), user: { id: 'u' } })).toThrow('signed-in user');
    expect(() => checkedEnvelope({ ...envelope(), expiresAt: 'later' })).toThrow('invalid date');
    expect(() => checkedEnvelope({ ...envelope(), expiresAt: '2000-01-01T00:00:00Z' })).toThrow(
      'already-expired',
    );
    expect(() => checkedEnvelope([])).toThrow('unreadable');
  });
  it('rejects a non-JSON success body instead of guessing', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response('<html>', { status: 200 }));
    await expect(
      new AuthAPI(null, fetcher).login({ email: 'a@example.test', password: 'correct horse battery' }),
    ).rejects.toThrow();
  });
});

// MARK: - Status mapping: the server's reason wins when present; otherwise honest status text.
describe('error mapping', () => {
  const login = (response: Response) =>
    new AuthAPI(null, vi.fn<typeof fetch>().mockResolvedValue(response)).login({
      email: 'a@example.test',
      password: 'correct horse battery',
    });
  it.each([400, 401, 403, 404, 409, 429])('carries the server reason for HTTP %i', async (status) => {
    const error = await login(json({ error: true, reason: `Synthetic reason for ${status}` }, status)).catch(
      (thrown: unknown) => thrown,
    );
    expect(error).toBeInstanceOf(APIError);
    expect(error).toMatchObject({ status, message: `Synthetic reason for ${status}` });
  });
  it.each([
    [400, /rejected this request/],
    [401, /did not accept/],
    [403, /not allowed/],
    [404, /unavailable/],
    [409, /server changed/i],
    [429, /Too many attempts/],
    [500, /HTTP 500/],
  ])('falls back to status text for HTTP %i without a reason', async (status, pattern) => {
    await expect(login(new Response('', { status }))).rejects.toThrow(pattern);
  });
  it('reads Retry-After on 429 and says roughly how long to wait', async () => {
    const error = await login(json({ error: true }, 429, { 'Retry-After': '120' })).catch(
      (thrown: unknown) => thrown,
    );
    expect(error).toMatchObject({ status: 429, retryAfter: 120 });
    expect((error as Error).message).toMatch(/about 2 minutes/);
  });
  it('ignores reasons that are not JSON, not strings, too long or multi-line', async () => {
    await expect(
      login(
        new Response('{"reason":"plain text type"}', {
          status: 400,
          headers: { 'Content-Type': 'text/plain' },
        }),
      ),
    ).rejects.toThrow(/rejected this request/);
    await expect(login(json({ reason: 42 }, 400))).rejects.toThrow(/rejected this request/);
    await expect(login(json({ reason: 'x'.repeat(501) }, 400))).rejects.toThrow(/rejected this request/);
    await expect(login(json({ reason: 'two\nlines' }, 400))).rejects.toThrow(/rejected this request/);
  });
  it('turns a timeout into a plain connection message', async () => {
    const fetcher = vi.fn<typeof fetch>().mockImplementation(
      (_url, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
        }),
    );
    vi.useFakeTimers();
    try {
      const pending = new AuthAPI('synthetic-session-token', fetcher).logout();
      const settled = pending.catch((error: unknown) => error);
      await vi.advanceTimersByTimeAsync(25_000);
      await expect(settled).resolves.toMatchObject({
        message: expect.stringMatching(/did not answer in time/),
      });
    } finally {
      vi.useRealTimers();
    }
  });
});

// MARK: - The API origin is same-origin by default and otherwise must be https or loopback http.
describe('API origin', () => {
  it('accepts an empty value, https origins and loopback http origins', () => {
    expect(resolveAPIOrigin(undefined)).toBe('');
    expect(resolveAPIOrigin('  ')).toBe('');
    expect(resolveAPIOrigin('https://api.example.test')).toBe('https://api.example.test');
    expect(resolveAPIOrigin('https://api.example.test/')).toBe('https://api.example.test');
    expect(resolveAPIOrigin('https://api.example.test:8443')).toBe('https://api.example.test:8443');
    expect(resolveAPIOrigin('http://127.0.0.1:8080')).toBe('http://127.0.0.1:8080');
    expect(resolveAPIOrigin('http://localhost:8080/')).toBe('http://localhost:8080');
    expect(resolveAPIOrigin('http://[::1]:8080')).toBe('http://[::1]:8080');
  });
  it.each([
    'http://api.example.test',
    'https://api.example.test/v1',
    'https://api.example.test?x=1',
    'https://api.example.test#top',
    'https://user:secret@api.example.test',
    'ftp://api.example.test',
    'not a url',
    'api.example.test',
  ])('rejects %s at startup', (value) => {
    expect(() => resolveAPIOrigin(value)).toThrow('VITE_REVA_API_ORIGIN');
  });
  it('prefixes origin-relative paths and refuses anything else', () => {
    expect(apiURL('/v1/auth/login', 'https://api.example.test')).toBe(
      'https://api.example.test/v1/auth/login',
    );
    expect(apiURL('/health', '')).toBe('/health');
    expect(apiURL('/v1/state')).toBe('/v1/state');
    expect(() => apiURL('v1/state', 'https://api.example.test')).toThrow('origin-relative');
    expect(() => apiURL('//evil.example.test/v1', 'https://api.example.test')).toThrow('origin-relative');
  });
});
