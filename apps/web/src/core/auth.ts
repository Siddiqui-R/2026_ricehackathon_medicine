// Purpose: Sign up, log in and manage account sessions against the Swift API's /v1/auth routes.
// Inputs: Email/password/name from the forms, and the current bearer session token for account actions.
// Outputs: Validated session envelopes and session descriptions, or APIError with the server's reason.
// Side effects: Bounded HTTP only (timeout, no redirects, no cookies, no cache); nothing is stored here.
import { APIError, apiURL, boundedBytes, errorReason, headerRetryAfter, resolveAPIOrigin } from './api.ts';
import { sessionUser, type SessionUser, type StoredSession } from './session.ts';

export { apiURL, resolveAPIOrigin };

// MARK: - Wire shapes and client-side policy limits that mirror the server contract
export const MAX_AUTH_BODY_BYTES = 16 * 1024;
export const MAX_AUTH_RESPONSE_BYTES = 64 * 1024;
export const PASSWORD_MIN_CHARACTERS = 8;
export const PASSWORD_MAX_BYTES = 72;
export const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export interface SessionDescription {
  kind: 'account' | 'token';
  owner: string;
  user: SessionUser | null;
  session: { id: string; createdAt: string; expiresAt: string; lastUsedAt: string } | null;
}
export type AuthTransport = Pick<
  AuthAPI,
  'signup' | 'login' | 'logout' | 'logoutAll' | 'session' | 'changePassword' | 'deleteAccount'
>;
export const normalizeEmail = (email: string): string => email.trim().toLowerCase();
const utf8Bytes = (value: string): number => new TextEncoder().encode(value).byteLength;
// Returns a user-facing problem or null. The server applies the same rules and stays authoritative.
export function passwordProblem(password: string, email = ''): string | null {
  const bytes = utf8Bytes(password);
  if ([...password].length < PASSWORD_MIN_CHARACTERS) return 'Use at least 8 characters.';
  if (bytes > PASSWORD_MAX_BYTES) return 'Use at most 72 UTF-8 bytes.';
  if (/[\r\n]/.test(password)) return 'A password cannot contain line breaks.';
  if (email && password === normalizeEmail(email)) return 'A password cannot be the same as the email.';
  if (!/[A-Z]/.test(password)) return 'Include at least 1 capital letter (A–Z).';
  if (!/[0-9]/.test(password)) return 'Include at least 1 number (0–9).';
  if (!/[\p{P}\p{S}]/u.test(password)) return 'Include at least 1 symbol.';
  return null;
}
export function emailProblem(email: string): string | null {
  const normalized = normalizeEmail(email);
  if (!normalized) return 'Enter your email address.';
  if (normalized.length < 3 || normalized.length > 254 || !EMAIL_PATTERN.test(normalized))
    return 'Enter a valid email address.';
  if (/[\u0000-\u001f\u007f]/u.test(normalized)) return 'Enter a valid email address.';
  return null;
}
export function nameProblem(name: string): string | null {
  const trimmed = name.trim();
  if (!trimmed) return 'Enter your name.';
  if (trimmed.length > 80) return 'Use at most 80 characters.';
  if (/[\u0000-\u001f\u007f]/u.test(trimmed)) return 'A name cannot contain control characters.';
  return null;
}

// MARK: - Response readers accept only the documented envelope fields
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('The server response was unreadable.');
  return value as Record<string, unknown>;
}
function string(value: unknown, maximum = 512): string {
  if (typeof value !== 'string' || !value || value.length > maximum || /[\r\n]/.test(value))
    throw new Error('The server response contained invalid text.');
  return value;
}
function timestamp(value: unknown): string {
  const text = string(value, 64);
  if (!Number.isFinite(Date.parse(text))) throw new Error('The server response contained an invalid date.');
  return text;
}
export function checkedEnvelope(value: unknown): StoredSession {
  const result = object(value);
  const user = sessionUser(result.user);
  if (!user) throw new Error('The server response did not describe the signed-in user.');
  const session = { token: string(result.token), expiresAt: timestamp(result.expiresAt), user };
  if (Date.parse(session.expiresAt) <= Date.now())
    throw new Error('The server issued an already-expired session. Check the server clock.');
  return session;
}

