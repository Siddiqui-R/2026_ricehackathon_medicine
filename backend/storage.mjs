// Purpose: Owner-scoped snapshots and originals with transactions, CAS and quotas.
// Inputs: Authenticated owner IDs, validated snapshot bodies and original bytes.
// Outputs: Revision envelopes, original bytes and bounded HTTP metadata.
// Side effects: Transactional Tiger reads/writes and a bounded mutation audit.
import { randomUUID, createHash } from "node:crypto";
import { database, transaction } from "./database.mjs";
import { fail, snapshot, filename, safeID } from "./validation.mjs";
const types = new Set([
  "application/pdf",
  "text/plain",
  "image/png",
  "image/jpeg",
  "image/heic",
  "image/heif",
  "audio/mp4",
  "audio/m4a",
  "audio/x-m4a",
  "audio/mpeg",
  "audio/wav",
  "audio/x-wav",
  "audio/webm",
  "audio/ogg",
  "video/mp4",
  "application/octet-stream",
]);
// MARK: - Owner serialization and bounded audit
async function ownerLock(client, owner) {
  await client.query(
    "INSERT INTO reva_owner_state(owner_id) VALUES($1) ON CONFLICT DO NOTHING",
    [owner],
  );
  return (
    await client.query(
      "SELECT * FROM reva_owner_state WHERE owner_id=$1 FOR UPDATE",
      [owner],
    )
  ).rows[0];
}
async function audit(client, owner, action, revision) {
  await client.query(
    "INSERT INTO reva_mutations(owner_id,mutation_id,action,revision) VALUES($1,$2,$3,$4)",
    [owner, randomUUID(), action, revision],
  );
  await client.query(
    "DELETE FROM reva_mutations WHERE owner_id=$1 AND mutation_id IN (SELECT mutation_id FROM reva_mutations WHERE owner_id=$1 ORDER BY created_at DESC OFFSET 128)",
    [owner],
  );
}
// MARK: - Revision-checked snapshots and deletion tombstones
export async function stateRoute(method, owner, input) {
  if (method === "GET") {
    const row = (
      await database().query(
        "SELECT revision,snapshot FROM reva_owner_state WHERE owner_id=$1",
        [owner],
      )
    ).rows[0];
    const revision = Number(row?.revision || 0),
      headers = { "X-State-Revision": String(revision) };
    if (!row?.snapshot) fail(404, "No saved state for this account.", headers);
    return { body: { revision, snapshot: row.snapshot }, headers };
  }
  if (!["PUT", "DELETE"].includes(method)) fail(405, "Method not supported.");
  if (method === "PUT") {
    if (!Number.isSafeInteger(input?.baseRevision) || input.baseRevision < 0)
      fail(400, "Provide a valid baseRevision.");
    snapshot(input.snapshot);
  }
  return transaction(async (client) => {
    const row = await ownerLock(client, owner),
      previous = Number(row.revision);
    if (method === "PUT" && previous !== input.baseRevision)
      fail(409, "The server changed. Pull and review before pushing again.", {
        "X-State-Revision": String(previous),
      });
    const revision =
      previous + (method === "PUT" || row.snapshot !== null ? 1 : 0);
    await client.query(
      "UPDATE reva_owner_state SET snapshot=$2::jsonb,revision=$3,updated_at=now() WHERE owner_id=$1",
      [
        owner,
        method === "PUT" ? JSON.stringify(input.snapshot) : null,
        revision,
      ],
    );
    if (method === "DELETE")
      await client.query("DELETE FROM reva_attachments WHERE owner_id=$1", [
        owner,
      ]);
    await audit(
      client,
      owner,
      method === "PUT" ? "state.put" : "state.delete",
      revision,
    );
    return {
      body: { revision },
      headers: { "X-State-Revision": String(revision) },
    };
  });
}
// MARK: - Original storage quotas and immutable range downloads
export async function attachmentRoute(method, owner, id, bytes, headers) {
  if (!safeID(id)) fail(400, "Invalid attachment identifier.");
  if (method === "GET") {
    const row = (
      await database().query(
        "SELECT filename,content_type,bytes FROM reva_attachments WHERE owner_id=$1 AND attachment_id=$2",
        [owner, id],
      )
    ).rows[0];
    if (!row) fail(404, "Original not found.");
    const etag =
      '"' + createHash("sha256").update(row.bytes).digest("hex") + '"';
    if (headers["if-match"] && headers["if-match"] !== etag)
      fail(412, "Original changed during download. Please retry.");
    if (headers.range) {
      const match = /^bytes=(\d+)-(\d+)$/.exec(headers.range);
      if (!match) fail(416, "Use an explicit byte range.");
      const start = Number(match[1]),
        end = Math.min(Number(match[2]), row.bytes.length - 1);
      if (start > end || end - start + 1 > 3 * 1024 * 1024)
        fail(416, "Invalid or oversized byte range.");
      return {
        status: 206,
        bytes: row.bytes.subarray(start, end + 1),
        headers: {
          ETag: etag,
          "Content-Type": row.content_type,
          "X-Filename": row.filename,
          "Content-Range": `bytes ${start}-${end}/${row.bytes.length}`,
        },
      };
    }
    if (row.bytes.length > 4 * 1024 * 1024)
      fail(413, "Download this original using byte ranges.");
    return {
      bytes: row.bytes,
      headers: {
        "Content-Type": row.content_type,
        "X-Filename": row.filename,
        "Content-Disposition": 'attachment; filename="' + row.filename + '"',
      },
    };
  }
  if (!["PUT", "DELETE"].includes(method)) fail(405, "Method not supported.");
  const type = (headers["content-type"] || "").split(";")[0].toLowerCase();
  if (method === "PUT") {
    if (!filename(headers["x-filename"]) || !bytes.length)
      fail(400, "Provide a safe filename and nonempty original.");
    if (!types.has(type)) fail(415, "Unsupported original content type.");
    if (bytes.length > 16 * 1024 * 1024) fail(413, "Original exceeds 16 MiB.");
  }
  return transaction(async (client) => {
    const row = await ownerLock(client, owner);
    if (method === "DELETE")
      await client.query(
        "DELETE FROM reva_attachments WHERE owner_id=$1 AND attachment_id=$2",
        [owner, id],
      );
    else {
      const quota = (
        await client.query(
          "SELECT count(*) AS count,COALESCE(sum(octet_length(bytes)),0) AS size FROM reva_attachments WHERE owner_id=$1 AND attachment_id<>$2",
          [owner, id],
        )
      ).rows[0];
      if (
        Number(quota.count) >= 128 ||
        Number(quota.size) + bytes.length > 64 * 1024 * 1024
      )
        fail(413, "Account original-storage quota exceeded.");
      await client.query(
        `INSERT INTO reva_attachments(owner_id,attachment_id,filename,content_type,bytes) VALUES($1,$2,$3,$4,$5)
        ON CONFLICT(owner_id,attachment_id) DO UPDATE SET filename=EXCLUDED.filename,content_type=EXCLUDED.content_type,bytes=EXCLUDED.bytes,updated_at=now()`,
        [owner, id, headers["x-filename"], type, bytes],
      );
    }
    await audit(
      client,
      owner,
      method === "PUT" ? "attachment.put" : "attachment.delete",
      Number(row.revision),
    );
    return { status: 204 };
  });
}
