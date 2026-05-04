require 'cgi'
require 'time'
require_relative 'database'
require_relative 'logger'

# Builds a daily digest of the user's unread articles. Pulls every
# UNREAD row whose published_at falls within the last `window_hours`,
# joins each to its feed (for the "from" label) and to its cached
# SummaryStore row (LLM if present, else extractive, else a
# content_text excerpt as a last-ditch fallback). Renders both a
# plain-text body (kept for ops legibility / future email re-use) and
# an HTML fragment that drops directly into the /digests/:id page.
#
# Module name is plural to avoid clashing with Ruby's built-in
# `Digest` (SHA1, MD5, …). Storage lives in DigestStore; this module
# is purely the composer.
module Digests
  Result = Struct.new(:subject, :text, :html, :count, :window_hours, :generated_at, keyword_init: true)

  DEFAULT_WINDOW_HOURS = 24
  DEFAULT_LIMIT        = 25
  EXCERPT_FALLBACK     = 240   # chars from content_text if no summary exists

  module_function

  def compose(window_hours: DEFAULT_WINDOW_HOURS, limit: DEFAULT_LIMIT, now: Time.now.utc)
    rows  = query_unread(window_hours: window_hours, limit: limit, now: now)
    count = rows.length
    AppLogger.info('digest_compose', count: count, window_hours: window_hours, limit: limit)

    Result.new(
      subject:      build_subject(count, window_hours, now),
      text:         build_text(rows, count, window_hours, now),
      html:         build_html(rows, count, window_hours, now),
      count:        count,
      window_hours: window_hours,
      generated_at: now
    )
  end

  # Compose + persist. Returns [id, Result] so callers can log the
  # row id and report the count in one go.
  def generate_and_store!(window_hours: DEFAULT_WINDOW_HOURS, limit: DEFAULT_LIMIT, now: Time.now.utc)
    require_relative 'digest_store'
    result = compose(window_hours: window_hours, limit: limit, now: now)
    id = DigestStore.create(result)
    [id, result]
  end

  # Exposed for specs; pulls the raw rows + their summary fields.
  def query_unread(window_hours:, limit:, now: Time.now.utc)
    cutoff = (now - (window_hours * 3600)).iso8601
    Database.connection.execute(<<~SQL, [cutoff, limit])
      SELECT a.id, a.uid, a.title, a.url, a.published_at, a.content_text,
             a.audio_url,
             f.title AS feed_title,
             s.llm   AS summary_llm,
             s.extractive AS summary_extractive
      FROM articles a
      JOIN feeds  f ON f.id = a.feed_id
      LEFT JOIN read_state rs ON rs.article_id = a.id
      LEFT JOIN summaries  s  ON s.article_id  = a.id
      WHERE COALESCE(rs.read, 0) = 0
        AND a.published_at >= ?
      ORDER BY a.published_at DESC
      LIMIT ?
    SQL
  end

  # ------------------------------------------------------------------
  class << self
    private

    def build_subject(count, hours, now)
      day = now.localtime.strftime('%a %b %-d')
      if count.zero?
        "Tech Feed Reader — no new articles (#{day})"
      else
        plural = count == 1 ? '' : 's'
        "Tech Feed Reader — #{count} new article#{plural} (#{day})"
      end
    end

    def build_text(rows, count, hours, now)
      lines = []
      lines << "Tech Feed Reader — Daily digest"
      lines << "Generated #{now.iso8601} · last #{hours}h · #{count} unread"
      lines << ""
      if rows.empty?
        lines << "Nothing new in the last #{hours} hours."
      else
        rows.each_with_index do |row, idx|
          lines << "#{idx + 1}. #{row['title']}"
          lines << "   #{row['feed_title']} · #{relative_when(row['published_at'], now)}#{row['audio_url'] ? ' · 🎧 podcast' : ''}"
          lines << "   #{row['url']}" if row['url'] && !row['url'].to_s.empty?
          summary = pick_summary(row)
          lines << "   #{summary}" unless summary.empty?
          lines << ""
        end
      end
      lines.join("\n")
    end

    # HTML fragment (no <html>/<head>/<body>/<style>) using app CSS
    # classes — drops directly into views/digest.erb under <main>.
    def build_html(rows, count, hours, now)
      header = <<~HTML
        <div class="digest-meta muted">
          Generated #{h(now.iso8601)} · last #{hours}h · #{count} unread
        </div>
      HTML

      body = if rows.empty?
        '<div class="empty-state">No new articles in the last %d hours.</div>' % hours
      else
        '<ol class="digest-items">' + rows.map { |row| render_item_html(row, now) }.join + '</ol>'
      end

      header + body
    end

    def render_item_html(row, now)
      title    = h(row['title'].to_s)
      url      = h(row['url'].to_s)
      feed     = h(row['feed_title'].to_s)
      published = h(relative_when(row['published_at'], now))
      summary  = h(pick_summary(row))
      pod_badge = row['audio_url'] ? ' <span class="badge podcast-badge">PODCAST</span>' : ''
      title_html = url.empty? ? title : %(<a href="#{url}" target="_blank" rel="noopener">#{title}</a>)
      <<~HTML
        <li class="digest-item">
          <div class="digest-item-title">#{title_html}#{pod_badge}</div>
          <div class="digest-item-meta muted">#{feed} · #{published}</div>
          #{summary.empty? ? '' : %(<div class="digest-item-summary">#{summary}</div>)}
        </li>
      HTML
    end

    def pick_summary(row)
      return row['summary_llm'].to_s.strip       unless row['summary_llm'].to_s.strip.empty?
      return row['summary_extractive'].to_s.strip unless row['summary_extractive'].to_s.strip.empty?
      excerpt = row['content_text'].to_s.strip
      return '' if excerpt.empty?
      excerpt.length > EXCERPT_FALLBACK ? "#{excerpt[0, EXCERPT_FALLBACK].rstrip}…" : excerpt
    end

    def relative_when(iso, now)
      return '—' if iso.nil? || iso.to_s.empty?
      t = (Time.parse(iso.to_s) rescue nil)
      return '—' unless t
      diff = now - t
      case diff
      when 0..3600        then "#{[(diff / 60).round, 1].max}m ago"
      when 3601..86_400   then "#{(diff / 3600).round}h ago"
      else                     "#{(diff / 86_400).round}d ago"
      end
    end

    def h(str)
      CGI.escapeHTML(str.to_s)
    end
  end
end