// MARK: - One bounded request boundary shared by public and bearer-authenticated auth routes
export class AuthAPI {
  private readonly token: string | null;
  private readonly fetcher: typeof fetch;
  constructor(token: string | null = null, fetcher: typeof fetch = globalThis.fetch.bind(globalThis)) {
    if (token !== null && (!token.trim() || /[\r\n]/.test(token)))
      throw new Error('A signed-in session is required for this action.');
    this.token = token;
    this.fetcher = fetcher;
  }
  private async send(
    path: string,
    method: string,
    value?: unknown,
    { authenticated = false, timeout = 25_000 }: { authenticated?: boolean; timeout?: number } = {},
  ): Promise<Record<string, unknown> | null> {
    const headers: Record<string, string> = {};
    let body: string | undefined;
    if (value !== undefined) {
      body = JSON.stringify(value);
      if (utf8Bytes(body) > MAX_AUTH_BODY_BYTES)
        throw new Error('The request is larger than the server accepts.');
      headers['Content-Type'] = 'application/json';
    }
    if (authenticated) {
      if (!this.token) throw new Error('Log in before using this account action.');
      headers.Authorization = `Bearer ${this.token}`;
    }
    const controller = new AbortController(),
      timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await this.fetcher(apiURL(path), {
        method,
        body,
        headers,
        signal: controller.signal,
        credentials: 'omit',
        cache: 'no-store',
        redirect: 'error',
      });
      if (!response.ok)
        throw new APIError(
          response.status,
          null,
          await errorReason(response),
          headerRetryAfter(response.headers.get('Retry-After')),
        );
      const bytes = await boundedBytes(response, MAX_AUTH_RESPONSE_BYTES);
      if (!bytes.byteLength) return null;
      return object(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)));
    } catch (error) {
      if (controller.signal.aborted)
        throw new Error('The server did not answer in time. Check your connection and try again.');
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }

  // MARK: - Public routes: sign-up and log-in return a session envelope to store
  async signup(input: { email: string; password: string; name: string }): Promise<StoredSession> {
    const problem =
      nameProblem(input.name) ?? emailProblem(input.email) ?? passwordProblem(input.password, input.email);
    if (problem) throw new Error(problem);
    const result = await this.send('/v1/auth/signup', 'POST', {
      email: normalizeEmail(input.email),
      password: input.password,
      name: input.name.trim(),
    });
    return checkedEnvelope(result);
  }
  async login(input: { email: string; password: string }): Promise<StoredSession> {
    const problem = emailProblem(input.email) ?? (input.password ? null : 'Enter your password.');
    if (problem) throw new Error(problem);
    const result = await this.send('/v1/auth/login', 'POST', {
      email: normalizeEmail(input.email),
      password: input.password,
    });
    return checkedEnvelope(result);
  }

  // MARK: - Bearer routes act on the presenting session; 204 answers carry no body
  async session(): Promise<SessionDescription> {
    const result = object(await this.send('/v1/auth/session', 'GET', undefined, { authenticated: true }));
    const kind = string(result.kind, 16);
    if (kind !== 'account' && kind !== 'token')
      throw new Error('The server described an unknown session kind.');
    const session = result.session == null ? null : object(result.session);
    return {
      kind,
      owner: string(result.owner, 80),
      user: result.user == null ? null : sessionUser(result.user),
      session: session && {
        id: string(session.id, 64),
        createdAt: timestamp(session.createdAt),
        expiresAt: timestamp(session.expiresAt),
        lastUsedAt: timestamp(session.lastUsedAt),
      },
    };
  }
  async logout(): Promise<void> {
    await this.send('/v1/auth/logout', 'POST', undefined, { authenticated: true });
  }
  async logoutAll(): Promise<void> {
    await this.send('/v1/auth/logout-all', 'POST', undefined, { authenticated: true });
  }
  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    if (!currentPassword) throw new Error('Enter your current password.');
    const problem = passwordProblem(newPassword);
    if (problem) throw new Error(problem);
    if (newPassword === currentPassword)
      throw new Error('Choose a new password that differs from the current one.');
    await this.send('/v1/auth/password', 'PUT', { currentPassword, newPassword }, { authenticated: true });
  }
  async deleteAccount(password: string): Promise<void> {
    if (!password) throw new Error('Enter your password to delete this account.');
    await this.send('/v1/auth/account', 'DELETE', { password }, { authenticated: true });
  }
}
