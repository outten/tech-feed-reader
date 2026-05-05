require 'time'
require_relative 'database'

# Per-feed weight signal. The user's "show more / show less from this
# source" controls bump the multiplier up or down by FEEDBACK_STEP per
# click. The Phase 6 ranker multiplies a feed's articles by the stored
# weight; until then this is purely data collection.
#
# Defaults / clamps:
#   default       1.0  (feeds with no row are treated as 1.0)
#   step          0.25 per :up / :down click
#   floor         0.25 (so :down can't silently zero a feed out — for
#                       hard hides see the future Mute-filter feature)
#   ceiling       3.0  (cap so a stack of 👍 doesn't dominate the ranker)
#
# Lazy: rows are only created when the user hits the bump endpoint.
# get_for / weights_by_feed_id return defaults for missing rows so the
# caller never has to special-case the no-row state.
module FeedFeedbackStore
  DEFAULT_WEIGHT = 1.0
  STEP           = 0.25
  FLOOR          = 0.25
  CEILING        = 3.0
  DIRECTIONS     = %i[up down reset].freeze

  module_function

  def db
    Database.connection
  end

  # Float weight for one feed. Returns DEFAULT_WEIGHT when no row.
  def weight_for(feed_id)
    row = db.execute('SELECT weight FROM feed_feedback WHERE feed_id = ?', [feed_id.to_i]).first
    row ? row['weight'].to_f : DEFAULT_WEIGHT
  end

  # Batch lookup keyed on feed_id. Used by the ranker (Phase 6) and
  # any view that needs to label many feed rows. Always returns a hash
  # the size of `feed_ids` — feeds without a stored weight default to
  # DEFAULT_WEIGHT.
  def weights_by_feed_id(feed_ids)
    ids = Array(feed_ids).map(&:to_i).uniq
    return {} if ids.empty?
    placeholders = (['?'] * ids.length).join(', ')
    rows = db.execute("SELECT feed_id, weight FROM feed_feedback WHERE feed_id IN (#{placeholders})", ids)
    stored = rows.each_with_object({}) { |r, h| h[r['feed_id']] = r['weight'].to_f }
    ids.each_with_object({}) { |id, h| h[id] = stored.fetch(id, DEFAULT_WEIGHT) }
  end

  # Bump the weight by ±STEP. direction must be in DIRECTIONS:
  #   :up    → weight += STEP, clamped at CEILING
  #   :down  → weight -= STEP, clamped at FLOOR
  #   :reset → weight = DEFAULT_WEIGHT (also deletes the row so the
  #            "no signal" state is observable downstream)
  # Returns the resulting Float weight.
  def bump(feed_id, direction:)
    raise ArgumentError, "direction must be one of #{DIRECTIONS.inspect} (got #{direction.inspect})" unless DIRECTIONS.include?(direction)
    fid = feed_id.to_i

    if direction == :reset
      db.execute('DELETE FROM feed_feedback WHERE feed_id = ?', [fid])
      return DEFAULT_WEIGHT
    end

    current = weight_for(fid)
    delta   = direction == :up ? STEP : -STEP
    nextval = (current + delta).clamp(FLOOR, CEILING)

    db.execute(<<~SQL, [fid, nextval, Time.now.utc.iso8601])
      INSERT INTO feed_feedback (feed_id, weight, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(feed_id) DO UPDATE SET weight = excluded.weight, updated_at = excluded.updated_at
    SQL

    nextval
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM feed_feedback').first['c']
  end
end
