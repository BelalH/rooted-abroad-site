CREATE TABLE IF NOT EXISTS leads (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  name          TEXT NOT NULL,
  email         TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('partner', 'buyer', 'other')),
  context       TEXT,
  referrer      TEXT,
  landing_query TEXT,
  country       TEXT,
  user_agent    TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS leads_email_unique ON leads (email);
CREATE INDEX IF NOT EXISTS leads_created_at ON leads (created_at);
