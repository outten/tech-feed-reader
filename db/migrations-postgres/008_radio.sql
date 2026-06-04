-- Internet radio stations catalog + per-user follows
CREATE TABLE IF NOT EXISTS radio_stations (
  id          BIGSERIAL    PRIMARY KEY,
  name        VARCHAR(120) NOT NULL,
  description TEXT,
  genre       VARCHAR(60),
  stream_url  TEXT         NOT NULL UNIQUE,
  image_url   TEXT,
  home_url    TEXT,
  catalog     VARCHAR(40)  NOT NULL DEFAULT 'catalog',
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS radio_follows (
  id          BIGSERIAL    PRIMARY KEY,
  user_id     BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  station_id  BIGINT       NOT NULL REFERENCES radio_stations(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE(user_id, station_id)
);
