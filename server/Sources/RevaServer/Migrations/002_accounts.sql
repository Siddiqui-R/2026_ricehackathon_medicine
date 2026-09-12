-- Purpose: Define schema v2 for account users and their hashed session tokens.
-- Inputs: This checked-in SQL is loaded by PostgresStore.migrate after 001_snapshot under the same advisory lock.
-- Outputs: User and session tables whose constraints mirror the server's normalization and hashing policy.
-- Side effects: Creates database objects. Schema-version bookkeeping is handled by the migration runner.
-- Ownership: Only bcrypt hashes and SHA-256 token hashes are stored; runtime queries bind every value as a parameter.
-- The user ID doubles as the owner ID of reva_owner_state, so account deletion also deletes that owner row.

-- MARK: - Accounts with normalized unique emails and bcrypt password hashes
CREATE TABLE IF NOT EXISTS reva_users (
    user_id TEXT PRIMARY KEY CHECK (user_id ~ '^[A-Za-z0-9_-]{1,80}$'),
    email TEXT NOT NULL UNIQUE CHECK (email = lower(email) AND length(email) BETWEEN 3 AND 254),
    display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 80),
    password_hash TEXT NOT NULL CHECK (password_hash LIKE '$2%' AND length(password_hash) BETWEEN 59 AND 72),
    password_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- MARK: - Opaque sessions stored by token hash with expiry and revocation
-- Deleting a user cascades to its sessions; the adapter revokes the oldest sessions beyond 20 live ones.
CREATE TABLE IF NOT EXISTS reva_sessions (
    session_id UUID PRIMARY KEY,
    token_hash TEXT NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    user_id TEXT NOT NULL REFERENCES reva_users(user_id) ON DELETE CASCADE,
    label TEXT NOT NULL DEFAULT '' CHECK (length(label) <= 120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

-- MARK: - Support per-user session listing, capping, and revocation
CREATE INDEX IF NOT EXISTS reva_sessions_user ON reva_sessions(user_id);
