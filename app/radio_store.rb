module RadioStore
  extend self

  # ── catalog ───────────────────────────────────────────────────────────────

  # Seed catalog stations into DB (idempotent — ON CONFLICT DO NOTHING).
  def seed_catalog!
    RadioCatalog::STATIONS.each do |s|
      db.execute(
        'INSERT INTO radio_stations (name, description, genre, stream_url, image_url, home_url, catalog)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (stream_url) DO UPDATE
           SET name=$1, description=$2, genre=$3, image_url=$5, home_url=$6, catalog=$7',
        [s[:name], s[:description], s[:genre], s[:stream_url],
         s[:image_url], s[:home_url], s[:catalog]]
      )
    end
  end

  def all_stations
    db.execute('SELECT * FROM radio_stations ORDER BY catalog, name')
  end

  def find(id)
    db.execute('SELECT * FROM radio_stations WHERE id = $1', [id.to_i]).first
  end

  def stations_by_group
    all_stations.group_by { |s| s['catalog'] }
  end

  # Top N stations ranked by follower count across all users.
  def popular_stations(limit: 5)
    db.execute(
      'SELECT rs.*, COUNT(rf.user_id) AS follower_count
       FROM radio_stations rs
       LEFT JOIN radio_follows rf ON rf.station_id = rs.id
       GROUP BY rs.id
       ORDER BY follower_count DESC, rs.name ASC
       LIMIT $1',
      [limit]
    )
  end

  # ── follows ───────────────────────────────────────────────────────────────

  def followed_stations(user_id)
    db.execute(
      'SELECT rs.* FROM radio_stations rs
       JOIN radio_follows rf ON rf.station_id = rs.id
       WHERE rf.user_id = $1
       ORDER BY rs.catalog, rs.name',
      [user_id]
    )
  end

  def following?(user_id, station_id)
    db.execute(
      'SELECT 1 FROM radio_follows WHERE user_id = $1 AND station_id = $2',
      [user_id, station_id.to_i]
    ).any?
  end

  def follow!(user_id, station_id)
    db.execute(
      'INSERT INTO radio_follows (user_id, station_id) VALUES ($1,$2)
       ON CONFLICT (user_id, station_id) DO NOTHING',
      [user_id, station_id.to_i]
    )
  end

  def unfollow!(user_id, station_id)
    db.execute(
      'DELETE FROM radio_follows WHERE user_id = $1 AND station_id = $2',
      [user_id, station_id.to_i]
    )
  end

  private

  def db
    Database.connection
  end
end
