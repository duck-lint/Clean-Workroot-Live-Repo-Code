## Goal

A clean “workroot” folder where outputs land and a separate git repo where pipeline scripts live (clean for commits). Python can import repo modules while you run from the workroot. No __pycache__ clutter in the repo.

---

## How this works:
You run commands from the workroot (so outputs land there)
A .pth file in the venv tells Python to add the repo folder to sys.path
Optionally, you disable bytecode generation to prevent __pycache__
Definitions

**workroot**: the folder you run from (contains .venv + outputs)

**repo**: the git directory containing your pipeline scripts

**bytecode**: .pyc files that show up in __pycache__


**Example paths**:
```
workroot: C:\path\to\workroot
repo: C:\path\to\Git_repo
```

### Step 0: Create / activate the venv in the workroot
From workroot:
```PowerShell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python --version
```
(Install your requirements after this as needed.)


### Step 1: Make the venv import modules from the repo (.pth trick)

#### 1.1 Get the venv site‑packages path
While the venv is activated:
```PowerShell
$site = python -c "import site; print(site.getsitepackages()[0])"
$site
```
#### 1.2 Write a .pth file pointing to your repo
Replace with your repo path:
```PowerShell
$REPO = "C:\Path\To\Your\Repo"
Set-Content -Path (Join-Path $site "repo.pth") -Value $REPO
```
#### 1.3 Verify it worked
Use a unique module name to avoid collisions:
```PowerShell
python -c "import repo_marker; print(repo_marker.__file__)"
```
You should see a path inside your repo. ✅

Tip: Don’t name your test file test.py — it collides with Python’s built‑in test package.


### Step 2: Optional: prevent __pycache__ from being created
This stops Python from writing .pyc bytecode files:
```PowerShell
$env:PYTHONDONTWRITEBYTECODE = "1"
python -c "import sys; print(sys.dont_write_bytecode)"
```
Note: this is session‑only unless you make it permanent.


### Step 3: Run repo scripts while outputs land in the workroot
Because you’re standing in the workroot, output folders land there, while imports resolve from the repo.

---

## What you do each time you open a new terminal
1. Go to the workroot
2. Activate venv
3. (Optional) set `PYTHONDONTWRITEBYTECODE`
`cd "C:\Path\To\Workroot" .\.venv\Scripts\Activate.ps1 $env:PYTHONDONTWRITEBYTECODE="1"   # optional`
You do **not** need to redo the `.pth` file each time.

---

## When you update the repo (git pull / changes)
Nothing special required.
Because the `.pth` points to the repo folder:
- edits and pulls are used immediately next run

Only redo the `.pth` if:
- you move the repo to a different folder
- you delete/recreate the venv

---

## Troubleshooting
### “ImportError: No module named common”
- The `.pth` file might be missing or points to the wrong repo path.
- Re-check:`python -c "import site; print(site.getsitepackages()[0])" Get-Content (Join-Path $site "pipeline_repo.pth")`
### Outputs are going into the repo again
- You probably ran the command while your terminal was _in the repo_.
- Check:`(Get-Location).Path`
- Fix: `cd` back to your workroot.
### `__pycache__` keeps appearing
- You forgot to set `PYTHONDONTWRITEBYTECODE` in the new session, or something else is generating bytecode.
- Use the persistent approach below if you want it always on.

---

## Make `PYTHONDONTWRITEBYTECODE` automatic (pick one)
### Option A: add it to your PowerShell profile
`notepad $PROFILE`
Add:
`$env:PYTHONDONTWRITEBYTECODE="1"`
### Option B: create a “bootstrap” script in your workroot
Make `bootstrap.ps1` in workroot:
```PowerShell
.\.venv\Scripts\Activate.ps1 
$env:PYTHONDONTWRITEBYTECODE="1"
```
Then each session you run:
`.\bootstrap.ps1`
(Preferred because it’s explicit and doesn’t affect unrelated shells.)
*Still requires bypass execution policy.* 

---

## Quick health check (copy/paste)
```PowerShell
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
Replace C:\Path\To\Your\Repo with your real repo path.

