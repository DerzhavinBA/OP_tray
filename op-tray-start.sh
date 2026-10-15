#!/bin/bash
# OpenProject tray start — OP_ROOT from env (default /opt/openproject)
set -e
OP_ROOT="${OP_ROOT:-/opt/openproject}"
cd "$OP_ROOT"
mkdir -p log tmp/pids
{
  echo "[$(date -Is)] start begin root=$OP_ROOT"
  export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "[$(date -Is)] ERROR: nvm not found at $NVM_DIR" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm use 22 >/dev/null
  if pgrep -u "$USER" -f 'foreman start -f Procfile.dev' >/dev/null 2>&1 \
    || pgrep -u "$USER" -f 'overmind start -f Procfile.dev' >/dev/null 2>&1; then
    echo "[$(date -Is)] already running"
    exit 0
  fi
  # A new session keeps the stack alive when the calling wsl.exe session is torn down.
  setsid nohup bin/dev >> log/tray-dev.log 2>&1 < /dev/null &
  echo $! > log/tray-dev.pid
  echo "[$(date -Is)] started pid=$(cat log/tray-dev.pid)"
  sleep 3
  if ! kill -0 "$(cat log/tray-dev.pid)" 2>/dev/null; then
    echo "[$(date -Is)] ERROR: bin/dev exited right after start" >&2
    exit 1
  fi
} >> log/tray-dev.log 2>&1
