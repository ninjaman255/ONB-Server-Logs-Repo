#!/usr/bin/env bash
# Sync the directory containing this script to a GitHub repository.
# Optional recurring syncs are managed by your user's cron scheduler.
set -euo pipefail

# ===== EDIT THESE TWO SETTINGS =====
REPO_URL="https://github.com/ninjaman255/ONB-Server-Logs-Repo"
BRANCH="main"
# ===================================

SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
SOURCE_DIR="$(dirname -- "$SCRIPT_PATH")"
SYNC_ID="$(printf '%s' "$SCRIPT_PATH" | cksum | awk '{print $1}')"
CRON_TAG="github-sync:${SYNC_ID}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/github-sync"
LOG_FILE="$LOG_DIR/${SYNC_ID}.log"

quote_for_shell() {
    local value=${1//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

sync_now() (
    set -e

    if [[ "$REPO_URL" == *"USERNAME/REPOSITORY.git" ]]; then
        echo "ERROR: Edit REPO_URL at the top of $SCRIPT_PATH first."
        exit 1
    fi
    for program in git rsync; do
        if ! command -v "$program" >/dev/null 2>&1; then
            echo "ERROR: $program is required."
            exit 1
        fi
    done

    local work_dir repo_dir
    work_dir="$(mktemp -d)" || exit 1
    trap 'rm -rf -- "$work_dir"' EXIT
    repo_dir="$work_dir/repo"

    echo "Source: $SOURCE_DIR"
    echo "Cloning $REPO_URL ($BRANCH)..."
    git clone --quiet --single-branch --branch "$BRANCH" "$REPO_URL" "$repo_dir" || exit 1

    echo "Recursively copying files..."
    rsync -a --exclude='.git/' --exclude='.env' \
        "$SOURCE_DIR/" "$repo_dir/" || exit 1

    git -C "$repo_dir" add -A || exit 1
    if git -C "$repo_dir" diff --cached --quiet; then
        echo "No changes to upload."
        exit 0
    else
        local diff_exit=$?
        if (( diff_exit != 1 )); then
            echo "ERROR: Could not check Git changes."
            exit "$diff_exit"
        fi
    fi

    git -C "$repo_dir" commit -m "Automatic sync $(date '+%Y-%m-%d %H:%M:%S')" || exit 1
    git -C "$repo_dir" push origin "$BRANCH" || exit 1
    echo "SUCCESS: Changes pushed to GitHub."
)

require_cron() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "ERROR: crontab is unavailable. Install/enable cron to use scheduling."
        return 1
    fi
}

# Replace only this script's cron entry; leave all other jobs untouched.
change_schedule() {
    local new_expression="${1:-}" temp_file
    require_cron || return 1
    temp_file="$(mktemp)" || return 1

    (crontab -l 2>/dev/null || true) | grep -Fv " # $CRON_TAG" > "$temp_file" || true
    if [[ -n "$new_expression" ]]; then
        mkdir -p "$LOG_DIR" || { rm -f -- "$temp_file"; return 1; }
        local cmd
        cmd="/usr/bin/env bash $(quote_for_shell "$SCRIPT_PATH") --sync >> $(quote_for_shell "$LOG_FILE") 2>&1"
        # Percent signs have special meaning inside crontab command fields.
        cmd="${cmd//%/\\%}"
        printf '%s %s # %s\n' "$new_expression" "$cmd" "$CRON_TAG" >> "$temp_file"
    fi

    if crontab "$temp_file"; then
        rm -f -- "$temp_file"
        if [[ -n "$new_expression" ]]; then
            echo "Automatic sync enabled: $new_expression"
            echo "Log: $LOG_FILE"
        else
            echo "Automatic sync disabled for this script."
        fi
    else
        rm -f -- "$temp_file"
        echo "ERROR: Failed to update crontab."
        return 1
    fi
}

install_schedule() {
    echo
    echo "Choose how often to sync:"
    echo "  1) Every 15 minutes"
    echo "  2) Every 30 minutes"
    echo "  3) Every hour"
    echo "  4) Daily at 2:00 AM"
    echo "  5) Cancel"
    local selection expression
    read -r -p "Choice [1-5]: " selection || return 0
    case "$selection" in
        1) expression='*/15 * * * *' ;;
        2) expression='*/30 * * * *' ;;
        3) expression='0 * * * *' ;;
        4) expression='0 2 * * *' ;;
        5) return 0 ;;
        *) echo "Invalid choice."; return 1 ;;
    esac
    change_schedule "$expression"
}

show_status() {
    require_cron || return 1
    local entry
    entry="$(crontab -l 2>/dev/null | grep -F " # $CRON_TAG" || true)"
    if [[ -n "$entry" ]]; then
        echo "Scheduled job: $entry"
        echo "Log: $LOG_FILE"
    else
        echo "No automatic sync is configured for this script."
    fi
}

case "${1:-}" in
    --sync) sync_now; exit $? ;;
    --install-schedule) install_schedule; exit $? ;;
    --remove-schedule) change_schedule ""; exit $? ;;
    --status) show_status; exit $? ;;
    "") ;;
    *) echo "Usage: $0 [--sync|--install-schedule|--remove-schedule|--status]"; exit 2 ;;
esac

while true; do
    echo
    echo "===== GitHub Sync (Linux/macOS) ====="
    echo "Source: $SOURCE_DIR"
    echo "1) Sync now"
    echo "2) Enable/change automatic sync"
    echo "3) Disable automatic sync"
    echo "4) View schedule status"
    echo "5) Exit"
    read -r -p "Choice [1-5]: " choice || exit 0
    case "$choice" in
        1) sync_now || echo "Sync failed; see the error above." ;;
        2) install_schedule || true ;;
        3) change_schedule "" || true ;;
        4) show_status || true ;;
        5) exit 0 ;;
        *) echo "Invalid choice." ;;
    esac
done
