### Goal
- a **clean working directory** (“workroot”) where outputs land (`stage_0_raw`, `stage_1_clean`, etc.)
- a separate **git repo** where your pipeline scripts live (kept clean for commits)
- Python able to import repo modules (`common.py`, etc.) while running from the workroot
- no `__pycache__` clutter in the repo

This workflow accomplishes that by:
1. keeping the current directory as the “output root”
2. telling the venv’s Python to import code from the repo via a `.pth` file
3. optionally disabling bytecode writes in the session

---

## Definitions
- **workroot**: the folder you stand in when running commands; contains `.venv` and your generated outputs
- **repo**: the git directory containing the pipeline scripts
- **bytecode**: the files that end up in the `__pycache__` dir

Example:
- workroot: `C:\path\to\workroot`
- repo: `C:\path\to\Git_repo`

---

## Step 0 — Create / activate the (.venv) in your workroot

From workroot:
```
py -V:3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python --version
```
Python .venv specific to cuda/pytorch build as of January 2026. Install requirements as necessary.

---

## Step 1 — Make the venv import modules from the repo (the `.pth` trick)

A `.pth` file placed in **site-packages** adds a directory to Python’s import path _for that venv_.
### 1.1 Get the venv site-packages path
While the venv is activated:
`$site = python -c "import site; print(site.getsitepackages()[0])" $site`
### 1.2 Write a `.pth` file pointing to your repo
Set the repo path, then write it:
`$REPO = "C:\Path\To\Your\Repo" Set-Content -Path (Join-Path $site "pipeline_repo.pth") -Value $REPO`
### 1.3 Verify it worked
`python -c "import common; print(common.__file__)"`
You should see a path pointing inside your repo.
✅ After this, the venv will always “see” your repo code until the venv is **deleted**.

---

## Step 2 — Optional: prevent `__pycache__` from being created
This stops Python from writing `.pyc` bytecode files (and thus avoids `__pycache__`).
For the current terminal session:
`$env:PYTHONDONTWRITEBYTECODE = "1"`
Verify:
`python -c "import sys; print(sys.dont_write_bytecode)"`
**Important:** this is session-only unless you make it persistent (see below).

---

## Step 3 — Run repo scripts while outputs land in the workroot
Because you’re standing in the workroot, relative paths resolve “at your feet.”
Example:
```PowerShell
python "$REPO\init_folders.py" --root .

python "$REPO\00_stage0_copy_raw.py" --input_path "C:\Path\To\Vault" --stage0_dir stage_0_raw

python "$REPO\01_stage1_clean.py" --stage0_path stage_0_raw --stage1_dir stage_1_clean --yaml_mode lenient

python "$REPO\02_stage2_chunk.py" --stage0_path stage_0_raw --stage1_dir stage_1_clean --out_dir stage_2_chunks --prefer_stage1 --yaml_mode lenient

python "$REPO\merge_chunks_jsonl.py" --chunks_dir stage_2_chunks --output_jsonl stage_2_chunks_merged.jsonl

python "$REPO\03_stage3_build_chroma.py" --chunks_jsonl stage_2_chunks_merged.jsonl --persist_dir stage_3_chroma --collection v1_chunks --mode upsert --device auto
```
All folders like `stage_0_raw/` are created in the workroot, not the repo.

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
