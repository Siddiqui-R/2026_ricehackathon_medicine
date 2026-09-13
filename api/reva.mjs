// Purpose: Same-origin Vercel API for accounts, durable Tiger storage and configured AI.
// Only exact routes dispatch; auth precedes private storage/provider access. No secrets enter Vite.
// Inputs: Bounded HTTP requests and server environment configuration.
// Outputs: Existing client JSON DTOs, original bytes or sanitized errors.
// Side effects: Authenticated database and provider operations through focused modules.
import { migrate, database } from "../backend/database.mjs";
import { authenticate, accountRoute, throttle } from "../backend/accounts.mjs";
import { stateRoute, attachmentRoute } from "../backend/storage.mjs";
import { providerStatus, gemini, transcribe } from "../backend/providers.mjs";
import { fail, HTTPError } from "../backend/validation.mjs";
import {
  transferChunk,
  readTransfer,
  removeTransfer,
} from "../backend/transfers.mjs";

export const config = { api: { bodyParser: false } };
// MARK: - Streaming body boundary and size limits
async function readBody(req, max, json) {
  if (Number(req.headers["content-length"] || 0) > max)
    fail(413, "Request exceeds this route’s size limit.");
  if (
    json &&
    !(req.headers["content-type"] || "").startsWith("application/json")
  )
    fail(415, "Use application/json.");
  const parts = [];
  let size = 0;
  for await (const part of req) {
    size += part.length;
    if (size > max) fail(413, "Request exceeds this route’s size limit.");
    parts.push(part);
  }
  const bytes = Buffer.concat(parts);
  if (!json) return bytes;
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch {
    fail(400, "Invalid JSON body.");
  }
}
// MARK: - Exact route dispatch, origin policy and authentication
export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  try {
    const url = new URL(req.url, "https://reva.invalid");
    const route = url.pathname.startsWith("/api/reva")
      ? url.searchParams.get("route")
      : url.pathname;
    const method = req.method;
    const authMatch =
      /^\/v1\/auth\/(signup|login|session|logout|logout-all|password|account)$/.exec(
        route || "",
      );
    const attachment = /^\/v1\/attachments\/([A-Za-z0-9_-]{1,80})$/.exec(
      route || "",
    );
    const operation = /^\/v1\/ai\/(summarize|prepare|profile)$/.exec(
      route || "",
    );
    const transfer = /^\/v1\/transfers\/([A-Za-z0-9_-]{1,80})$/.exec(
      route || "",
    );
    if (
      !authMatch &&
      !attachment &&
      !operation &&
      !transfer &&
      ![
        "/health",
        "/v1/state",
        "/v1/providers",
        "/v1/audio/transcribe",
      ].includes(route)
    )
      fail(404, "API route not found.");
    // Native clients omit Origin; browser cross-origin callers must be explicitly allowed.
    const origin = req.headers.origin;
    if (origin) {
      const allowed = new Set(
        (
          process.env.REVA_ALLOWED_ORIGINS ||
          "https://revamed.health,https://revamed.vercel.app"
        )
          .split(",")
          .map((x) => x.trim()),
      );
      if (process.env.VERCEL_URL)
        allowed.add("https://" + process.env.VERCEL_URL);
      if (!allowed.has(origin)) fail(403, "Origin is not allowed.");
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
      res.setHeader(
        "Access-Control-Allow-Methods",
        "GET,POST,PUT,DELETE,OPTIONS",
      );
      res.setHeader(
        "Access-Control-Allow-Headers",
        "Authorization,Content-Type,X-Filename,X-Reva-Upload,Range,If-Match",
      );
      res.setHeader(
        "Access-Control-Expose-Headers",
        "X-State-Revision,X-Filename,Retry-After,Content-Range,ETag",
      );
    }
    if (method === "OPTIONS") {
      res.statusCode = 204;
      res.end();
      return;
    }
    await migrate();
    let result;
    if (route === "/health") {
      if (method !== "GET") fail(405, "Method not supported.");
      await database().query("SELECT 1");
      result = { body: { status: "ok", storage: "postgres", isDemo: false } };
    } else {
      const publicAuth =
        authMatch && ["signup", "login"].includes(authMatch[1]);
      const identity = publicAuth
        ? null
        : await authenticate(req.headers.authorization);
      if (authMatch) {
        const needsBody = ["signup", "login", "password", "account"].includes(
          authMatch[1],
        );
        const input = needsBody ? await readBody(req, 16384, true) : {};
        const peer = String(
          req.headers["x-vercel-forwarded-for"] ||
            req.socket.remoteAddress ||
            "unknown",
        ).split(",")[0];
        result = await accountRoute(
          authMatch[1],
          method,
          input,
          identity,
          peer,
        );
      } else if (transfer) {
        if (method !== "PUT") fail(405, "Method not supported.");
        result = await transferChunk(
          identity.owner,
          transfer[1],
          Number(url.searchParams.get("offset")),
          Number(url.searchParams.get("total")),
          await readBody(req, 3 * 1024 * 1024, false),
        );
      } else if (route === "/v1/state")
        result = await stateRoute(
          method,
          identity.owner,
          method === "PUT" ? await readBody(req, 4 * 1024 * 1024, true) : null,
        );
      else if (attachment) {
        const upload = req.headers["x-reva-upload"];
        const bytes =
          method === "PUT"
            ? upload
              ? await readTransfer(identity.owner, upload)
              : await readBody(req, 4 * 1024 * 1024, false)
            : null;
        result = await attachmentRoute(
          method,
          identity.owner,
          attachment[1],
          bytes,
          req.headers,
        );
        if (upload && method === "PUT")
          await removeTransfer(identity.owner, upload);
      } else if (route === "/v1/providers") {
        if (method !== "GET") fail(405, "Method not supported.");
        result = { body: providerStatus() };
      } else {
        if (method !== "POST") fail(405, "Method not supported.");
        await throttle("provider:" + identity.owner, 30, 3600);
        await throttle("provider-global", 200, 86400);
        if (operation)
          result = {
            body: await gemini(
              operation[1],
              await readBody(
                req,
                operation[1] === "summarize"
                  ? 256 * 1024
                  : operation[1] === "profile"
                    ? 2 * 1024 * 1024
                    : 1024 * 1024,
                true,
              ),
            ),
          };
        else {
          const upload = req.headers["x-reva-upload"];
          result = {
            body: await transcribe(
              upload
                ? await readTransfer(identity.owner, upload)
                : await readBody(req, 4 * 1024 * 1024, false),
              req.headers,
            ),
          };
          if (upload) await removeTransfer(identity.owner, upload);
        }
      }
    }
    // MARK: - Response serialization and sanitized failures
    res.statusCode = result.status || 200;
    for (const [name, value] of Object.entries(result.headers || {}))
      res.setHeader(name, value);
    if (result.bytes) {
      res.end(result.bytes);
      return;
    }
    if (res.statusCode === 204) {
      res.end();
      return;
    }
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(result.body));
  } catch (error) {
    if (res.headersSent) {
      res.destroy();
      return;
    }
    res.statusCode = error instanceof HTTPError ? error.status : 503;
    for (const [name, value] of Object.entries(
      error instanceof HTTPError ? error.headers : {},
    ))
      res.setHeader(name, value);
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        error: true,
        reason:
          error instanceof HTTPError
            ? error.message
            : "The server is unavailable. Your browser copy is unchanged.",
      }),
    );
  }
}
