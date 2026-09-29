#!/bin/sh
# Tests for scripts/decision-lease.sh -- fixtures in a temp dir, no network.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
lease="$script_dir/decision-lease.sh"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/grimdex-lease-test.XXXXXX")
export GRIMDEX_ROOT="$sandbox"
failures=0

assert() {
    label="$1"; cond="$2"
    if [ "$cond" = "0" ]; then echo "PASS  $label"; else echo "FAIL  $label"; failures=$((failures + 1)); fi
}

mkdir -p "$sandbox/projects/p1/decisions"
printf '# d001\n' > "$sandbox/projects/p1/decisions/d001-first.md"
printf '# d002\n' > "$sandbox/projects/p1/decisions/d002-second.md"

# ---------- claim skips existing committed numbers ----------
got=$(sh "$lease" claim p1 --tag t1)
[ "$got" = "d003" ]; assert 'claim skips committed d001/d002 -> d003' $?

# ---------- next claim advances past the lease, not just committed files ----------
got2=$(sh "$lease" claim p1 --tag t2)
[ "$got2" = "d004" ]; assert 'second claim advances to d004' $?

# ---------- release removes the lease; a subsequent claim does NOT reuse it ----------
sh "$lease" release p1 d003
[ ! -e "$sandbox/projects/p1/decisions/.leases/d003.lease" ]; assert 'release removes the lease file' $?
got3=$(sh "$lease" claim p1 --tag t3)
[ "$got3" = "d005" ]; assert 'released number is not reused (max still counts d004)' $?

# ---------- release on a number with no lease is a harmless no-op ----------
sh "$lease" release p1 d999
assert 'release of nonexistent lease does not error' $?

# ---------- concurrent claims never collide ----------
outdir=$(mktemp -d "${TMPDIR:-/tmp}/grimdex-lease-race.XXXXXX")
i=1
while [ "$i" -le 15 ]; do
    ( sh "$lease" claim p1 --tag "race-$i" > "$outdir/$i.out" ) &
    i=$((i + 1))
done
wait
dupes=$(cat "$outdir"/*.out | sort | uniq -d | wc -l | tr -d ' ')
[ "$dupes" = "0" ]; assert '15 concurrent claims -> zero duplicate numbers' $?
uniq_count=$(cat "$outdir"/*.out | sort -u | wc -l | tr -d ' ')
[ "$uniq_count" = "15" ]; assert '15 concurrent claims -> 15 distinct numbers' $?

# ---------- reap: expired lease removed, recent lease kept + flagged ----------
old_lease="$sandbox/projects/p1/decisions/.leases/d900.lease"
printf 'pid=1\nhost=h\nts=x\ntag=old\n' > "$old_lease"
touch -t 202601010000 "$old_lease"
recent_lease="$sandbox/projects/p1/decisions/.leases/d901.lease"
printf 'pid=1\nhost=h\nts=x\ntag=recent\n' > "$recent_lease"
touch -t "$(date -v-45M +%Y%m%d%H%M 2>/dev/null || date -d '-45 minutes' +%Y%m%d%H%M)" "$recent_lease"
out=$(sh "$lease" reap p1)
echo "$out" | grep -q 'reaped: d900'; assert 'reap removes an expired (>2h) lease' $?
[ ! -e "$old_lease" ]; assert 'expired lease file actually gone' $?
echo "$out" | grep -q 'stale-warning: d901'; assert 'reap flags (not removes) a 30-90min-old live lease' $?
[ -e "$recent_lease" ]; assert 'recent lease file untouched' $?
rm -f "$recent_lease"

# ---------- reap-all walks every project with a .leases dir ----------
mkdir -p "$sandbox/projects/p2/decisions"
sh "$lease" claim p2 --tag other > /dev/null
p2_lease="$sandbox/projects/p2/decisions/.leases/d001.lease"
touch -t 202601010000 "$p2_lease"
out=$(sh "$lease" reap-all)
echo "$out" | grep -q 'reaped: d001 (age .*, project p2)'; assert 'reap-all reaches a second project' $?

# ---------- claiming in a project with no decisions/ dir yet still works ----------
got4=$(sh "$lease" claim brand-new --tag fresh)
[ "$got4" = "d001" ]; assert 'fresh project with no decisions dir -> d001' $?

# ---------- usage/error paths exit non-zero, do not crash the shell ----------
# (set +e for this block: each of these is EXPECTED to return nonzero, and a bare
# `cmd; rc=$?` still trips `set -e` on cmd's own failure before rc=$? ever runs.)
set +e
sh "$lease" >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ]; assert 'no subcommand -> exit 2' $?
set +e
sh "$lease" bogus >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ]; assert 'unknown subcommand -> exit 2' $?
set +e
sh "$lease" claim >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -ne 0 ]; assert 'claim with no project-id -> nonzero exit' $?

if [ "$failures" -eq 0 ]; then
    echo ""
    echo "All decision-lease tests passed."
else
    echo ""
    echo "$failures test(s) FAILED."
    exit 1
fi
