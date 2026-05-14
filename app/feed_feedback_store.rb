require 'time'
require_relative 'database'

# Per-(user, feed) weight signal. The user's "show more / show less from
# this source" controls bump the multiplier up or down by FEEDBACK_STEP
# per click. The Phase 6 ranker multiplies a feed's articles by the
# stored weight; until then this is purely data collection.
#
# Defaults / clamps:
#   default       1.0  (feeds with no row are treated as 1.0)
#   step          0.25 per :up / :down click
#   floor         0.25 (so :down can't silently zero a feed out — for
#                       hard hides see the Mute-filter feature)
#   ceiling       3.0  (cap so a stack of 👍 doesn't dominate the ranker)
#
# Lazy: rows are only created when the user hits the bump endpoint.
# weight_for / weights_by_feed_id return defaults for missing rows so the
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

  def weight_for(user_id, feed_id)
    row = db.execute(
      'SELECT weight FROM feed_feedback WHERE user_id = ? AND feed_id = ?',
      [user_id.to_i, feed_id.to_i]
    ).first
    row ? row['weight'].to_f : DEFAULT_WEIGHT
  end

  def weights_by_feed_id(user_id, feed_ids)
    ids = Array(feed_ids).map(&:to_i).uniq
    return {} if ids.empty?
    placeholders = (['?'] * ids.length).join(', ')
    rows = db.execute(
      "SELECT feed_id, weight FROM feed_feedback WHERE user_id = ? AND feed_id IN (#{placeholders})",
      [user_id.to_i] + ids
    )
    stored = rows.each_with_object({}) { |r, h| h[r['feed_id']] = r['weight'].to_f }
    ids.each_with_object({}) { |id, h| h[id] = stored.fetch(id, DEFAULT_WEIGHT) }
  end

  def bump(user_id, feed_id, direction:)
    raise ArgumentError, "direction must be one of #{DIRECTIONS.inspect} (got #{direction.inspect})" unless DIRECTIONS.include?(direction)
    uid = user_id.to_i
    fid = feed_id.to_i

    if direction == :reset
      db.execute('DELETE FROM feed_feedback WHERE user_id = ? AND feed_id = ?', [uid, fid])
      return DEFAULT_WEIGHT
    end

    current = weight_for(uid, fid)
    delta   = direction == :up ? STEP : -STEP
    nextval = (current + delta).clamp(FLOOR, CEILING)

    db.execute(<<~SQL, [uid, fid, nextval, Time.now.utc.iso8601])
      INSERT INTO feed_feedback (user_id, feed_id, weight, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(user_id, feed_id) DO UPDATE SET weight = excluded.weight, updated_at = excluded.updated_at
    SQL

    nextval
  end

  def count(user_id)
    db.execute('SELECT COUNT(*) AS c FROM feed_feedback WHERE user_id = ?', [user_id.to_i]).first['c']
  end
end
