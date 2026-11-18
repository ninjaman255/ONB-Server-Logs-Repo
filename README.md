# GitHub Folder Sync v3

Automatically copy **all files and nested directories** from the folder containing the script into a GitHub repository. **v3 adds a destination folder inside the repository**, so multiple servers can independently upload logs to their own locations.

The scripts work without specifying individual files or source folders. They perform **additive syncs** (no automatic deletion) and support **optional scheduled syncs**.

| Platform | Script | Requirements | Optional scheduler |
| --- | --- | --- | --- |
| Windows | `github-sync.bat` | Git for Windows; built-in Robocopy | Windows Task Scheduler via `schtasks` (no PowerShell) |
| Linux / macOS | `github-sync.sh` | Git, rsync, Bash | User `cron` via `crontab` |

## 1. Configure the destination

Edit these settings at the top of **either script**:

```text
REPO_URL    = Your GitHub repository URL
BRANCH      = Branch to update (typically main)
REPO_SUBDIR = Folder inside that repository
```

**Windows (`github-sync.bat`)**:

```bat
set "REPO_URL=https://github.com/USERNAME/server-logs.git"
set "BRANCH=main"
set "REPO_SUBDIR=servers/Server_A/logs"
```

**Linux/macOS (`github-sync.sh`)**:

```bash
REPO_URL="https://github.com/USERNAME/server-logs.git"
BRANCH="main"
REPO_SUBDIR="servers/Server_B/logs"
```

**Destination rules:**

- `REPO_SUBDIR` is relative to the repository root. The script creates missing folders.
- Use forward slashes (`/`) on **both** platforms. Allowed characters: letters, numbers, `_`, `-`, `.`, `/` (no spaces in destination names).
- Leave `REPO_SUBDIR` **empty** to upload to the repository root, just like v2. A value of `.` also means the root.
- Do not use leading/trailing slashes, `..`, or `.git` path segments. These are rejected.
- **Each server gets its own copy** of the script with the **same `REPO_URL` and `BRANCH`**, but a **different `REPO_SUBDIR`**. Avoid assigning the same destination to multiple servers unless you intend to combine their files.

### Example: multiple servers, one repository

Server A stores its script and logs in `/server_A/_DEBUGGING/` and sets:

```text
REPO_SUBDIR=servers/Server_A/logs
```

Server B stores its script and logs in `/server_B/_DEBUGGING/` and sets:

```text
REPO_SUBDIR=servers/Server_B/logs
```

After they run, the **same GitHub repository** contains:

```text
server-logs/
├── servers/
│   ├── Server_A/
│   │   └── logs/
│   │       ├── server.log
│   │       ├── crashes/
│   │       │   └── crash_001.log
│   │       └── github-sync.sh
│   └── Server_B/
│       └── logs/
│           ├── server.log
│           ├── archived/
│           │   └── old.log
│           └── github-sync.bat
└── README.md
```

Only the **contents** of `_DEBUGGING` are added beneath the destination folder; `_DEBUGGING` itself is not created automatically in GitHub. The scripts themselves are included because they are located in the source folder.

## 2. Run a manual sync

1. Create the GitHub repository and branch (if they do not already exist).
2. Place `github-sync.bat` or `github-sync.sh` **inside the folder you want uploaded**.
3. Edit `REPO_URL`, `BRANCH`, and optionally `REPO_SUBDIR` in that script.
4. Ensure `git` is installed and you have authenticated to GitHub, with a Git commit name and email configured.
5. Start the script:

**Windows:** Double-click `github-sync.bat`, then choose **1 — Sync now**. No PowerShell is needed.

**Linux/macOS:**

```bash
chmod +x github-sync.sh
./github-sync.sh
```

Choose **1 — Sync now**. You can run it from elsewhere, too: the source is **always the script's own directory**, not the current working directory.

Each run clones the latest branch into a temporary folder, copies the local source contents into `REPO_SUBDIR`, commits changed files, pushes to GitHub, and removes the temporary folder. If nothing changed, it makes no commit. If another server pushes at the same time, it attempts to rebase and retry the push (up to three attempts); actual file conflicts still require manual resolution.

## 3. Optional automatic sync

Scheduling is **opt-in**. Running the script normally **does not** install a task or service.

| Menu option | Action |
| --- | --- |
| 1 | Sync now, once |
| 2 | Enable/change automatic sync |
| 3 | Disable automatic sync |
| 4 | View schedule status |
| 5 | Exit |

When you choose **2**, select:

- Every **15 minutes**
- Every **30 minutes**
- **Hourly**
- **Daily at 2:00 AM**

Windows uses **Task Scheduler** and Linux/macOS uses **cron**. Both run the script on a schedule **without a constantly running terminal**. On Windows, the task may only run while the user is signed in, depending on task settings. Keep the script at its original path, keep the computer awake/running at the scheduled time, and ensure Git authentication works without interactive prompts.

**Changing `REPO_SUBDIR` later:** Update it in the script. The existing scheduled task will use the new destination on its next run; you do not need to re-register it. Existing files in the old destination are **not deleted**.

Scheduled logs are stored in `%LOCALAPPDATA%\GitHubSync\` on Windows and `~/.local/state/github-sync/` by default on Linux/macOS. The **View schedule status** option prints the log location.

## Command-line options

Use `--sync` to perform a one-time unattended run. The scheduler also uses this option.

```bat
REM Windows
call github-sync.bat --sync
call github-sync.bat --status
call github-sync.bat --remove-schedule
```

```bash
# Linux/macOS
./github-sync.sh --sync
./github-sync.sh --status
./github-sync.sh --remove-schedule
./github-sync.sh --install-schedule
```

## Safety and limitations

- The sync is **additive**: files deleted locally are **not** removed from GitHub, and files outside the chosen destination remain untouched.
- `.git` directories and files named `.env` are excluded. **Other sensitive files and log data are not automatically filtered**. Review before uploading, especially to public repositories.
- Source files in subdirectories are included recursively; empty directories are not tracked by Git.
- Git `.gitignore` rules can prevent some copied files from being committed.
- Large or continually growing log files can make Git repositories slow or exceed hosting limits. Consider log rotation and exclude credentials, access tokens, or personal data.
- A scheduled upload requires network access, Git authentication, and a computer that is powered on. If a concurrent push results in a conflict, the run fails safely rather than force-pushing.
- Tested locally for Bash recursive sync, two-server destinations, path validation, and additive behavior. Windows batch code requires validation on a Windows machine.
