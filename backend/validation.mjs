// Purpose: Validate the existing client contracts before SQL or paid provider side effects.
// Inputs: Untrusted JSON values and HTTP metadata.
// Outputs: Validated fields or typed HTTP errors.
// Side effects: None.
// MARK: - Bounded primitive values and sanitized errors
export class HTTPError extends Error {
  constructor(status, reason, headers = {}) {
    super(reason);
    this.status = status;
    this.headers = headers;
  }
}
export const fail = (status, reason, headers) => {
  throw new HTTPError(status, reason, headers);
};
export const safeID = (v) =>
  typeof v === "string" && /^[A-Za-z0-9_-]{1,80}$/.test(v);
export const text = (v, max, empty = false) =>
  typeof v === "string" &&
  Buffer.byteLength(v) <= max &&
  !v.includes("\0") &&
  (empty || v.trim().length > 0);
export const filename = (v) =>
  typeof v === "string" &&
  /^[A-Za-z0-9 _().-]{1,180}$/.test(v) &&
  !v.startsWith(".") &&
  v === v.trim();
// MARK: - Snapshot structure and account credential policy
export function snapshot(value) {
  if (
    !value ||
    Array.isArray(value) ||
    value.schemaVersion !== 1 ||
    !value.profile ||
    Array.isArray(value.profile) ||
    typeof value.profile !== "object" ||
    !Object.keys(value.profile).length
  )
    fail(400, "Invalid snapshot profile or schema.");
  for (const field of ["records", "visits", "bookings", "recordings"]) {
    if (
      !Array.isArray(value[field]) ||
      value[field].length > 5000 ||
      value[field].some(
        (item) => !item || typeof item !== "object" || Array.isArray(item),
      )
    )
      fail(400, "Invalid snapshot arrays.");
  }
  function depth(item, level) {
    if (level > 32) fail(400, "Snapshot nesting exceeds 32 levels.");
    if (item && typeof item === "object")
      for (const child of Object.values(item)) depth(child, level + 1);
  }
  depth(value, 0);
}
export function credentials(input, signup = false) {
  if (!input || typeof input.email !== "string")
    fail(400, "Provide an email address.");
  const email = input.email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254)
    fail(400, "Provide a valid email address.");
  password(input.password, email);
  if (signup && (!text(input.name, 80) || /[\x00-\x1f\x7f]/.test(input.name)))
    fail(400, "Name must contain 1–80 characters without control characters.");
  return { email, password: input.password, name: input.name?.trim() };
}
export function password(value, email) {
  if (
    !text(value, 72) ||
    [...value].length < 8 ||
    !/[A-Z]/.test(value) ||
    !/[0-9]/.test(value) ||
    !/[\p{P}\p{S}]/u.test(value) ||
    /[\r\n]/.test(value) ||
    value.toLowerCase() === email?.toLowerCase()
  )
    fail(
      400,
      "Use at least 8 characters, a capital letter, a number and a symbol; at most 72 UTF-8 bytes, no line breaks, and a password different from your email.",
    );
}
// MARK: - Provider source limits and source identity checks
export function summaryInput(input) {
  if (
    !safeID(input?.recordID) ||
    !text(input.title, 240) ||
    !text(input.text, 120000)
  )
    fail(400, "Provide recordID, title and bounded source text.");
}
export function preparationInput(input) {
  const v = input?.visit,
    records = input?.records;
  if (
    !safeID(v?.id) ||
    !text(v.type, 80) ||
    !text(v.concern, 6000, true) ||
    !text(v.goal, 6000, true) ||
    !(v.concern + v.goal).trim() ||
    !Array.isArray(v.questions) ||
    v.questions.length > 20 ||
    v.questions.some((q) => !text(q, 1000)) ||
    !Array.isArray(records) ||
    records.length < 1 ||
    records.length > 100
  )
    fail(400, "Provide a valid visit and 1–100 source records.");
  if (new Set(records.map((r) => r?.id)).size !== records.length)
    fail(400, "Record IDs must be unique.");
  let size = 0;
  for (const r of records) {
    if (
      !safeID(r?.id) ||
      !text(r.title, 240) ||
      !text(r.date, 40) ||
      !Number.isSafeInteger(r.version) ||
      r.version < 1 ||
      !text(r.text, 120000) ||
      !text(r.summary, 8000, true)
    )
      fail(400, "Invalid source record.");
    size += Buffer.byteLength(r.text + r.summary);
  }
  if (size > 500000) fail(413, "Select fewer source records.");
}
