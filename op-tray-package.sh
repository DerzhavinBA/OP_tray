#!/bin/bash
# Package-only management. No dev runtimes or process-name/port killing.
set -euo pipefail
export SYSTEMD_PAGER=cat
export SYSTEMD_COLORS=0
OP_ROOT="${OP_ROOT:-/opt/openproject}"
action="${1:-check}"
fail() { echo "[FAIL] $*" >&2; exit 1; }
check_package() {
  [ -x /usr/bin/openproject ] || fail 'Packaged CLI /usr/bin/openproject is missing'
  [ -d "$OP_ROOT" ] || fail "OpenProject directory missing: $OP_ROOT"
  [ -d /run/systemd/system ] || fail 'systemd is not running in this distro'
  local listing unit state rest web=0 worker=0
  listing=$(systemctl list-unit-files 'openproject*.service' --no-legend --no-pager) || fail 'Cannot enumerate OpenProject services'
  units=()
  leaves=()
  while read -r unit state rest; do
    if [[ "$unit" == openproject.service || "$unit" =~ ^openproject-[a-zA-Z0-9_-]+\.service$ ]]; then
      [ "$(systemctl show "$unit" -p LoadState --value)" = loaded ] || fail "Service not loaded: $unit"
      units+=("$unit")
      if [[ "$unit" =~ ^openproject-.+-[0-9]+\.service$ ]]; then leaves+=("$unit"); fi
      if [[ "$unit" =~ ^openproject-web-[0-9]+\.service$ ]]; then web=1; fi
      if [[ "$unit" =~ ^openproject-worker-[0-9]+\.service$ ]]; then worker=1; fi
    fi
  done <<< "$listing"
  [[ " ${units[*]} " == *' openproject.service '* ]] || fail 'openproject.service is missing'
  [ "$web" = 1 ] && [ "$worker" = 1 ] || fail 'Packaged web/worker instances are missing'
}
check_package
case "$action" in
  check) echo PACKAGE_OK ;;
  status)
    active=0; bad=0; detail=''
    for unit in "${leaves[@]}"; do
      state=$(systemctl show "$unit" -p ActiveState --value) || fail "Cannot read $unit"
      detail+=" $unit=$state"
      case "$state" in active) active=$((active+1));; inactive) :;; *) bad=1;; esac
    done
    if [ "$bad" = 0 ] && [ "$active" = "${#leaves[@]}" ]; then echo RUNNING
    elif [ "$bad" = 0 ] && [ "$active" = 0 ]; then echo STOPPED
    else echo "ERROR$detail"; fi ;;
  start|stop)
    [ "$(id -u)" = 0 ] || fail "$action requires root"
    mkdir -p "$OP_ROOT/log"
    { echo "[$(date -Is)] $action package services"; systemctl "$action" "${units[@]}"; } >> "$OP_ROOT/log/tray-service.log" 2>&1 || {
      tail -n 15 "$OP_ROOT/log/tray-service.log" >&2; exit 1;
    }
    if [ "$action" = stop ]; then
      for unit in "${units[@]}"; do
        state=$(systemctl show "$unit" -p ActiveState --value)
        [[ "$state" = inactive || "$state" = failed ]] || fail "Stop incomplete: $unit=$state"
      done
    fi ;;
  migrate)
    [ "$(id -u)" != 0 ] || fail 'Run migrations as the OpenProject user'
    mkdir -p "$OP_ROOT/log"
    { echo "[$(date -Is)] package db:migrate"; /usr/bin/openproject run bundle exec rails db:migrate; } 2>&1 | tee -a "$OP_ROOT/log/tray-prepare.log" ;;
  pending)
    output=$(/usr/bin/openproject run bundle exec rails db:migrate:status) || fail 'Cannot read migration status'
    printf '%s\n' "$output" | awk '/^[[:space:]]*down[[:space:]]+[0-9]+/ {n++} END {print n+0}' ;;
  doctor)
    echo '[OK] Packaged CLI and systemd web/worker units'
    /usr/bin/openproject run ruby -v
    systemctl --no-pager --full status "${units[@]}" || true
    pg_isready || fail 'PostgreSQL not ready' ;;
  journal) exec journalctl --no-pager -n "${2:-250}" -u 'openproject*.service' ;;
  follow) exec journalctl --no-pager -n 50 -f -u 'openproject*.service' ;;
  *) fail "Unknown action: $action" ;;
esac
