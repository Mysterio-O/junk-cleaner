#!/bin/bash
# common.sh - shared functions for File Cleaner CLI
# Sourced by filecleaner.sh and run-job.sh — do not run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS_DIR="$SCRIPT_DIR/jobs"
LOGS_DIR="$SCRIPT_DIR/logs"
mkdir -p "$JOBS_DIR" "$LOGS_DIR"

# Convert a Git Bash (POSIX-style) path to a Windows path for schtasks.
# Falls back to the original path if cygpath isn't available.
to_win_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        echo "$1"
    fi
}

# Search for matching files or directories under a parent directory.
# Args: parent_dir  type(file|dir)  comma_separated_names
# For directories, matches are pruned (we don't look inside a matched dir,
# e.g. we won't search inside node_modules once it's found).
search_targets() {
    local parent="$1"
    local type="$2"
    local names_csv="$3"
    local -a names
    IFS=',' read -ra names <<< "$names_csv"

    local -a expr=()
    local i
    for i in "${!names[@]}"; do
        if [ "$i" -gt 0 ]; then
            expr+=( -o )
        fi
        expr+=( -name "${names[$i]}" )
    done

    if [ "$type" = "dir" ]; then
        find "$parent" -type d \( "${expr[@]}" \) -prune -print 2>/dev/null
    else
        find "$parent" -type f \( "${expr[@]}" \) -print 2>/dev/null
    fi
}

# Delete a single target (file or directory).
delete_target() {
    local path="$1"
    local type="$2"
    if [ "$type" = "dir" ]; then
        rm -rf -- "$path"
    else
        rm -f -- "$path"
    fi
}

# Returns success (0) if the target's PARENT folder was modified within
# the last N days — meaning it should be SKIPPED (protected as "recent work").
should_skip_recent() {
    local target_path="$1"
    local days="$2"
    local parent_dir
    parent_dir="$(dirname -- "$target_path")"
    if find "$parent_dir" -maxdepth 0 -mtime -"$days" 2>/dev/null | grep -q .; then
        return 0
    else
        return 1
    fi
}

new_job_id() {
    echo "job_$(date +%Y%m%d%H%M%S)"
}

# Save a job's config as simple KEY=VALUE lines.
save_job() {
    local job_id="$1" parent="$2" type="$3" names="$4" del_recent="$5" recent_days="$6" interval="$7" task_name="$8"
    local file="$JOBS_DIR/${job_id}.conf"
    {
        echo "JOB_ID=$job_id"
        echo "PARENT_DIR=$parent"
        echo "TARGET_TYPE=$type"
        echo "TARGET_NAMES=$names"
        echo "DELETE_RECENT=$del_recent"
        echo "RECENT_DAYS=$recent_days"
        echo "INTERVAL_DAYS=$interval"
        echo "TASK_NAME=$task_name"
        echo "CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$file"
}

# Load a job config file into shell variables (JOB_ID, PARENT_DIR, etc).
load_job() {
    local file="$1"
    JOB_ID=""; PARENT_DIR=""; TARGET_TYPE=""; TARGET_NAMES=""; DELETE_RECENT=""
    RECENT_DAYS=""; INTERVAL_DAYS=""; TASK_NAME=""; CREATED_AT=""
    while IFS='=' read -r key value; do
        case "$key" in
            JOB_ID) JOB_ID="$value" ;;
            PARENT_DIR) PARENT_DIR="$value" ;;
            TARGET_TYPE) TARGET_TYPE="$value" ;;
            TARGET_NAMES) TARGET_NAMES="$value" ;;
            DELETE_RECENT) DELETE_RECENT="$value" ;;
            RECENT_DAYS) RECENT_DAYS="$value" ;;
            INTERVAL_DAYS) INTERVAL_DAYS="$value" ;;
            TASK_NAME) TASK_NAME="$value" ;;
            CREATED_AT) CREATED_AT="$value" ;;
        esac
    done < "$file"
}

# Register a Windows Scheduled Task that runs run-job.sh for this job every N days.
create_scheduled_task() {
    local job_id="$1" interval_days="$2" task_name="$3"
    local bash_path bash_win run_job_posix run_job_win

    bash_path="$(command -v bash)"
    if [ -z "$bash_path" ]; then
        echo "Could not locate bash executable. Please register the scheduled task manually." >&2
        return 1
    fi

    bash_win="$(to_win_path "$bash_path")"
    run_job_posix="$SCRIPT_DIR/run-job.sh"
    run_job_win="$(to_win_path "$run_job_posix")"

    schtasks /create /tn "$task_name" \
        /tr "\"$bash_win\" \"$run_job_win\" $job_id" \
        /sc DAILY /mo "$interval_days" /st 09:00 /f
}

delete_scheduled_task() {
    local task_name="$1"
    schtasks /delete /tn "$task_name" /f >/dev/null 2>&1
}
