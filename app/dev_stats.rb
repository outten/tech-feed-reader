require 'json'
require 'time'
require 'open3'

# DevStats: parses Claude Code session transcripts from
# ~/.claude/projects/**/*.jsonl, aggregates token usage and cost, and
# joins it with git/PR activity for this repo so /admin/dev-stats can
# show what development costs and produces.
#
# All projects are rolled up for token/cost (the user runs Claude on
# multiple repos). Productivity metrics (commits, lines, PRs merged)
# are this repo only — that's where the running process has git access.
module DevStats
  TRANSCRIPTS_ROOT = File.expand_path('~/.claude/projects')

  # Anthropic published pricing per 1M tokens (USD). Update if rates
  # change. Models matched by substring (case-insensitive) so any
  # version of opus/sonnet/haiku picks up the right row.
  #
  # These rates produce an "API-equivalent cost" — i.e. what the usage
  # would cost billed at API rates. Claude Code subscribers (Pro / Max)
  # pay a flat monthly fee instead, so the actual bill is the
  # subscription amount, not this. The API-equivalent is still useful
  # as a per-session / per-day "value derived" signal.
  PRICING = {
    'opus'   => { input: 15.00, output: 75.00, cache_read: 1.50,  cache_write: 18.75 },
    'sonnet' => { input:  3.00, output: 15.00, cache_read: 0.30,  cache_write:  3.75 },
    'haiku'  => { input:  1.00, output:  5.00, cache_read: 0.10,  cache_write:  1.25 }
  }.freeze

  # Subscription tiers — flat monthly fee for Claude Code access.
  # Override the active tier with CLAUDE_SUBSCRIPTION_TIER=max5 etc.
  SUBSCRIPTIONS = {
    'pro'   => { label: 'Claude Pro',    monthly_usd: 20  },
    'max5'  => { label: 'Claude Max 5x', monthly_usd: 100 },
    'max20' => { label: 'Claude Max 20x',monthly_usd: 200 }
  }.freeze

  DEFAULT_SUBSCRIPTION = 'max20'.freeze

  def self.report
    by_day, by_project, by_model, sessions = aggregate_transcripts

    today = Date.today
    today_iso = today.iso8601
    week_ago = (today - 6)
    month_ago = (today - 29)
    calendar_month_start = Date.new(today.year, today.month, 1).iso8601

    mtd_totals = window_totals(by_day, calendar_month_start..today_iso)

    {
      generated_at: Time.now.utc.iso8601,
      totals: {
        today: window_totals(by_day, today_iso..today_iso),
        last_7: window_totals(by_day, week_ago.iso8601..today_iso),
        last_30: window_totals(by_day, month_ago.iso8601..today_iso),
        all_time: window_totals(by_day, nil),
        month_to_date: mtd_totals
      },
      subscription: subscription_summary(mtd_totals[:cost]),
      by_day: by_day.sort.reverse.first(30).to_h,
      by_project: by_project.sort_by { |_, v| -v[:cost] },
      by_model: by_model.sort_by { |_, v| -v[:cost] },
      session_count: sessions.size,
      git: git_activity(since_days: 30),
      prs: pr_activity(since_days: 30)
    }
  end

  def self.subscription_summary(month_api_equiv_cost)
    tier_key = (ENV['CLAUDE_SUBSCRIPTION_TIER'] || DEFAULT_SUBSCRIPTION).downcase
    tier = SUBSCRIPTIONS[tier_key] || SUBSCRIPTIONS[DEFAULT_SUBSCRIPTION]
    monthly = tier[:monthly_usd].to_f
    multiple = monthly.zero? ? 0.0 : (month_api_equiv_cost / monthly)
    savings = month_api_equiv_cost - monthly
    {
      tier_key: tier_key,
      label: tier[:label],
      monthly_usd: monthly,
      month_api_equiv_cost: month_api_equiv_cost,
      value_multiple: multiple,
      savings: savings,
      available_tiers: SUBSCRIPTIONS.keys
    }
  end

  def self.aggregate_transcripts
    by_day = Hash.new { |h, k| h[k] = empty_bucket }
    by_project = Hash.new { |h, k| h[k] = empty_bucket }
    by_model = Hash.new { |h, k| h[k] = empty_bucket }
    sessions = {}

    return [by_day, by_project, by_model, sessions] unless Dir.exist?(TRANSCRIPTS_ROOT)

    Dir.glob(File.join(TRANSCRIPTS_ROOT, '*', '*.jsonl')).each do |path|
      File.foreach(path) do |line|
        rec = parse_line(line) or next
        next unless rec[:tokens]

        day = rec[:timestamp].utc.to_date.iso8601
        project = rec[:project]
        model_key = model_bucket(rec[:model])

        add_to_bucket(by_day[day], rec)
        add_to_bucket(by_project[project], rec)
        add_to_bucket(by_model[model_key], rec)
        sessions[rec[:session_id]] = true if rec[:session_id]
      end
    rescue Errno::ENOENT, Errno::EACCES
      next
    end

    [by_day, by_project, by_model, sessions]
  end

  def self.parse_line(line)
    obj = JSON.parse(line)
    return nil unless obj['type'] == 'assistant'

    msg = obj['message'] or return nil
    usage = msg['usage'] or return nil

    input  = usage['input_tokens'].to_i
    output = usage['output_tokens'].to_i
    cache_r = usage['cache_read_input_tokens'].to_i
    cache_w = usage['cache_creation_input_tokens'].to_i

    return nil if input.zero? && output.zero? && cache_r.zero? && cache_w.zero?

    model = msg['model'].to_s
    cwd = obj['cwd'].to_s
    project = project_label(cwd)

    {
      timestamp: Time.parse(obj['timestamp']),
      model: model,
      project: project,
      session_id: obj['sessionId'],
      tokens: {
        input: input,
        output: output,
        cache_read: cache_r,
        cache_write: cache_w
      },
      cost: cost_for(model, input, output, cache_r, cache_w)
    }
  rescue JSON::ParserError, ArgumentError, TypeError
    nil
  end

  def self.project_label(cwd)
    return '(unknown)' if cwd.empty?
    cwd.sub(%r{^#{Regexp.escape(ENV['HOME'].to_s)}/?}, '~/')
  end

  def self.model_bucket(model)
    m = model.to_s.downcase
    return 'opus'   if m.include?('opus')
    return 'sonnet' if m.include?('sonnet')
    return 'haiku'  if m.include?('haiku')
    model.empty? ? '(unknown)' : model
  end

  def self.cost_for(model, input, output, cache_r, cache_w)
    rates = PRICING[model_bucket(model)] || PRICING['opus']
    (input      * rates[:input]       +
     output     * rates[:output]      +
     cache_r    * rates[:cache_read]  +
     cache_w    * rates[:cache_write]) / 1_000_000.0
  end

  def self.empty_bucket
    { input: 0, output: 0, cache_read: 0, cache_write: 0, cost: 0.0, messages: 0 }
  end

  def self.add_to_bucket(bucket, rec)
    bucket[:input]       += rec[:tokens][:input]
    bucket[:output]      += rec[:tokens][:output]
    bucket[:cache_read]  += rec[:tokens][:cache_read]
    bucket[:cache_write] += rec[:tokens][:cache_write]
    bucket[:cost]        += rec[:cost]
    bucket[:messages]    += 1
  end

  def self.window_totals(by_day, range)
    keys = range ? by_day.keys.select { |d| range.cover?(d) } : by_day.keys
    keys.each_with_object(empty_bucket) do |d, acc|
      b = by_day[d]
      acc[:input]       += b[:input]
      acc[:output]      += b[:output]
      acc[:cache_read]  += b[:cache_read]
      acc[:cache_write] += b[:cache_write]
      acc[:cost]        += b[:cost]
      acc[:messages]    += b[:messages]
    end
  end

  # Per-day commits + insertions/deletions from `git log --shortstat`.
  # Returns a hash keyed by ISO date.
  def self.git_activity(since_days:)
    out, status = Open3.capture2(
      'git', 'log',
      "--since=#{since_days} days ago",
      '--shortstat',
      "--pretty=format:__COMMIT__|%H|%aI|%s"
    )
    return {} unless status.success?

    by_day = Hash.new { |h, k| h[k] = { commits: 0, insertions: 0, deletions: 0 } }
    current_day = nil
    out.each_line do |raw|
      line = raw.strip
      if line.start_with?('__COMMIT__|')
        _, _sha, iso, _subject = line.split('|', 4)
        current_day = Time.parse(iso).utc.to_date.iso8601 rescue nil
        by_day[current_day][:commits] += 1 if current_day
      elsif current_day && line.match?(/files? changed/)
        ins = line[/(\d+) insertion/, 1].to_i
        del = line[/(\d+) deletion/, 1].to_i
        by_day[current_day][:insertions] += ins
        by_day[current_day][:deletions] += del
      end
    end
    by_day
  rescue StandardError
    {}
  end

  # PRs merged in the last N days via `gh`. Silently returns [] if `gh`
  # isn't installed or isn't authed against this repo.
  def self.pr_activity(since_days:)
    since_date = (Date.today - since_days).iso8601
    out, status = Open3.capture2(
      'gh', 'pr', 'list',
      '--state', 'merged',
      '--limit', '100',
      '--search', "merged:>=#{since_date}",
      '--json', 'number,title,mergedAt,additions,deletions,author'
    )
    return [] unless status.success?

    JSON.parse(out).map do |pr|
      {
        number: pr['number'],
        title: pr['title'],
        merged_at: pr['mergedAt'],
        merged_day: (Time.parse(pr['mergedAt']).utc.to_date.iso8601 rescue nil),
        additions: pr['additions'].to_i,
        deletions: pr['deletions'].to_i
      }
    end.sort_by { |pr| pr[:merged_at] || '' }.reverse
  rescue StandardError
    []
  end
end
