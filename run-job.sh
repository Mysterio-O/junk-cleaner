#!/bin/bash
# run-job.sh <job_id>
# Executed automatically by Windows Task Scheduler. No user interaction —
# logs everything to logs/<job_id>.log instead.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

JOB_ID_ARG="${1:-}"
if [ -z "$JOB_ID_ARG" ]; then
    echo "Usage: run-job.sh <job_id>" >&2
    exit 1
fi

JOB_FILE="$JOBS_DIR/${JOB_ID_ARG}.conf"
if [ ! -f "$JOB_FILE" ]; then
    echo "Job file not found: $JOB_FILE" >&2
    exit 1
fi

load_job "$JOB_FILE"
LOG_FILE="$LOGS_DIR/${JOB_ID}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Job started (type=$TARGET_TYPE names=$TARGET_NAMES interval=${INTERVAL_DAYS}d delete_recent=${DELETE_RECENT} recent_days=${RECENT_DAYS})"

if [ ! -d "$PARENT_DIR" ]; then
    log "Parent directory missing: $PARENT_DIR. Skipping this run."
    exit 0
fi

results=()
while IFS= read -r line; do
    [ -n "$line" ] && results+=("$line")
done < <(search_targets "$PARENT_DIR" "$TARGET_TYPE" "$TARGET_NAMES")

deleted=0
skipped=0
for p in "${results[@]}"; do
    if [ "$DELETE_RECENT" = "no" ] && should_skip_recent "$p" "$RECENT_DAYS"; then
        log "Skipped (parent folder modified within ${RECENT_DAYS}d): $p"
        skipped=$((skipped+1))
        continue
    fi
    delete_target "$p" "$TARGET_TYPE"
    log "Deleted: $p"
    deleted=$((deleted+1))
done

log "Job finished. Deleted=$deleted Skipped=$skipped Found=${#results[@]}"
