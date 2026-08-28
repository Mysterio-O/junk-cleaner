# File Cleaner CLI

A minimal Git Bash CLI that finds files or directories (by exact name) inside
a nested folder tree, deletes them with your confirmation, and can optionally
save the search as a recurring cleanup job using Windows Task Scheduler.

Good for things like clearing out `node_modules` / `.next` folders across
multiple project folders.

## Requirements

- Windows with **Git Bash** (or any bash that has access to Windows'
  `schtasks` command).
- No extra dependencies — just standard `find`, `rm`, `schtasks`.

## Setup

1. Put the whole `file-cleaner` folder somewhere permanent (e.g.
   `C:\Work\file-cleaner`). It needs to stay in place — scheduled jobs call
   back into `run-job.sh` inside this folder.
2. In Git Bash:
   ```bash
   cd /c/Work/file-cleaner
   chmod +x filecleaner.sh run-job.sh
   ./filecleaner.sh
   ```

## Using it

### 1) Search & delete

- Choose whether you're looking for **files** or **directories**.
  - Directories are matched by exact folder name (e.g. `node_modules`, `.next`).
  - Files are matched by exact file name (e.g. `package.json`).
  - You can enter more than one name, comma-separated: `node_modules,.next`
- Enter the parent directory to search under — it's searched recursively,
  no matter how deeply nested things are.
- All matches are listed, and nothing is deleted until you confirm with `y`.
- For directories, once a match is found it isn't searched inside further
  (e.g. it won't look for more matches inside an already-matched
  `node_modules`).

### 2) Save it as a scheduled workflow (optional)

After a successful delete, you'll be asked if you want to save this exact
search as a recurring job:

- **How often?** — enter a number of days (e.g. `3`, `7`). This becomes a
  Windows Scheduled Task that reruns the same search-and-delete
  automatically, with no prompts.
- **Delete recently worked-on items too?**
  - **Yes** → every future run deletes all matches unconditionally.
  - **No** → you'll also be asked how many days count as "recent". On each
    future run, a match is **skipped** if its *containing folder* was
    modified within that many days — otherwise it's deleted.

Each saved job gets its own `jobs/<job_id>.conf` file and its own Windows
Scheduled Task (named `FileCleaner_<job_id>`, runs daily at 9:00 AM, set to
repeat every N days). Every scheduled run appends to `logs/<job_id>.log`
so you can check what happened without babysitting it.

### 3) Manage scheduled jobs

From the main menu, option 2 lists every saved job (what it searches for,
where, and how often) and lets you delete a single job by number or wipe
all of them. Deleting a job also removes its Windows Scheduled Task.

## Notes / limitations

- This is intentionally minimal: exact-name matching only (no wildcards
  yet), one folder tree and one name-set per job.
- `schtasks` sometimes needs elevated permissions depending on your Windows
  policy. If task creation fails, the job config is still saved — you can
  create the task manually:
  ```
  schtasks /create /tn "FileCleaner_<job_id>" /tr "\"C:\Program Files\Git\bin\bash.exe\" \"C:\Work\file-cleaner\run-job.sh\" <job_id>" /sc DAILY /mo <N> /st 09:00 /f
  ```
- Deleted items are removed permanently (`rm -rf` / `rm -f`) — there's no
  recycle bin step, so double-check the match list before confirming.
