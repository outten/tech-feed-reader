#!/usr/bin/env bash
# Tear down whatever scripts/run_all.sh started:
#
#   1. Sidekiq worker (graceful: SIGTERM, then SIGKILL after 8s)
#   2. Web app        (same)
#   3. Redis — only if run_all.sh started it (.we_started_redis flag)
#   4. Jaeger container
#
# Idempotent — missing PID files / dead PIDs / absent containers are
# all logged but don't fail the script. Safe to run when nothing's up.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_DIR="$ROOT/tmp/pids"
WE_STARTED_REDIS_FLAG="$PID_DIR/.we_started_redis"

say()  { printf '\033[0;36m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m!\033[0m %s\n' "$*"; }

stop_bg() {
  local name="$1"
  local pid_file="$PID_DIR/$name.pid"

  if [ ! -f "$pid_file" ]; then
    warn "$name: no pid file"
    return 0
  fi

  local pid; pid=$(cat "$pid_file" 2>/dev/null || true)
  if [ -z "$pid" ]; then
    warn "$name: pid file empty"
    rm -f "$pid_file"
    return 0
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    warn "$name (pid $pid): already gone"
    rm -f "$pid_file"
    return 0
  fi

  say "Stopping $name (pid $pid)..."
  kill "$pid" 2>/dev/null || true
  # Reap any direct children (bundle exec wrapper edge cases).
  pkill -P "$pid" 2>/dev/null || true

  local i
  for i in $(seq 1 16); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done

  if kill -0 "$pid" 2>/dev/null; then
    warn "$name didn't exit gracefully — sending SIGKILL"
    kill -9 "$pid" 2>/dev/null || true
    pkill -9 -P "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

stop_bg sidekiq
stop_bg web

if [ -f "$WE_STARTED_REDIS_FLAG" ]; then
  stop_bg redis
  rm -f "$WE_STARTED_REDIS_FLAG"
else
  warn "Skipping Redis (not started by run-all)"
fi

if command -v docker >/dev/null 2>&1; then
  if docker ps -a --filter 'name=^jaeger$' --format '{{.Names}}' 2>/dev/null | grep -q '^jaeger$'; then
    say "Stopping Jaeger container..."
    docker rm -f jaeger >/dev/null 2>&1 || true
  else
    warn "no jaeger container to stop"
  fi
fi

say "All stopped."
