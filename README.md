# Project Template: Repo + Workroot (PowerShell / Python)

This setup gives you a **repeatable, copy‑pasteable project template** with a clean separation between:

- **Repo** → git‑tracked source code only  
- **Workroot** → virtual environment + outputs + session wiring  

It is designed so you can:

- Duplicate two folders (`template-repo` + `template-repo-workroot`)
- Rename them
- Run **one command** to initialize
- Run **one command per session** to work
- Delete and recreate workroots freely without touching the repo

No global PowerShell policy changes. No fragile assumptions.

---

## Folder Layout (Template)

Starting point:

```
Projects/
  template-repo/
    repo_marker.py
    (your pipeline code here)
  
  template-repo-workroot/
    boot.cmd
    bootstrap.ps1
    init.ps1
    README.md   <-- this file (optional location)
```

After copying and renaming:

```
Projects/
  Project-A/
    repo_marker.py
    ...
  
  Project-A-workroot/
    boot.cmd
    bootstrap.ps1
    init.ps1
```

The only thing you must change before initialization is:

> **Rename both folders so they share the same base name**, with `-workroot` appended to the workroot.

Example:
- `Project-A`
- `Project-A-workroot`

This naming convention is how the scripts auto‑discover the repo path.

---

## Core Idea (Mental Model)

There are **three distinct layers**, each handled explicitly:

1. **Repo**
   - Pure source code
   - Safe to commit
   - Never polluted by outputs or `__pycache__`

2. **Workroot**
   - Where you run commands
   - Where outputs land
   - Where the venv lives

3. **Bootstrap / Init scripts**
   - Wire Python + PowerShell together
   - Never committed to global state
   - Fully project‑scoped

---

## What Each File Does

### `boot.cmd`
- Entry point that *always works*
- Launches PowerShell with `ExecutionPolicy Bypass`
- Prevents execution‑policy friction
- Does **not** modify system or user policy

You never run `.ps1` files directly — you always go through `boot.cmd`.

---

### `init.ps1` (one‑time per workroot)

Run this **once** after copying/renaming folders.

Note: `boot.cmd init.ps1` opens a new PowerShell session, runs init, then drops you into the bootstrap session. Do your work in that session; type `exit` to return.

It will:

- Create `.venv` **if missing**
- Activate the venv
- Derive the repo path from the `*-workroot` name
- Write a `.pth` file so Python can import repo modules
- Verify imports using `repo_marker.py`

Think of this as:

> “Bring this workroot online.”

---

### `bootstrap.ps1` (every session)

Run this **every time you open a new terminal**.

It will:

- Activate the existing venv
- Set `$env:REPO` (for navigation + tab completion)
- Disable Python bytecode (`__pycache__`) for a clean repo

Think of this as:

> “Prepare this shell to work.”

---

## Required Marker File (Repo)

Your repo **must** contain a uniquely named module for verification.

Example (already in `template-repo`):

```python
# repo_marker.py
```

It can be empty — it only exists so imports can be tested reliably.

Do **not** name this file `test.py` (that collides with Python internals).

---

## First‑Time Setup (True Init)

### 1) Rename folders

Rename both template folders:

```
template-repo           → Project-A
template-repo-workroot  → Project-A-workroot
```

### 2) Initialize the workroot

From PowerShell:

```powershell
cd C:\Path\To\Projects\Project-A-workroot
.\boot.cmd init.ps1
```

What happens:
- `.venv` is created if missing
- Repo path is auto‑derived
- `.pth` file is written
- Import is verified

If this completes without errors, the environment is wired correctly.

---

## Daily Usage (Every Session)

Each new terminal:

```powershell
cd C:\Path\To\Projects\Project-A-workroot
.\boot.cmd bootstrap.ps1
```

You are now in a new PowerShell session with the environment set. Stay in this session for work; use `exit` to return.

After this:

- `python` uses the venv
- Repo modules import correctly
- `$env:REPO` works for tab completion
- Outputs land in the workroot

Example:

```powershell
cd $env:REPO
Get-ChildItem
```

---

## Run manifests

Run manifests are written under `manifests\` in the workroot. This is disposable workroot state and safe to delete.

Example:

```powershell
.\boot.cmd bootstrap.ps1
wr python $env:REPO\some_script.py --arg1 x
wr -Snapshot python $env:REPO\some_script.py --arg1 x
```

Each run writes a JSON manifest: `manifests\run_<run_id>.json` in the workroot.

Snapshot diffs are off by default. Use: `wr -Snapshot <command> [args...]` to include file change lists.

## Python Version Control (Important)

### Default behavior

`init.ps1` uses:

```powershell
py -m venv .venv
```

This uses **whatever Python `py` resolves to by default**.

---

### If you need a specific Python version

First, verify available versions:

```powershell
py -0
```

Example output:

```
 -3.10
 -3.11
 -3.12
```

To force a version, edit **one line** in `init.ps1`:

```powershell
py -3.11 -m venv $venvDir
```

This pins the venv to Python 3.11.

Notes:
- The venv is tied to that Python version
- If you delete the workroot, re‑running `init.ps1` recreates it correctly
- The repo remains untouched

---

## When You Delete a Workroot

This setup assumes workroots are disposable.

Safe to delete:
- `.venv`
- outputs
- logs
- manifests

To recover:
```powershell
copy Project-A-workroot
rename
.\boot.cmd init.ps1
```

Nothing needs to be redone in the repo.

---

## Troubleshooting

### ImportError / Module not found

- Ensure `repo_marker.py` exists in the repo root
- Re‑run:

```powershell
.\boot.cmd init.ps1
```

---

### Outputs appearing in the repo

You ran the command while your shell was *in the repo*.

Check:

```powershell
(Get-Location).Path
```

Fix:

```powershell
cd C:\Path\To\Projects\Project-A-workroot
```

---

### `$env:REPO` is empty

You forgot to run `bootstrap.ps1` in this session.

```powershell
.\boot.cmd bootstrap.ps1
```

---

### Execution policy errors

You ran a `.ps1` directly.

Correct usage is always:

```powershell
.\boot.cmd bootstrap.ps1
# or
.\boot.cmd init.ps1
```

No global policy changes are required.

---

## Summary

- **Copy repo + workroot**
- **Rename both**
- **Run `init.ps1` once**
- **Run `bootstrap.ps1` every session**
- **Delete workroots freely**
- **Keep repos clean**

This pattern scales cleanly across many projects without hidden state or global side effects.














