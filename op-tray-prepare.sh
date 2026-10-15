#!/bin/bash
# OpenProject tray prepare: bundle install + db:migrate
# OP_ROOT from env (default /opt/openproject)
set -e
OP_ROOT="${OP_ROOT:-/opt/openproject}"
cd "$OP_ROOT"
mkdir -p log
LOG="$OP_ROOT/log/tray-prepare.log"
{
  echo "[$(date -Is)] prepare begin root=$OP_ROOT"
  export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
  export NVM_DIR="$HOME/.nvm"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    nvm use 22 >/dev/null || true
  fi
  echo "[$(date -Is)] bundle install"
  bundle install
  echo "[$(date -Is)] bin/rails db:migrate"
  bin/rails db:migrate
  echo "[$(date -Is)] prepare done"
} >> "$LOG" 2>&1
