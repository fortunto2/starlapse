-- One row per contributed shot. Location is rounded on the phone to 0.1° (~10 km)
-- before it is sent; the server never sees anything finer.
CREATE TABLE IF NOT EXISTS observations (
  id TEXT PRIMARY KEY,
  contributor TEXT NOT NULL,
  received_at TEXT NOT NULL,
  taken_at TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('stack', 'meteors')),
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  sky_brightness REAL,
  uncertainty REAL,
  naked_eye_limit REAL,
  bortle INTEGER,
  stack_limit REAL,
  matched_stars INTEGER,
  altitude REAL,
  azimuth REAL,
  camera TEXT NOT NULL,
  meteors TEXT,
  photo_key TEXT,
  app_version TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS observations_contributor ON observations (contributor);
CREATE INDEX IF NOT EXISTS observations_taken ON observations (taken_at);
