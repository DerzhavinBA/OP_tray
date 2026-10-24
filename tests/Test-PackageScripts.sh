#!/bin/bash
# All commands are mocked; never operates real services or a database.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/app"
export OP_ROOT="$fixture/app" CALLS="$fixture/calls"
cat > "$fixture/bin/systemctl" <<'MOCK'
#!/bin/bash
case "$1" in
 list-unit-files) printf '%s enabled\n' openproject.service openproject-web.service openproject-web-1.service openproject-worker.service openproject-worker-1.service;;
 show) if [ "$4" = LoadState ]; then echo loaded; else case "$MODE:$2" in
 stopped:*) echo inactive;; partial:openproject-worker-1.service) echo failed;; *) echo active;; esac; fi;;
 start|stop) printf '%s\n' "$*" >> "$CALLS";;
 *) exit 3;;
esac
MOCK
cat > "$fixture/bin/id" <<'MOCK'
#!/bin/bash
echo "${TEST_UID:-0}"
MOCK
cat > "$fixture/bin/package-cli" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
 *db:migrate:status*) printf 'boot notice\n up 20261010 Example\n down 20261011 Pending\n down 20261012 Pending\n';;
 *) echo 'migration output';;
esac
exit "${CLI_EXIT:-0}"
MOCK
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH" MODE=running
sed "s|/usr/bin/openproject|$fixture/bin/package-cli|g" "$root/op-tray-package.sh" > "$fixture/package.sh"
test "$(bash "$fixture/package.sh" check)" = PACKAGE_OK
test "$(bash "$fixture/package.sh" status)" = RUNNING
export MODE=partial
[[ $(bash "$fixture/package.sh" status) == ERROR* ]]
export MODE=stopped
test "$(bash "$fixture/package.sh" status)" = STOPPED
bash "$fixture/package.sh" stop
grep -q '^stop openproject.service openproject-web.service openproject-web-1.service openproject-worker.service openproject-worker-1.service$' "$CALLS"
export MODE=running
bash "$fixture/package.sh" start
test "$(bash "$fixture/package.sh" pending)" = 2
export CLI_EXIT=1
if bash "$fixture/package.sh" pending > /dev/null 2>&1; then echo 'FAIL pending accepted CLI failure'; exit 1; fi
export TEST_UID=1000
if bash "$fixture/package.sh" migrate > /dev/null 2>&1; then echo 'FAIL migrate swallowed CLI failure'; exit 1; fi
grep -q 'run bundle exec rails db:migrate' "$CALLS"
test -s "$OP_ROOT/log/tray-prepare.log"
export CLI_EXIT=0
bash "$fixture/package.sh" migrate > /dev/null
if bash "$fixture/package.sh" stop > /dev/null 2>&1; then echo 'FAIL unprivileged stop'; exit 1; fi
echo 'PASS package shell: exact service targets, stopped/partial/running, CLI status, migration failure and logs'
