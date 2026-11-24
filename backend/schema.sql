CREATE TABLE IF NOT EXISTS events (
  id          TEXT PRIMARY KEY,          -- generated on the watch; makes retries idempotent
  start_ts    INTEGER NOT NULL,          -- epoch seconds (UTC)
  end_ts      INTEGER NOT NULL,
  first_side  TEXT NOT NULL CHECK (first_side IN ('L','R')),
  left_s      INTEGER NOT NULL DEFAULT 0,
  right_s     INTEGER NOT NULL DEFAULT 0,
  device      TEXT,
  created_at  INTEGER NOT NULL,
  imported_at INTEGER,                   -- set when a batch containing it is acked
  deleted     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_events_pending ON events (imported_at, deleted, start_ts);

CREATE TABLE IF NOT EXISTS batches (
  id         TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  event_ids  TEXT NOT NULL,              -- JSON array of event ids
  acked_at   INTEGER
);

-- live state of a feed that is still running on a watch (one row per watch)
CREATE TABLE IF NOT EXISTS active (
  device      TEXT PRIMARY KEY,
  start_ts    INTEGER NOT NULL,
  first_side  TEXT NOT NULL,
  side        TEXT NOT NULL,          -- side currently being timed
  left_s      INTEGER NOT NULL,       -- banked seconds (excluding the live segment)
  right_s     INTEGER NOT NULL,
  run_ts      INTEGER NOT NULL,       -- start of live segment, -1 when paused
  paused_at   INTEGER NOT NULL,       -- -1 when running
  updated_at  INTEGER NOT NULL
);
