// Purpose: Transfer originals up to 16 MiB in <=3 MiB requests under Vercel's 4.5 MB body limit.
// Incomplete uploads expire, count toward a per-owner staging quota and never replace originals.
import { database, transaction } from "./database.mjs";
import { fail, safeID } from "./validation.mjs";
export async function transferChunk(owner, id, offset, total, bytes) {
  if (
    !safeID(id) ||
    !Number.isSafeInteger(offset) ||
    !Number.isSafeInteger(total) ||
    offset < 0 ||
    total < 1 ||
    total > 16 * 1024 * 1024 ||
    !bytes.length ||
    bytes.length > 3 * 1024 * 1024 ||
    offset + bytes.length > total
  )
    fail(400, "Invalid upload chunk.");
  return transaction(async (client) => {
    await client.query("DELETE FROM reva_web_uploads WHERE expires_at<now()");
    await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [owner]);
    const row = (
      await client.query(
        "SELECT * FROM reva_web_uploads WHERE owner_id=$1 AND upload_id=$2 FOR UPDATE",
        [owner, id],
      )
    ).rows[0];
    if (row && (row.total !== total || row.bytes.length !== offset))
      fail(409, "Upload offset changed. Restart the upload.");
    if (!row && offset !== 0) fail(409, "Upload is missing its first chunk.");
    const quota = (
      await client.query(
        "SELECT count(*) AS count,COALESCE(sum(octet_length(bytes)),0) AS size FROM reva_web_uploads WHERE owner_id=$1",
        [owner],
      )
    ).rows[0];
    if (
      (!row && Number(quota.count) >= 8) ||
      Number(quota.size) + bytes.length > 32 * 1024 * 1024
    )
      fail(413, "Temporary upload quota exceeded. Try again after an hour.");
    if (row)
      await client.query(
        "UPDATE reva_web_uploads SET bytes=bytes || $3::bytea,expires_at=now()+interval '1 hour' WHERE owner_id=$1 AND upload_id=$2",
        [owner, id, bytes],
      );
    else
      await client.query(
        "INSERT INTO reva_web_uploads(owner_id,upload_id,total,bytes) VALUES($1,$2,$3,$4)",
        [owner, id, total, bytes],
      );
    return { status: 204 };
  });
}
export async function readTransfer(owner, id) {
  if (!safeID(id)) fail(400, "Invalid upload reference.");
  const row = (
    await database().query(
      "SELECT total,bytes FROM reva_web_uploads WHERE owner_id=$1 AND upload_id=$2 AND expires_at>now()",
      [owner, id],
    )
  ).rows[0];
  if (!row || row.total !== row.bytes.length)
    fail(409, "Upload is incomplete or expired. Restart the upload.");
  return row.bytes;
}
export async function removeTransfer(owner, id) {
  await database().query(
    "DELETE FROM reva_web_uploads WHERE owner_id=$1 AND upload_id=$2",
    [owner, id],
  );
}
