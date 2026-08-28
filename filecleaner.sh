#!/bin/bash
# File Cleaner CLI
# Interactively finds files/directories in a nested folder tree, deletes them
# with confirmation, and optionally saves the search as a recurring
# scheduled workflow (Windows Task Scheduler).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

main_menu() {
    while true; do
        echo ""
        echo "===== File Cleaner ====="
        echo "1) Search & delete files/directories"
        echo "2) Manage scheduled jobs"
        echo "3) Exit"
        read -rp "Choose an option [1-3]: " choice
        case "$choice" in
            1) run_search_flow ;;
            2) manage_jobs_menu ;;
            3) echo "Bye."; exit 0 ;;
            *) echo "Invalid option." ;;
        esac
    done
}

run_search_flow() {
    echo ""
    read -rp "Search for (f)iles or (d)irectories? [f/d]: " kind
    local type
    case "$kind" in
        f|F) type="file" ;;
        d|D) type="dir" ;;
        *) echo "Invalid choice."; return ;;
    esac

    local prompt_label
    if [ "$type" = "dir" ]; then
        prompt_label="exact directory name(s), e.g. node_modules,.next"
    else
        prompt_label="exact file name(s), e.g. package.json,.env"
    fi
    read -rp "Enter $prompt_label: " names_csv
    names_csv="$(echo "$names_csv" | tr -d ' ')"
    if [ -z "$names_csv" ]; then
        echo "No names provided."
        return
    fi

    read -rp "Enter the parent directory to search in: " parent_dir
    parent_dir="${parent_dir/#\~/$HOME}"
    if [ ! -d "$parent_dir" ]; then
        echo "Directory not found: $parent_dir"
        return
    fi

    echo "Searching..."
    local -a results=()
    while IFS= read -r line; do
        [ -n "$line" ] && results+=("$line")
    done < <(search_targets "$parent_dir" "$type" "$names_csv")

    if [ "${#results[@]}" -eq 0 ]; then
        echo "No matches found."
        return
    fi

    echo ""
    echo "Found ${#results[@]} match(es):"
    local p
    for p in "${results[@]}"; do
        echo "  - $p"
    done

    echo ""
    read -rp "Delete all of the above? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted. Nothing was deleted."
        return
    fi

    local deleted=0
    for p in "${results[@]}"; do
        delete_target "$p" "$type" && deleted=$((deleted+1))
    done
    echo "Deleted $deleted item(s)."

    offer_save_as_job "$parent_dir" "$type" "$names_csv"
}

offer_save_as_job() {
    local parent_dir="$1" type="$2" names_csv="$3"
    echo ""
    read -rp "Save this as a recurring scheduled workflow? [y/N]: " save_choice
    if [[ ! "$save_choice" =~ ^[Yy]$ ]]; then
        echo "Not saved. Done."
        return
    fi

    local interval_days
    read -rp "How often should this run, in days? (e.g. 3, 7): " interval_days
    if ! [[ "$interval_days" =~ ^[0-9]+$ ]] || [ "$interval_days" -lt 1 ]; then
        echo "Invalid number of days. Cancelling save."
        return
    fi

    local del_recent_choice del_recent recent_days
    read -rp "Should recently worked-on items also be deleted? [y/N]: " del_recent_choice
    if [[ "$del_recent_choice" =~ ^[Yy]$ ]]; then
        del_recent="yes"
        recent_days=0
    else
        del_recent="no"
        read -rp "Skip items whose containing folder changed within how many days?: " recent_days
        if ! [[ "$recent_days" =~ ^[0-9]+$ ]]; then
            echo "Invalid number, defaulting to 7 days."
            recent_days=7
        fi
    fi

    local job_id task_name
    job_id="$(new_job_id)"
    task_name="FileCleaner_${job_id}"

    save_job "$job_id" "$parent_dir" "$type" "$names_csv" "$del_recent" "$recent_days" "$interval_days" "$task_name"

    if create_scheduled_task "$job_id" "$interval_days" "$task_name"; then
        echo "Scheduled! This will run automatically every $interval_days day(s)."
        echo "Job ID: $job_id"
    else
        echo "Job saved, but the Windows scheduled task could not be created automatically."
        echo "You may need to run this from a terminal with permission to use schtasks,"
        echo "or create the task manually (see README.md)."
    fi
}

