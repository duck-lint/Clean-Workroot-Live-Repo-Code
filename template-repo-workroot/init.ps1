param(
    [string]$RepoPath = "",
    [string]$PthName = "repo.pth",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load the same repo-derivation logic by calling bootstrap in DryRun mode is tempting,
# but bootstrap activates the venv; we want to ensure venv is active here too.
# So: activate venv and derive repo in the same way.

$Workroot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkrootItem = Get-Item -LiteralPath $Workroot

$venvDir = Join-Path $Workroot ".venv"
$activate = Join-Path $Workroot ".venv\Scripts\Activate.ps1"

if (-not (Test-Path -LiteralPath $activate)) {
    Write-Host "No venv found. Creating .venv in workroot..."
    py -m venv $venvDir
}

. $activate

$env:PYTHONDONTWRITEBYTECODE = "1"

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $leaf = $WorkrootItem.Name
    if ($leaf -notlike "*-workroot") {
        throw "Expected workroot folder name to end with '-workroot'. Got: '$leaf'. Pass -RepoPath or rename the folder."
    }
    $repoName = $leaf.Substring(0, $leaf.Length - "-workroot".Length)
    $RepoPath = Join-Path -Path $WorkrootItem.Parent.FullName -ChildPath $repoName
}

if (-not (Test-Path -LiteralPath $RepoPath)) {
    throw "Repo path does not exist: '$RepoPath'. Create it or pass -RepoPath."
}
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Repo path is not a folder: '$RepoPath'. Pass -RepoPath to a directory or rename the workroot."
}

$site = python -c "import site; print(site.getsitepackages()[0])"
$pthPath = Join-Path $site $PthName

if ($DryRun) {
    Write-Host "[dry-run] repo: $RepoPath"
    Write-Host "[dry-run] site-packages: $site"
    Write-Host "[dry-run] would write: $pthPath"
    return
}

Set-Content -Path $pthPath -Value $RepoPath -Encoding UTF8
Write-Host "Wrote .pth:" $pthPath
Write-Host "Repo path :" $RepoPath

# Verify: you need SOME importable module in the repo (e.g., repo_marker.py)
try {
    python -c "import repo_marker; print('repo_marker:', repo_marker.__file__)"
    Write-Host "Import test: OK"
} catch {
    Write-Warning "Import test failed. Ensure 'repo_marker.py' exists in the repo root (or adjust the test import)."
    throw
}

$toolsPath = Join-Path $Workroot "workroot_tools.ps1"
if (Test-Path -LiteralPath $toolsPath) { . $toolsPath }
if (Get-Command -Name wr -ErrorAction SilentlyContinue) {
    Write-Host "Run commands with manifests using: wr <command> [args...]"
}

