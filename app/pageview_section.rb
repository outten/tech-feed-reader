# STUFF #48.1 — derive a section bucket from a request path so the
# admin analytics page can render per-section aggregates without
# re-deriving on every query. The bucket is computed once at
# write-time (in RequestLogMiddleware), persisted, and indexed.
#
# Sections cover the user-meaningful surfaces. /admin gets its own
# bucket so admin browsing doesn't muddy "what are users reading"
# numbers; /auth covers sign-up + sign-in + the WebAuthn ceremony.
#
# Paths that don't match any pattern return nil ("other") — those
# fall into the page-level aggregate but not any per-section bar.
#
# IGNORE_PATTERNS is the noise filter: /health + /metrics + static
# assets. Those still emit a JSON log line via the middleware (for
# debugging), but we skip the pageview INSERT so the analytics
# table stays focused on user-facing pageviews.
module PageviewSection
  module_function

  # Ordered: the first matching pattern wins. /admin must come
  # before broader prefixes that might also match.
  PATTERNS = [
    ['admin',    %r{\A/admin(/|\z)}],
    ['auth',     %r{\A/(sign-up|sign-in|sign-out|account|api/auth)(/|\z)}],
    ['articles', %r{\A/(articles|article|bookmarks|search|topics|triage|digests)(/|\z)}],
    ['podcasts', %r{\A/(podcasts?|bus)(/|\z)}],
    ['youtube',  %r{\A/youtube(/|\z)}],
    ['sports',   %r{\A/sports(/|\z)}],
    ['feeds',    %r{\A/(feeds|tags)(/|\z)}],
    ['home',     %r{\A/(about)?\z}]
  ].freeze

  # Static assets + healthchecks + Prometheus scrape + the chat
  # widget's XHR endpoint (chatter, not "page" views). These never
  # land in the pageviews table.
  IGNORE_PATTERNS = [
    %r{\A/(health|metrics)\z},
    %r{\A/(style\.css|page-background\.js|global-player\.js|header-refresh\.js|chat-widget\.js|search-shortcut\.js|continue-progress\.js|feeds-filter\.js)(\?|\z)},
    %r{\A/img/},
    %r{\A/api/chat\b}
  ].freeze

  def for_path(path)
    return nil if path.nil? || path.empty?
    PATTERNS.each { |name, rx| return name if path =~ rx }
    nil
  end

  def ignore?(path)
    return true if path.nil? || path.empty?
    IGNORE_PATTERNS.any? { |rx| path =~ rx }
  end
end
