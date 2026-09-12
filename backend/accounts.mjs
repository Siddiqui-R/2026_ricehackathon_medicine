// Purpose: Account/session compatibility with the Swift API, using shared durable storage.
// Passwords use bcrypt; only SHA-256 hashes of opaque bearer tokens are stored.
// Inputs: Validated credential fields and bearer tokens.
// Outputs: Account/session DTOs or sanitized authentication failures.
// Side effects: Shared SQL throttles, account and session mutations.
import { randomBytes, randomUUID, createHash } from "node:crypto";
import bcrypt from "bcryptjs";
import { database, transaction } from "./database.mjs";
import { fail, credentials, password } from "./validation.mjs";
export const hash = (value) => createHash("sha256").update(value).digest("hex");
const userDTO = (row) => ({
  id: row.user_id,
  email: row.email,
  name: row.display_name,
  createdAt: row.created_at.toISOString(),
});
const dummy = bcrypt.hash("reva-non-account-dummy-password", 12);

// MARK: Atomic shared throttles work across function instances and never store emails/IPs in plain text.
export async function throttle(label, limit, seconds) {
  const result = await database().query(
    `INSERT INTO reva_web_limits(key_hash,count,resets_at) VALUES($1,1,now()+$2*interval '1 second')
    ON CONFLICT(key_hash) DO UPDATE SET count=CASE WHEN reva_web_limits.resets_at<now() THEN 1 ELSE reva_web_limits.count+1 END,
    resets_at=CASE WHEN reva_web_limits.resets_at<now() THEN now()+$2*interval '1 second' ELSE reva_web_limits.resets_at END RETURNING count`,
    [hash(label), seconds],
  );
  if (result.rows[0].count > limit)
    fail(429, "Too many attempts. Please wait before retrying.", {
      "Retry-After": String(seconds),
    });
  await database().query(
    "DELETE FROM reva_web_limits WHERE resets_at<now()-interval '1 day'",
  );
}
// MARK: - Opaque session issuance and resolution
async function issue(client, row) {
  const token = "rs_" + randomBytes(32).toString("base64url"),
    id = randomUUID();
  const days = Math.min(
    365,
    Math.max(1, Number(process.env.REVA_SESSION_DAYS) || 30),
  );
  const expiresAt = new Date(Date.now() + days * 86400000);
  await client.query(
    "INSERT INTO reva_sessions(session_id,token_hash,user_id,expires_at) VALUES($1,$2,$3,$4)",
    [id, hash(token), row.user_id, expiresAt],
  );
  await client.query(
    `UPDATE reva_sessions SET revoked_at=now() WHERE session_id IN
    (SELECT session_id FROM reva_sessions WHERE user_id=$1 AND revoked_at IS NULL AND expires_at>now() ORDER BY created_at DESC OFFSET 20)`,
    [row.user_id],
  );
  return { token, expiresAt: expiresAt.toISOString(), user: userDTO(row) };
}
export async function authenticate(header) {
  const token =
    typeof header === "string" && /^Bearer ([^\s]{24,512})$/.exec(header)?.[1];
  if (!token) fail(401, "Sign in to continue.");
  let tokens = {};
  try {
    tokens = JSON.parse(process.env.REVA_TOKENS || "{}");
  } catch {
    fail(503, "Server authentication configuration is invalid.");
  }
  if (
    Object.hasOwn(tokens, token) &&
    /^[A-Za-z0-9_-]{1,80}$/.test(tokens[token])
  )
    return { owner: tokens[token], kind: "token", user: null, session: null };
  const { rows } = await database().query(
    `SELECT u.*,s.session_id,s.created_at AS session_created,s.last_used_at,s.expires_at FROM reva_sessions s
    JOIN reva_users u USING(user_id) WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now()`,
    [hash(token)],
  );
  if (!rows.length) fail(401, "Your session ended. Please log in again.");
  const row = rows[0];
  await database().query(
    "UPDATE reva_sessions SET last_used_at=now() WHERE session_id=$1 AND last_used_at<now()-interval '5 minutes'",
    [row.session_id],
  );
  return {
    owner: row.user_id,
    kind: "account",
    user: userDTO(row),
    session: {
      id: row.session_id,
      createdAt: row.session_created.toISOString(),
      lastUsedAt: row.last_used_at.toISOString(),
      expiresAt: row.expires_at.toISOString(),
    },
  };
}
// MARK: - Registration, login and password-confirmed account actions
export async function accountRoute(route, method, input, identity, peer) {
  if (route === "signup" || route === "login") {
    if (method !== "POST") fail(405, "Method not supported.");
    if (route === "signup" && process.env.REVA_SIGNUP === "closed")
      fail(403, "Sign-up is closed on this server.");
    const c = credentials(input, route === "signup");
    await throttle("auth-ip:" + peer, 40, 900);
    await throttle("auth-email:" + c.email, 8, 900);
    if (route === "signup") {
      const encoded = await bcrypt.hash(c.password, 12);
      try {
        return {
          status: 201,
          body: await transaction(async (client) => {
            const row = (
              await client.query(
                "INSERT INTO reva_users(user_id,email,display_name,password_hash) VALUES($1,$2,$3,$4) RETURNING *",
                [
                  "u_" + randomBytes(12).toString("hex"),
                  c.email,
                  c.name,
                  encoded,
                ],
              )
            ).rows[0];
            return issue(client, row);
          }),
        };
      } catch (error) {
        if (error.code === "23505")
          fail(409, "An account with this email already exists.");
        throw error;
      }
    }
    const row = (
      await database().query("SELECT * FROM reva_users WHERE email=$1", [
        c.email,
      ])
    ).rows[0];
    const valid = await bcrypt.compare(
      c.password,
      row?.password_hash || (await dummy),
    );
    if (!row || !valid) fail(401, "Email or password is incorrect.");
    return {
      body: await transaction(async (client) => {
        const locked = (
          await client.query(
            "SELECT * FROM reva_users WHERE user_id=$1 FOR UPDATE",
            [row.user_id],
          )
        ).rows[0];
        if (!locked || locked.password_hash !== row.password_hash)
          fail(401, "Please log in again.");
        return issue(client, locked);
      }),
    };
  }
  if (route === "session" && method === "GET") return { body: identity };
  if (identity.kind !== "account")
    fail(400, "This operation requires an account session.");
  if ((route === "logout" || route === "logout-all") && method === "POST") {
    await database().query(
      route === "logout"
        ? "UPDATE reva_sessions SET revoked_at=now() WHERE session_id=$1"
        : "UPDATE reva_sessions SET revoked_at=now() WHERE user_id=$1",
      [route === "logout" ? identity.session.id : identity.owner],
    );
    return { status: 204 };
  }
  if (
    (route === "password" && method === "PUT") ||
    (route === "account" && method === "DELETE")
  ) {
    const supplied =
      route === "password" ? input.currentPassword : input.password;
    if (typeof supplied !== "string" || Buffer.byteLength(supplied) > 72)
      fail(400, "Provide your current password.");
    await throttle("password:" + identity.owner, 8, 900);
    const row = (
      await database().query("SELECT * FROM reva_users WHERE user_id=$1", [
        identity.owner,
      ])
    ).rows[0];
    if (!row || !(await bcrypt.compare(supplied, row.password_hash)))
      fail(401, "Current password is incorrect.");
    let encoded;
    if (route === "password") {
      password(input.newPassword, row.email);
      encoded = await bcrypt.hash(input.newPassword, 12);
    }
    await transaction(async (client) => {
      const current = (
        await client.query(
          "SELECT password_hash FROM reva_users WHERE user_id=$1 FOR UPDATE",
          [identity.owner],
        )
      ).rows[0];
      if (!current || current.password_hash !== row.password_hash)
        fail(409, "Account changed. Try again.");
      if (route === "password") {
        await client.query(
          "UPDATE reva_users SET password_hash=$2,password_updated_at=now() WHERE user_id=$1",
          [identity.owner, encoded],
        );
        await client.query(
          "UPDATE reva_sessions SET revoked_at=now() WHERE user_id=$1 AND session_id<>$2",
          [identity.owner, identity.session.id],
        );
      } else {
        await client.query("DELETE FROM reva_web_uploads WHERE owner_id=$1", [
          identity.owner,
        ]);
        await client.query("DELETE FROM reva_owner_state WHERE owner_id=$1", [
          identity.owner,
        ]);
        await client.query("DELETE FROM reva_users WHERE user_id=$1", [
          identity.owner,
        ]);
      }
    });
    return { status: 204 };
  }
  fail(405, "Method not supported.");
}
