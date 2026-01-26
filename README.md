# Project Template: Repo + Workroot (PowerShell / Python)

This template keeps your repo clean and your workroot disposable. You get:

- A repo that is safe to commit (source only)
- A workroot for venvs, outputs, logs, and session wiring
- Zero global PowerShell policy changes (boot.cmd always uses ExecutionPolicy Bypass)
- Optional run manifests and per-session transcripts for traceability

---

## Quick Start

1) Copy and rename both folders so the base name matches:

```
Projects/
  Project-A/
  Project-A-workroot/
```

2) Initialize the workroot (one time):

```powershell
cd C:\Path\To\Projects\Project-A-workroot
.oot.cmd init.ps1
```

3) Start a session (every terminal):

```powershell
.oot.cmd bootstrap.ps1
```

---

## Folder Layout (Template)

```
Projects/
  template-repo/
    repo_marker.py
    (your pipeline code here)

  template-repo-workroot/
    boot.cmd
    bootstrap.ps1
    init.ps1
    workroot_tools.ps1
    README.md   <-- this file (optional location)
```

---

## Mental Model

Three explicit layers:

1. Repo
   - Source code only
   - Safe to commit
   - Never polluted by outputs or __pycache__

2. Workroot
   - Where commands run
   - Where outputs and logs land
   - Where the venv lives

3. Boot/Init scripts
   - Wire PowerShell and Python together
   - Live with the project
   - Make sessions repeatable

---

## Scripts and Responsibilities

### boot.cmd
- Safe entry point for all sessions
- Launches PowerShell with ExecutionPolicy Bypass
- Does not modify system or user policy

Usage:

```powershell
.oot.cmd init.ps1
.oot.cmd bootstrap.ps1
```

Note: `boot.cmd init.ps1` starts a new session, runs init, then drops you into bootstrap automatically.

---

### init.ps1 (one time per workroot)

What it does:
- Creates `.venv` if missing
- Installs `requirements.txt` if present in the workroot
- Activates the venv
- Derives repo path from the `*-workroot` folder name
- Writes a `.pth` file so Python can import repo modules
- Verifies import using `repo_marker.py`

Think: "Bring this workroot online."

---

### bootstrap.ps1 (every session)

What it does:
- Activates the venv
- Sets `$env:REPO` for easy navigation and tab completion
- Sets `$env:PYTHONDONTWRITEBYTECODE=1` to avoid __pycache__ in the repo
- Starts a transcript (by default)
- Loads `workroot_tools.ps1` so `wr` is available

Think: "Prepare this shell to work."

---

## Required Marker File (Repo)

Your repo must contain a unique importable module so init can verify imports:

```python
# repo_marker.py
value = "ok"
```

Do not name this file `test.py` (it collides with Python internals).

---

## Session Transcript (Default)

A transcript is started automatically in every bootstrap session.

- Default location: `<workroot>\_workroot_transcripts\`
- File name: `session_yyyyMMdd_HHmmss_<shortid>.log`
- The path is printed once when the session starts

Disable or customize:

```powershell
.oot.cmd bootstrap.ps1 -NoTranscript
.oot.cmd bootstrap.ps1 -TranscriptDir C:\Path\To\Logs
```

Notes:
- Transcript files grow with output volume; avoid typing secrets.
- The transcript records host output (Write-Host), which is why `wr -CaptureOutput` replays captured output back to the host.

---

## Run Manifests and the `wr` Command

`wr` is an alias for `Invoke-WorkrootCommand` and is loaded by `workroot_tools.ps1`.

General usage:

```powershell
wr [flags] -- <command> [args...]
```

Flags:
- `-DryRun`            Print derived paths and manifest location, do not execute
- `-Snapshot`          Include before/after file snapshots and change lists
- `-IncludeUser`       Include the username in the manifest
- `-CaptureOutput`     Capture stdout/stderr into the manifest (opt-in)
- `-NoCapture`         Force output capture off
- `-RawNativeStderr`   Capture raw native stderr (no PowerShell wrapper). Implies -CaptureOutput
- `-MaxOutputBytes N`  Limit captured bytes per stream (default 65536)
- `-OutputEncoding X`  Decode captured output using a specific encoding

Examples:

```powershell
wr python $env:REPO\some_script.py --arg1 x
wr -Snapshot -- python $env:REPO\some_script.py --arg1 x
wr -IncludeUser -- python $env:REPO\some_script.py
wr -CaptureOutput -- python -c "print('hello')"
wr -CaptureOutput -RawNativeStderr -- python -c "import sys; print('err', file=sys.stderr)"
```

Manifest output location:
- `<workroot>\_workroot_manifestsun_<run_id>.json`

---

## Output Capture Details (Opt-In)

Output capture is OFF by default to preserve interactive behavior.

When you enable `-CaptureOutput`:
- Stdout/stderr are redirected to temp files
- Captured text is written into the manifest
- Output is replayed to the host so the transcript records it

Encoding defaults:
- Windows PowerShell (Desktop): `unicode`
- PowerShell 7+: `utf8`

If you see odd characters in captured output, override explicitly:

```powershell
wr -CaptureOutput -OutputEncoding unicode -- <command>
wr -CaptureOutput -OutputEncoding utf8 -- <command>
```

Raw native stderr:
- `-RawNativeStderr` uses `Start-Process -RedirectStandardError` to avoid PowerShell error-record wrappers
- Best for non-interactive commands
- You lose PowerShell error context, but stderr is clean

---

## Snapshot Diffs

With `-Snapshot`, manifests include file change lists:
- `new_files`
- `modified_files`
- `deleted_files`

Snapshots exclude:
- `.venv/`
- `.git/`
- `_workroot_manifests/`
- `manifests/`

---

## Python Version Control

Default behavior in `init.ps1`:

```powershell
py -m venv .venv
```

To pin a specific Python version:

```powershell
py -0
py -3.11 -m venv .venv
```

The venv is tied to that version; deleting the workroot will recreate it correctly.

---

## Deleting a Workroot (Safe)

Workroots are disposable. Safe to delete:
- `.venv/`
- `_workroot_manifests/`
- `_workroot_transcripts/`
- outputs/logs

The repo stays clean and untouched.

---

## Troubleshooting

### ImportError / module not found
- Ensure `repo_marker.py` exists in the repo root
- Re-run: `\.oot.cmd init.ps1`

### Outputs appear in the repo
You ran the command while your shell was in the repo.

```powershell
(Get-Location).Path
cd C:\Path\To\Projects\Project-A-workroot
```

### `$env:REPO` is empty
You forgot to bootstrap this session.

```powershell
.oot.cmd bootstrap.ps1
```

### Execution policy errors
Always run through `boot.cmd`:

```powershell
.oot.cmd bootstrap.ps1
.oot.cmd init.ps1
```

---

## Summary

- Copy repo + workroot
- Rename both to the same base name
- Run `init.ps1` once
- Run `bootstrap.ps1` every session
- Keep repos clean; delete workroots freely

This pattern scales cleanly across many projects without hidden state or global side effects.
