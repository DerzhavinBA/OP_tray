#!/bin/bash
# OpenProject tray doctor — prints OK/FAIL lines; exit 0 if critical checks pass.
# Must never be interactive (no prompts / pagers / GUIs).
set +e
export DEBIAN_FRONTEND=noninteractive
export GIT_PAGER=cat
export PAGER=cat
OP_ROOT="${OP_ROOT:-/opt/openproject}"
OP_HTTP_PORT="${OP_HTTP_PORT:-3000}"
fail=0

say() { printf '%s\n' "$1"; }

say "[CHK] OP_ROOT=$OP_ROOT user=$USER"
if [ -d "$OP_ROOT" ]; then
  say "[OK] root directory exists"
else
  say "[FAIL] root directory missing"
  fail=1
fi

if [ -f "$OP_ROOT/bin/dev" ]; then
  say "[OK] bin/dev present"
else
  say "[FAIL] bin/dev missing"
  fail=1
fi

if [ -f "$OP_ROOT/bin/rails" ]; then
  say "[OK] bin/rails present"
else
  say "[FAIL] bin/rails missing"
  fail=1
fi

export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
if command -v ruby >/dev/null 2>&1; then
  say "[OK] ruby=$(ruby -v 2>/dev/null | head -n1)"
else
  say "[FAIL] ruby not in PATH"
  fail=1
fi

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
  nvm use 22 >/dev/null 2>&1 || true
  if command -v node >/dev/null 2>&1; then
    say "[OK] node=$(node -v 2>/dev/null)"
  else
    say "[FAIL] node not available after nvm"
    fail=1
  fi
else
  say "[FAIL] nvm not found at $NVM_DIR"
  fail=1
fi

if command -v pg_isready >/dev/null 2>&1 && pg_isready -q 2>/dev/null; then
  say "[OK] postgres ready (pg_isready)"
else
  say "[FAIL] postgres not ready"
  fail=1
fi

for port in "$OP_HTTP_PORT" 4200 1234; do
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | grep -qE ":${port}\\b"; then
      say "[OK] port $port listening (ss)"
    else
      say "[INFO] port $port not listening"
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -ltn 2>/dev/null | grep -qE ":${port}\\b"; then
      say "[OK] port $port listening (netstat)"
    else
      say "[INFO] port $port not listening"
    fi
  else
    say "[INFO] cannot probe port $port (no ss/netstat)"
  fi
done

if pgrep -u "$USER" -f 'foreman start -f Procfile.dev|overmind start -f Procfile.dev|bin/dev' >/dev/null 2>&1; then
  say "[OK] Procfile.dev / bin/dev process detected"
else
  say "[INFO] no Procfile.dev stack process"
fi

if [ "$fail" -eq 0 ]; then
  say "[SUMMARY] critical checks passed"
  exit 0
fi
say "[SUMMARY] critical checks FAILED"
exit 1
