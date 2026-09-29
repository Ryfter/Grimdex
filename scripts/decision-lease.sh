#!/bin/sh
# Grimdex concurrent-write guard (grimdex-d042): atomically claim the next decision
# number for a project tier so two sessions sharing this repo can't both grab the
# same dNNN. POSIX sh on purpose (grimdex-d043: pwsh is not the fragile-mechanical-
# checks language of choice) -- no deps beyond coreutils + find.
#
# Usage:
#   decision-lease.sh claim   <project-id> [--ttl-hours N] [--tag TEXT]
#   decision-lease.sh release <project-id> <NNN>
#   decision-lease.sh reap    <project-id> [--ttl-hours N]
#   decision-lease.sh reap-all           [--ttl-hours N]
#   decision-lease.sh list    <project-id>
#
# claim   -> prints the claimed number as "dNNN" on stdout, creates the lease file.
# release -> removes the lease file if present (no-op, exit 0, if already gone).
# reap    -> removes .lease files older than --ttl-hours (default 2); on stdout,
#            one line per lease removed ("reaped: dNNN (age Xh)") and one line per
#            still-live lease older than 30min ("stale-warning: dNNN (age Xh)").
# reap-all -> reap across every projects/*/decisions/.leases/ dir.
# list    -> show active leases for a project, one per line.
#
# The number claimed = max(existing dNNN-*.md on disk, existing *.lease files) + 1,
# retried on collision. Leases live in a git-ignored .leases/ subdir and are never
# committed. Release your lease once the real dNNN-*.md is committed (the number is
# then claimed in git and the lease is redundant) -- the TTL + reap is the safety net
# for a lease left behind by a crashed or abandoned session.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root="${GRIMDEX_ROOT:-$(CDPATH= cd -- "$script_dir/.." && pwd)}"

usage() {
    echo "usage: $0 {claim|release|reap|reap-all|list} ..." >&2
    exit 2
}

decisions_dir() {
    printf '%s/projects/%s/decisions' "$root" "$1"
}

leases_dir() {
    printf '%s/.leases' "$(decisions_dir "$1")"
}

# Highest dNNN found among a project's committed decision files.
max_committed() {
    d=$(decisions_dir "$1")
    [ -d "$d" ] || { echo 0; return; }
    ls "$d" 2>/dev/null | sed -n 's/^d\([0-9][0-9]*\)-.*\.md$/\1/p' |
        sed 's/^0*//' | sort -n | tail -1 | sed 's/^$/0/'
}

# Highest dNNN currently leased (live or not -- reap first if you want only live ones).
max_leased() {
    l=$(leases_dir "$1")
    [ -d "$l" ] || { echo 0; return; }
    ls "$l" 2>/dev/null | sed -n 's/^d\([0-9][0-9]*\)\.lease$/\1/p' |
        sed 's/^0*//' | sort -n | tail -1 | sed 's/^$/0/'
}

cmd_claim() {
    project="${1:?claim needs a project-id}"; shift
    tag=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --tag) tag="${2:-}"; shift 2 ;;
            --ttl-hours) shift 2 ;;  # accepted, unused at claim time
            *) usage ;;
        esac
    done
    l=$(leases_dir "$project")
    mkdir -p "$l"
    a=$(max_committed "$project"); b=$(max_leased "$project")
    i=$(( (a > b ? a : b) + 1 ))
    while :; do
        numstr=$(printf '%03d' "$i")
        lease="$l/d${numstr}.lease"
        # `set -C` (noclobber): the shell's `>` redirect opens with O_EXCL under the
        # hood, so this create is atomic even against another process racing here.
        if (set -C; printf 'pid=%s\nhost=%s\nts=%s\ntag=%s\n' \
                "$$" "$(hostname -s 2>/dev/null || hostname)" \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tag" > "$lease") 2>/dev/null; then
            echo "d${numstr}"
            return 0
        fi
        i=$((i + 1))
    done
}

cmd_release() {
    project="${1:?release needs a project-id}"
    num="${2:?release needs a decision number, e.g. 042 or d042}"
    num=$(echo "$num" | sed 's/^d//')
    numstr=$(printf '%03d' "$num")
    rm -f "$(leases_dir "$project")/d${numstr}.lease"
}

# Reap one project's lease dir. $1=project, $2=ttl-hours.
reap_one() {
    project="$1"; ttl_hours="$2"
    l=$(leases_dir "$project")
    [ -d "$l" ] || return 0
    now=$(date -u +%s)
    for f in "$l"/d*.lease; do
        [ -e "$f" ] || continue
        mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "$now")
        age_h=$(( (now - mtime) / 3600 ))
        base=$(basename "$f" .lease)
        if [ "$age_h" -ge "$ttl_hours" ]; then
            rm -f "$f"
            echo "reaped: ${base} (age ${age_h}h, project ${project})"
        elif [ "$age_h" -ge 1 ] || [ $(( (now - mtime) / 60 )) -ge 30 ]; then
            age_m=$(( (now - mtime) / 60 ))
            echo "stale-warning: ${base} (age ${age_m}m, project ${project}) -- still live, may indicate a dead session"
        fi
    done
}

cmd_reap() {
    project="${1:?reap needs a project-id}"; shift || true
    ttl_hours=2
    while [ $# -gt 0 ]; do
        case "$1" in --ttl-hours) ttl_hours="$2"; shift 2 ;; *) usage ;; esac
    done
    reap_one "$project" "$ttl_hours"
}

cmd_reap_all() {
    ttl_hours=2
    while [ $# -gt 0 ]; do
        case "$1" in --ttl-hours) ttl_hours="$2"; shift 2 ;; *) usage ;; esac
    done
    [ -d "$root/projects" ] || return 0
    for pd in "$root"/projects/*/; do
        [ -d "${pd}decisions/.leases" ] || continue
        project=$(basename "$pd")
        reap_one "$project" "$ttl_hours"
    done
}

cmd_list() {
    project="${1:?list needs a project-id}"
    l=$(leases_dir "$project")
    [ -d "$l" ] || return 0
    for f in "$l"/d*.lease; do
        [ -e "$f" ] || continue
        echo "$(basename "$f" .lease): $(tr '\n' ' ' < "$f")"
    done
}

[ $# -ge 1 ] || usage
sub="$1"; shift
case "$sub" in
    claim)    cmd_claim "$@" ;;
    release)  cmd_release "$@" ;;
    reap)     cmd_reap "$@" ;;
    reap-all) cmd_reap_all "$@" ;;
    list)     cmd_list "$@" ;;
    *) usage ;;
esac
