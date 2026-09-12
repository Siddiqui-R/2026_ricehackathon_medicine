-- Purpose: Define schema v1 for owner snapshots, original bytes, and bounded mutation metadata.
-- Inputs: This checked-in SQL is loaded by PostgresStore.migrate under an advisory transaction lock.
-- Outputs: Aggregate tables and an audit lookup index with structural, identity, and byte constraints.
-- Side effects: Creates database objects. Schema-version bookkeeping is handled by the migration runner.
-- Ownership: Runtime queries supply the authenticated owner and bind their values as parameters.
-- Each store mutation is transactional. Separate snapshot and attachment requests have separate commits.

-- MARK: - Owner aggregate and retained revision after snapshot deletion
-- All native domain arrays remain inside JSONB, including optional profile and symptom fields.
CREATE TABLE IF NOT EXISTS reva_owner_state (
    owner_id TEXT PRIMARY KEY CHECK (owner_id ~ '^[A-Za-z0-9_-]{1,80}$'),
    revision BIGINT NOT NULL DEFAULT 0 CHECK (revision >= 0),
    snapshot JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (snapshot IS NULL OR (
        jsonb_typeof(snapshot) = 'object'
        AND snapshot ?& ARRAY['schemaVersion','profile','records','visits','bookings','recordings']
        AND snapshot->'schemaVersion' = '1'::jsonb
        AND jsonb_typeof(snapshot->'profile') = 'object'
        AND snapshot->'profile' != '{}'::jsonb
        AND jsonb_typeof(snapshot->'records') = 'array'
        AND jsonb_typeof(snapshot->'visits') = 'array'
        AND jsonb_typeof(snapshot->'bookings') = 'array'
        AND jsonb_typeof(snapshot->'recordings') = 'array'
        AND octet_length(snapshot::text) <= 8388608
    ))
);

-- MARK: - Original document/audio bytes scoped by owner and attachment identity
-- Per-owner aggregate quotas are enforced by the adapter while it holds the owner's row lock.
CREATE TABLE IF NOT EXISTS reva_attachments (
    owner_id TEXT NOT NULL REFERENCES reva_owner_state(owner_id) ON DELETE CASCADE,
    attachment_id TEXT NOT NULL CHECK (attachment_id ~ '^[A-Za-z0-9_-]{1,80}$'),
    filename TEXT NOT NULL CHECK (octet_length(filename) BETWEEN 1 AND 180 AND filename ~ '^[A-Za-z0-9 ._()-]+$' AND left(filename, 1) != '.' AND filename = btrim(filename)),
    content_type TEXT NOT NULL CHECK (length(content_type) BETWEEN 1 AND 100),
    bytes BYTEA NOT NULL CHECK (octet_length(bytes) BETWEEN 1 AND 16777216),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, attachment_id)
);

-- MARK: - Metadata-only mutation history
-- The adapter retains the most recent 128 entries per owner without copying patient text into audit rows.
CREATE TABLE IF NOT EXISTS reva_mutations (
    owner_id TEXT NOT NULL REFERENCES reva_owner_state(owner_id) ON DELETE CASCADE,
    mutation_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('state.put','state.delete','attachment.put','attachment.delete')),
    revision BIGINT NOT NULL CHECK (revision >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, mutation_id)
);

-- MARK: - Support bounded per-owner audit retention
CREATE INDEX IF NOT EXISTS reva_mutations_owner_created ON reva_mutations(owner_id, created_at DESC);
