
#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# CONFIGURATION
# ==========================================

REPO_URL="https://github.com/ninjaman255/ONB-Server-Logs-Repo"
BRANCH="main"

COMMIT_MESSAGE="Automatic sync $(date '+%Y-%m-%d %H:%M:%S')"

# ==========================================
# AUTO-DETECT ROOT DIRECTORY
# ==========================================

# Always use the directory containing this script,
# regardless of where the script is executed from.
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

echo "Source directory: $SOURCE_DIR"

# Temporary workspace OUTSIDE the source directory
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT

REPO_DIR="$WORK_DIR/repo"

# ==========================================
# CLONE GITHUB REPOSITORY
# ==========================================

echo "Cloning GitHub repository..."
git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"

# ==========================================
# RECURSIVELY COLLECT EVERYTHING
# ==========================================

echo "Collecting all files and directories..."

rsync -a \
    --exclude='.git/' \
    --exclude='.env' \
    "$SOURCE_DIR/" "$REPO_DIR/"

# ==========================================
# COMMIT AND PUSH
# ==========================================

cd "$REPO_DIR"

git add -A

if git diff --cached --quiet; then
    echo "No changes detected."
else
    git commit -m "$COMMIT_MESSAGE"
    git push origin "$BRANCH"
    echo "Changes pushed successfully!"
fi

echo "Synchronization complete!"