manage_jobs_menu() {
    while true; do
        echo ""
        shopt -s nullglob
        local files=("$JOBS_DIR"/*.conf)
        shopt -u nullglob

        local -a job_files=()
        if [ "${#files[@]}" -eq 0 ]; then
            echo "No scheduled jobs found."
        else
            echo "===== Scheduled Jobs (${#files[@]}) ====="
            local i=1
            local f
            for f in "${files[@]}"; do
                load_job "$f"
                echo "$i) [$JOB_ID] $TARGET_TYPE: $TARGET_NAMES  |  in: $PARENT_DIR  |  every $INTERVAL_DAYS day(s)  |  delete-recent: $DELETE_RECENT"
                job_files+=("$f")
                i=$((i+1))
            done
        fi

        echo ""
        echo "n) Create a new scheduled job"
        if [ "${#job_files[@]}" -gt 0 ]; then
            echo "a) Delete a single job"
            echo "b) Delete ALL jobs"
        fi
        echo "c) Back to main menu"
        read -rp "Choose an option: " opt
        case "$opt" in
            n) create_job_flow ;;
            a)
                if [ "${#job_files[@]}" -eq 0 ]; then
                    echo "Invalid option."
                    continue
                fi
                local num
                read -rp "Enter the job number to delete: " num
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#job_files[@]}" ]; then
                    local target_file="${job_files[$((num-1))]}"
                    load_job "$target_file"
                    delete_scheduled_task "$TASK_NAME"
                    rm -f -- "$target_file"
                    echo "Job $JOB_ID deleted."
                else
                    echo "Invalid job number."
                fi
                ;;
            b)
                if [ "${#job_files[@]}" -eq 0 ]; then
                    echo "Invalid option."
                    continue
                fi
                local confirm_all
                read -rp "Delete ALL ${#job_files[@]} job(s)? [y/N]: " confirm_all
                if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                    for f in "${job_files[@]}"; do
                        load_job "$f"
                        delete_scheduled_task "$TASK_NAME"
                        rm -f -- "$f"
                    done
                    echo "All jobs deleted."
                fi
                ;;
            c) return ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# Create a scheduled job directly, without running an interactive delete first.
# Shows a preview of current matches (informational only — nothing is deleted now).
create_job_flow() {
    echo ""
    read -rp "Search for (f)iles or (d)irectories? [f/d]: " kind
    local type
    case "$kind" in
        f|F) type="file" ;;
        d|D) type="dir" ;;
        *) echo "Invalid choice."; return ;;
    esac

    local prompt_label
    if [ "$type" = "dir" ]; then
        prompt_label="exact directory name(s), e.g. node_modules,.next"
    else
        prompt_label="exact file name(s), e.g. package.json,.env"
    fi
    local names_csv
    read -rp "Enter $prompt_label: " names_csv
    names_csv="$(echo "$names_csv" | tr -d ' ')"
    if [ -z "$names_csv" ]; then
        echo "No names provided."
        return
    fi

    local parent_dir
    read -rp "Enter the parent directory this job should search: " parent_dir
    parent_dir="${parent_dir/#\~/$HOME}"
    if [ ! -d "$parent_dir" ]; then
        echo "Directory not found: $parent_dir"
        return
    fi

    echo "Previewing current matches (nothing will be deleted now)..."
    local -a results=()
    while IFS= read -r line; do
        [ -n "$line" ] && results+=("$line")
    done < <(search_targets "$parent_dir" "$type" "$names_csv")
    echo "Currently ${#results[@]} match(es) exist under that path."

    local interval_days
    read -rp "How often should this run, in days? (e.g. 3, 7): " interval_days
    if ! [[ "$interval_days" =~ ^[0-9]+$ ]] || [ "$interval_days" -lt 1 ]; then
        echo "Invalid number of days. Cancelling."
        return
    fi

    local del_recent_choice del_recent recent_days
    read -rp "Should recently worked-on items also be deleted? [y/N]: " del_recent_choice
    if [[ "$del_recent_choice" =~ ^[Yy]$ ]]; then
        del_recent="yes"
        recent_days=0
    else
        del_recent="no"
        read -rp "Skip items whose containing folder changed within how many days?: " recent_days
        if ! [[ "$recent_days" =~ ^[0-9]+$ ]]; then
            echo "Invalid number, defaulting to 7 days."
            recent_days=7
        fi
    fi

    local job_id task_name
    job_id="$(new_job_id)"
    task_name="FileCleaner_${job_id}"

    save_job "$job_id" "$parent_dir" "$type" "$names_csv" "$del_recent" "$recent_days" "$interval_days" "$task_name"

    if create_scheduled_task "$job_id" "$interval_days" "$task_name"; then
        echo "Scheduled! This will run automatically every $interval_days day(s)."
        echo "Job ID: $job_id"
    else
        echo "Job saved, but the Windows scheduled task could not be created automatically."
        echo "You may need to run this from a terminal with permission to use schtasks,"
        echo "or create the task manually (see README.md)."
    fi
}

main_menu
