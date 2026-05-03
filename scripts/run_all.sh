#!/usr/bin/env bash
# Boot the full local dev stack in the background:
#
#   1. Jaeger all-in-one (Docker container — OTLP receiver + UI)
#   2. Redis             (only if not already up; we don't touch a
#                         pre-existing Redis on stop-all)
#   3. Web app           (Sinatra+Puma, OTLP env wired)
#   4. Sidekiq worker    (OTLP env wired so feed.fetch + llm.summarize
#                         spans flow to Jaeger)
#   5. Opens browser tabs for the app + Jaeger UI once both are healthy
#
# PID files in tmp/pids/<name>.pid, logs in tmp/logs/<name>.log so
# stop_all.sh can find + kill them and you can `tail -f tmp/logs/web.log`
# to debug a startup failure. Re-running this script is safe — running
# processes are detected and skipped.
#
# Stop the stack with: make stop-all

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_DIR="$ROOT/tmp/pids"
LOG_DIR="$ROOT/tmp/logs"
WE_STARTED_REDIS_FLAG="$PID_DIR/.we_started_redis"
mkdir -p "$PID_DIR" "$LOG_DIR"

# ---- pretty output -----------------------------------------------------
say()  { printf '\033[0;36m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m!\033[0m %s\n' "$*"; }
err()  { printf '\033[0;31m✗\033[0m %s\n' "$*" >&2; }

is_running() {
  local pid_file="$1"
  [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null
}

# Background a command with env vars, tee its output to a log, write the
# PID to a file. `env` lets us prefix arbitrary VAR=val pairs in the
# argv array passed in.
start_bg() {
  local name="$1"; shift
  local pid_file="$PID_DIR/$name.pid"
  local log_file="$LOG_DIR/$name.log"

  if is_running "$pid_file"; then
    warn "$name already running (pid $(cat "$pid_file"))"
    return 0
  fi

  : > "$log_file"
  ( cd "$ROOT" && "$@" >>"$log_file" 2>&1 ) &
  echo $! > "$pid_file"
  say "$name started (pid $(cat "$pid_file"), log: $log_file)"
}

wait_for_url() {
  local url="$1"; local label="$2"; local max_tries="${3:-60}"
  local i
  for i in $(seq 1 "$max_tries"); do
    if curl -sf -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  else
    warn "no 'open' or 'xdg-open' found — open $url manually"
  fi
}

# ---- 1. Jaeger ---------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  err "docker not found — install Docker Desktop (or set SKIP_JAEGER=1)"
  [ "${SKIP_JAEGER:-0}" = "1" ] || exit 1
fi

if [ "${SKIP_JAEGER:-0}" != "1" ]; then
  if docker ps --filter 'name=^jaeger$' --format '{{.Names}}' 2>/dev/null | grep -q '^jaeger$'; then
    warn "jaeger container already running"
  else
    say "Starting Jaeger (Docker)..."
    docker rm -f jaeger >/dev/null 2>&1 || true
    docker run -d --name jaeger \
      -p 16686:16686 -p 4317:4317 -p 4318:4318 \
      jaegertracing/all-in-one:latest >/dev/null
    say "jaeger container started"
  fi
fi

# ---- 2. Redis ----------------------------------------------------------
if redis-cli ping >/dev/null 2>&1; then
  warn "Redis already running (not started by us — leaving alone on stop)"
  rm -f "$WE_STARTED_REDIS_FLAG"
else
  say "Starting Redis..."
  start_bg redis redis-server --save '' --appendonly no
  touch "$WE_STARTED_REDIS_FLAG"
  for _ in $(seq 1 20); do
    redis-cli ping >/dev/null 2>&1 && break
    sleep 0.25
  done
  if ! redis-cli ping >/dev/null 2>&1; then
    err "Redis didn't come up. Check $LOG_DIR/redis.log"
    exit 1
  fi
fi

# ---- 3. Web app --------------------------------------------------------
say "Starting web app (Puma + OTel)..."
start_bg web env \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  OTEL_SERVICE_NAME=tech-feed-reader \
  bundle exec ruby app/main.rb

# ---- 4. Sidekiq worker -------------------------------------------------
say "Starting Sidekiq worker (OTel)..."
start_bg sidekiq env \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  OTEL_SERVICE_NAME=tech-feed-reader \
  bundle exec sidekiq -r ./app/sidekiq_boot.rb -c 5

# ---- 5. Wait for readiness + open browser ------------------------------
say "Waiting for web app on :4567..."
if ! wait_for_url 'http://localhost:4567/health' 'web' 60; then
  err "Web app did not respond within 30s. Check $LOG_DIR/web.log"
  exit 1
fi

if [ "${SKIP_JAEGER:-0}" != "1" ]; then
  say "Waiting for Jaeger UI on :16686..."
  if ! wait_for_url 'http://localhost:16686' 'jaeger' 60; then
    warn "Jaeger UI didn't respond within 30s; continuing anyway"
  fi
fi

say "Opening browser tabs..."
open_url 'http://localhost:4567'
sleep 0.3
[ "${SKIP_JAEGER:-0}" = "1" ] || open_url 'http://localhost:16686'

cat <<EOF

  All services up.
    App:        http://localhost:4567
    Admin:      http://localhost:4567/admin
    Traces:     http://localhost:4567/admin/traces  (in-memory)
    Jaeger UI:  http://localhost:16686             (OTLP-exported)

  Logs:  tail -f tmp/logs/{web,sidekiq,redis}.log
  PIDs:  $PID_DIR
  Stop:  make stop-all

EOF
