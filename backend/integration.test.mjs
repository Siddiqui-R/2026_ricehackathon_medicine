// Purpose: Exercise real HTTP + Tiger transactions using isolated fictional accounts, then delete only those accounts.
// Run with REVA_TEST_DB=true. Reads ignored .env for this explicit integration test only.
import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { parseEnv } from "node:util";
import handler from "../api/reva.mjs";
import { closeDatabase } from "./database.mjs";
test(
  "Vercel HTTP contracts: accounts, owner isolation, CAS, originals, logout, password change and deletion",
  { skip: process.env.REVA_TEST_DB !== "true", timeout: 120000 },
  async () => {
    Object.assign(
      process.env,
      parseEnv(await readFile(new URL("../.env", import.meta.url), "utf8")),
    );
    const server = createServer(handler);
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const origin = "http://127.0.0.1:" + server.address().port;
    const password = "Reva-test-" + randomUUID();
    const accounts = [];
    async function request(path, method = "GET", token, body, headers = {}) {
      return fetch(origin + path, {
        method,
        headers: {
          ...(token ? { Authorization: "Bearer " + token } : {}),
          ...(body && !Buffer.isBuffer(body)
            ? { "Content-Type": "application/json" }
            : {}),
          ...headers,
        },
        body: body
          ? Buffer.isBuffer(body)
            ? body
            : JSON.stringify(body)
          : undefined,
      });
    }
    try {
      assert.equal((await request("/health")).status, 200);
      assert.equal((await request("/v1/state")).status, 401);
      for (let i = 0; i < 2; i++) {
        const email = "reva-check-" + randomUUID() + "@example.invalid";
        const response = await request("/v1/auth/signup", "POST", null, {
          email,
          password,
          name: "Fictional Deployment Test",
        });
        assert.equal(response.status, 201, await response.clone().text());
        accounts.push({ ...(await response.json()), email, password });
      }
      const [a, b] = accounts;
      const upload = randomUUID();
      assert.equal(
        (
          await request(
            `/v1/transfers/${upload}?offset=0&total=6`,
            "PUT",
            a.token,
            Buffer.from("abc"),
            { "Content-Type": "application/octet-stream" },
          )
        ).status,
        204,
      );
      assert.equal(
        (
          await request("/v1/attachments/chunked", "PUT", a.token, null, {
            "Content-Type": "text/plain",
            "X-Filename": "chunks.txt",
            "X-Reva-Upload": upload,
          })
        ).status,
        409,
      );
      assert.equal(
        (
          await request(
            `/v1/transfers/${upload}?offset=3&total=6`,
            "PUT",
            b.token,
            Buffer.from("def"),
            { "Content-Type": "application/octet-stream" },
          )
        ).status,
        409,
      );
      assert.equal(
        (
          await request(
            `/v1/transfers/${upload}?offset=3&total=6`,
            "PUT",
            a.token,
            Buffer.from("def"),
            { "Content-Type": "application/octet-stream" },
          )
        ).status,
        204,
      );
      assert.equal(
        (
          await request("/v1/attachments/chunked", "PUT", a.token, null, {
            "Content-Type": "text/plain",
            "X-Filename": "chunks.txt",
            "X-Reva-Upload": upload,
          })
        ).status,
        204,
      );
      const ranged = await request(
        "/v1/attachments/chunked",
        "GET",
        a.token,
        null,
        { Range: "bytes=0-2" },
      );
      assert.equal(ranged.status, 206);
      assert.equal(await ranged.text(), "abc");
      assert.equal(ranged.headers.get("content-range"), "bytes 0-2/6");
      assert.equal(
        (
          await request("/v1/attachments/chunked", "GET", a.token, null, {
            Range: "bytes=3-5",
            "If-Match": '"changed"',
          })
        ).status,
        412,
      );
      assert.equal(
        (await request("/v1/attachments/chunked", "DELETE", a.token)).status,
        204,
      );
      assert.equal(
        (await request("/v1/auth/session", "GET", a.token)).status,
        200,
      );
      const initial = await request("/v1/state", "GET", a.token);
      assert.equal(initial.status, 404);
      assert.equal(initial.headers.get("x-state-revision"), "0");
      const state = {
        schemaVersion: 1,
        profile: { id: "fictional" },
        records: [],
        visits: [],
        bookings: [],
        recordings: [],
      };
      const saved = await request("/v1/state", "PUT", a.token, {
        baseRevision: 0,
        snapshot: state,
      });
      assert.equal(saved.status, 200);
      assert.equal((await saved.json()).revision, 1);
      assert.equal(
        (
          await request("/v1/state", "PUT", a.token, {
            baseRevision: 0,
            snapshot: state,
          })
        ).status,
        409,
      );
      assert.deepEqual(
        (await (await request("/v1/state", "GET", a.token)).json()).snapshot,
        state,
      );
      assert.equal((await request("/v1/state", "GET", b.token)).status, 404);
      assert.equal(
        (
          await request(
            "/v1/attachments/fixture",
            "PUT",
            a.token,
            Buffer.from("Fictional original"),
            { "Content-Type": "text/plain", "X-Filename": "fixture.txt" },
          )
        ).status,
        204,
      );
      assert.equal(
        await (await request("/v1/attachments/fixture", "GET", a.token)).text(),
        "Fictional original",
      );
      assert.equal(
        (await request("/v1/attachments/fixture", "GET", b.token)).status,
        404,
      );
      assert.equal(
        (await request("/v1/attachments/fixture", "DELETE", a.token)).status,
        204,
      );
      assert.equal(
        (await request("/v1/attachments/fixture", "GET", a.token)).status,
        404,
      );
      assert.equal(
        (await (await request("/v1/state", "DELETE", a.token)).json()).revision,
        2,
      );
      assert.equal(
        (await (await request("/v1/state", "DELETE", a.token)).json()).revision,
        2,
      );
      assert.equal(
        (
          await request("/v1/state", "PUT", a.token, {
            baseRevision: 1,
            snapshot: state,
          })
        ).status,
        409,
      );
      assert.equal(
        (await request("/v1/providers", "GET", a.token)).status,
        200,
      );
      const login = await request("/v1/auth/login", "POST", null, {
        email: a.email,
        password,
      });
      assert.equal(login.status, 200);
      const second = await login.json();
      const newPassword = password + "-changed";
      assert.equal(
        (
          await request("/v1/auth/password", "PUT", a.token, {
            currentPassword: password,
            newPassword,
          })
        ).status,
        204,
      );
      a.password = newPassword;
      assert.equal(
        (await request("/v1/auth/session", "GET", second.token)).status,
        401,
      );
      assert.equal(
        (await request("/v1/auth/logout", "POST", b.token)).status,
        204,
      );
      assert.equal(
        (await request("/v1/auth/session", "GET", b.token)).status,
        401,
      );
      const relogin = await request("/v1/auth/login", "POST", null, {
        email: b.email,
        password,
      });
      b.token = (await relogin.json()).token;
      assert.equal((await request("/api/reva?route=/health")).status, 200);
      assert.equal(
        (await request("/v1/booking/call", "POST", a.token, {})).status,
        404,
      );
    } finally {
      for (const a of accounts) {
        const response = await request("/v1/auth/account", "DELETE", a.token, {
          password: a.password,
        });
        assert.equal(
          response.status,
          204,
          "Cleanup must remove the fictional account",
        );
        assert.equal(
          (await request("/v1/auth/session", "GET", a.token)).status,
          401,
        );
      }
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
      await closeDatabase();
    }
  },
);
