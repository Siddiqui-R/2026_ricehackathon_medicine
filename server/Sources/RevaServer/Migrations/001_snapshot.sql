-- Reva aggregate schema v1. All prototype domain arrays live in snapshot.
-- Snapshots and source/audio bytes are owner-scoped and committed transactionally.
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
CREATE TABLE IF NOT EXISTS reva_attachments (
    owner_id TEXT NOT NULL REFERENCES reva_owner_state(owner_id) ON DELETE CASCADE,
    attachment_id TEXT NOT NULL CHECK (attachment_id ~ '^[A-Za-z0-9_-]{1,80}$'),
    filename TEXT NOT NULL CHECK (octet_length(filename) BETWEEN 1 AND 180 AND filename ~ '^[A-Za-z0-9 ._()-]+$' AND left(filename, 1) != '.' AND filename = btrim(filename)),
    content_type TEXT NOT NULL CHECK (length(content_type) BETWEEN 1 AND 100),
    bytes BYTEA NOT NULL CHECK (octet_length(bytes) BETWEEN 1 AND 16777216),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, attachment_id)
);
CREATE TABLE IF NOT EXISTS reva_mutations (
    owner_id TEXT NOT NULL REFERENCES reva_owner_state(owner_id) ON DELETE CASCADE,
    mutation_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('state.put','state.delete','attachment.put','attachment.delete')),
    revision BIGINT NOT NULL CHECK (revision >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, mutation_id)
);
CREATE INDEX IF NOT EXISTS reva_mutations_owner_created ON reva_mutations(owner_id, created_at DESC);
