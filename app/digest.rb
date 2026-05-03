require 'cgi'
require 'time'
require_relative 'database'
require_relative 'logger'
require_relative 'sanitizer'

# Builds the daily-digest email body. Pulls every UNREAD article whose
# published_at falls within the last `window_hours`, joins each row to
# its feed (for the "from" label) and to its cached SummaryStore row
# (LLM if present, else extractive, else a content_text excerpt as a
# last-ditch fallback), and renders both a plain-text and a minimal
# HTML body.
#
# Stateless: the SQL is bounded by `window_hours` (default 24), so two
# runs in the same day will surface the same articles. That's a
# feature for ad-hoc `make digest` runs; for cron use, fire it once
# per day and the user gets one email.
#
# No mailing happens here. Hand the result to Mailer.deliver.
module Digest
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
      lines << "—"
      lines << "Open the app: open /articles?state=unread"
      lines.join("\n")
    end

    def build_html(rows, count, hours, now)
      header = <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8">
        <style>
          body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #1d1d1f; max-width: 680px; margin: 0 auto; padding: 24px; }
          h1 { font-size: 18px; margin: 0 0 4px; }
          .meta { color: #6e6e73; font-size: 13px; margin-bottom: 24px; }
          .item { padding: 12px 0; border-top: 1px solid #f0f0f5; }
          .item:first-of-type { border-top: none; }
          .title { font-weight: 600; font-size: 15px; }
          .title a { color: #1d1d1f; text-decoration: none; }
          .title a:hover { color: #0071e3; }
          .feed { color: #6e6e73; font-size: 13px; margin: 2px 0 6px; }
          .summary { color: #3a3a3c; font-size: 14px; }
          .empty { color: #6e6e73; padding: 24px 0; text-align: center; }
          .pod { background: #e9d6ff; color: #5e1f9c; padding: 1px 6px; border-radius: 4px; font-size: 11px; font-weight: 700; letter-spacing: 0.06em; margin-left: 6px; }
          footer { color: #8e8e93; font-size: 12px; margin-top: 32px; padding-top: 12px; border-top: 1px solid #f0f0f5; }
        </style>
        </head><body>
        <h1>Tech Feed Reader — Daily digest</h1>
        <div class="meta">Last #{hours} hours · #{count} unread</div>
      HTML

      body = if rows.empty?
        '<div class="empty">No new articles in the last %d hours.</div>' % hours
      else
        rows.map { |row| render_item_html(row, now) }.join("\n")
      end

      footer = <<~HTML
        <footer>Generated #{h(now.iso8601)} · open <code>/articles?state=unread</code> in the app.</footer>
        </body></html>
      HTML

      header + body + footer
    end

    def render_item_html(row, now)
      title    = h(row['title'].to_s)
      url      = h(row['url'].to_s)
      feed     = h(row['feed_title'].to_s)
      published = h(relative_when(row['published_at'], now))
      summary  = h(pick_summary(row))
      pod_badge = row['audio_url'] ? '<span class="pod">PODCAST</span>' : ''
      title_html = url.empty? ? title : %(<a href="#{url}" target="_blank" rel="noopener">#{title}</a>)
      <<~HTML
        <div class="item">
          <div class="title">#{title_html}#{pod_badge}</div>
          <div class="feed">#{feed} · #{published}</div>
          #{summary.empty? ? '' : %(<div class="summary">#{summary}</div>)}
        </div>
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
