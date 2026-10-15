#!/bin/bash
# OpenProject tray stop (only current user's Procfile.dev stack)
# OP_ROOT from env (default /opt/openproject)
set +e
OP_ROOT="${OP_ROOT:-/opt/openproject}"
cd "$OP_ROOT" || exit 0
mkdir -p log
echo "[$(date -Is)] stop begin root=$OP_ROOT" >> log/tray-dev.log
pkill -u "$USER" -f 'bin/dev' 2>/dev/null
pkill -u "$USER" -f 'foreman start' 2>/dev/null
pkill -u "$USER" -f 'overmind start' 2>/dev/null
pkill -u "$USER" -f 'rails server' 2>/dev/null
pkill -u "$USER" -f 'puma' 2>/dev/null
pkill -u "$USER" -f 'good_job' 2>/dev/null
pkill -u "$USER" -f 'ng serve' 2>/dev/null
pkill -u "$USER" -f '@angular/cli' 2>/dev/null
pkill -u "$USER" -f 'op-blocknote-hocuspocus' 2>/dev/null
pkill -u "$USER" -f 'tsx watch' 2>/dev/null
sleep 1
if command -v fuser >/dev/null 2>&1; then
  for port in 3000 4200 1234; do
    fuser -k "${port}/tcp" 2>/dev/null
  done
fi
rm -f tmp/pids/server.pid log/tray-dev.pid
echo "[$(date -Is)] stop done" >> log/tray-dev.log
exit 0
