# Workroot + Repo Python Setup (Clean Outputs, Clean Commits)

## Goal

This setup gives you a **clean separation** between:

- **workroot** → where you *run* commands and where outputs land  
- **repo** → where your *git-tracked pipeline code* lives  

You get:

- Clean repos (no output junk, no `__pycache__`)
- Python imports that work as if the repo were installed
- Fast shell navigation + tab completion to the repo
- A single explicit bootstrap step per session (optional, but recommended)

---

## Mental Model (important)

There are **two separate systems** involved:

1. **Python import system**
   - Controlled by a `.pth` file inside the venv
   - Affects `sys.path`
   - Makes `import your_repo_module` work

2. **PowerShell environment**
   - Controlled by `$env:REPO`, `$env:PYTHONDONTWRITEBYTECODE`, etc.
   - Affects tab completion, `cd`, convenience commands
   - Does *not* affect Python imports

They are intentionally independent.

---

## Quickstart (5 lines)

From PowerShell:

```powershell
cd "C:\Path\To\Workroot"
.\.venv\Scripts\Activate.ps1
$env:REPO="C:\Path\To\Your\Repo"
$env:PYTHONDONTWRITEBYTECODE="1"   # optional
python -c "import repo_marker; print(repo_marker.__file__)"
```

If that prints a path inside your repo, you’re done.

---

## Definitions

- **workroot**  
  The directory you *run from*.  
  Contains:
  - `.venv/`
  - outputs (JSONL, manifests, logs, etc.)

- **repo**  
  The git repository containing pipeline scripts and modules.

- **bytecode**  
  `.pyc` files written to `__pycache__` directories.

Example paths:

```
workroot: C:\path\to\workroot
repo:     C:\path\to\Git_repo
```

---

## Step 0: Create and activate the venv (in the workroot)

From the **workroot**:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python --version
```

Install requirements after this if needed.

---

## Step 1: Make the venv import modules from the repo (.pth trick)

This is the *only* persistent wiring step.

### 1.1 Find the venv’s site-packages directory

With the venv activated:

```powershell
$site = python -c "import site; print(site.getsitepackages()[0])"
$site
```

### 1.2 Write a `.pth` file pointing at your repo

Replace with your real repo path:

```powershell
$REPO = "C:\Path\To\Your\Repo"
Set-Content -Path (Join-Path $site "repo.pth") -Value $REPO
```

What this does:
- Python reads `.pth` files on startup
- Each line is added to `sys.path`
- Your repo becomes importable without installs or symlinks

### 1.3 Verify imports work

Use a **unique module name** inside the repo:

```powershell
python -c "import repo_marker; print(repo_marker.__file__)"
```

You should see a path inside the repo. ✅

**Tip:** Don’t name the file `test.py` — it collides with Python’s built-in `test` package.

---

## Step 2: (Optional) Set `$env:REPO` for navigation + tab completion

This is **shell-only convenience**.

```powershell
$env:REPO = "C:\Path\To\Your\Repo"
```

What this enables:

```powershell
cd $env:REPO
Get-ChildItem $env:REPO
"$env:REPO\src\"   # tab-completes paths
```

Important:
- `$env:REPO` does **not** affect Python imports
- It exists purely for navigation, scripting, and readability

---

## Step 3: (Optional) Prevent `__pycache__` creation

Disable bytecode generation for the session:

```powershell
$env:PYTHONDONTWRITEBYTECODE = "1"
python -c "import sys; print(sys.dont_write_bytecode)"
```

Notes:
- This is session-scoped unless made persistent
- Useful when the repo must stay clean for commits

---

## Step 4: Run repo scripts from the workroot

Because you are *standing in the workroot*:

- Outputs land in the workroot
- Imports resolve from the repo via `.pth`
- The repo stays clean

This is the entire point of the setup.

---

## What you do each time you open a new terminal

Minimal version:

1. `cd` to workroot
2. Activate venv

Optional extras:

3. Set `PYTHONDONTWRITEBYTECODE`
4. Set `$env:REPO`

Example:

```powershell
cd "C:\Path\To\Workroot"
.\.venv\Scripts\Activate.ps1
$env:PYTHONDONTWRITEBYTECODE="1"   # optional
$env:REPO="C:\Path\To\Your\Repo"   # optional
```

You **do not** redo the `.pth` file each session.

---

## Bootstrap script (recommended)

Instead of typing env vars manually, create a **single explicit entrypoint**.

### `bootstrap.ps1` (lives in the workroot)

```powershell
.\.venv\Scripts\Activate.ps1

# Keep repo clean
$env:PYTHONDONTWRITEBYTECODE = "1"

# Convenience only (navigation + tab completion)
$env:REPO = "C:\Path\To\Your\Repo"
```

Then each session:

```powershell
.\bootstrap.ps1
```

### Why this also “handles tab completion”

- PowerShell expands environment variables *before* path completion
- Once `$env:REPO` is set:
  - `$env:REPO\` participates in tab completion
  - `cd $env:REPO` works immediately
- No extra configuration is required

The bootstrap doesn’t modify completion behavior — it simply ensures the
variable exists early in the session so completion can use it.

This is preferred over `$PROFILE` because:
- It’s explicit
- It’s project-scoped
- It doesn’t affect unrelated shells

---

## When the repo changes (git pull, edits)

Nothing special required.

Because the `.pth` points to the repo directory:
- Changes are picked up immediately
- No reinstalls
- No cache invalidation

Redo the `.pth` only if:
- The repo moves to a new path
- The venv is deleted/recreated

---

## Troubleshooting

### ImportError: No module named X

- `.pth` file missing or wrong
- Re-check:

```powershell
$site = python -c "import site; print(site.getsitepackages()[0])"
Get-Content (Join-Path $site "repo.pth")
```

### Outputs landing in the repo

You ran the command *from the repo*.

Check:

```powershell
(Get-Location).Path
```

Fix:
```powershell
cd C:\Path\To\Workroot
```

### Tab completion jumps to `C:\`

`$env:REPO` is unset or invalid.

```powershell
$env:REPO
Test-Path $env:REPO
```

### `__pycache__` keeps appearing

You forgot to set `PYTHONDONTWRITEBYTECODE` in this session.

Use `bootstrap.ps1` if you want it every time.

---

## Quick health check (copy/paste)

```powershell
@'
import sys, site
print("exe:", sys.executable)
print("site-packages:", site.getsitepackages()[0])
print("repo in sys.path:", r"C:\Path\To\Your\Repo" in sys.path)
try:
    import repo_marker
    print("repo_marker:", repo_marker.__file__)
except Exception as e:
    print("import failed:", type(e).__name__, e)
'@ | .\.venv\Scripts\python -
```

Replace `C:\Path\To\Your\Repo` with your actual path.
