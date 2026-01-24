param(
    [string]$RepoPath = "",
    [switch]$NoBytecode = $true,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Workroot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkrootItem = Get-Item -LiteralPath $Workroot

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

$activate = Join-Path $Workroot ".venv\Scripts\Activate.ps1"
if (-not (Test-Path -LiteralPath $activate)) {
    throw "Venv not found at '$activate'. Create it: py -m venv .venv"
}

if ($DryRun) {
    Write-Host "[dry-run] workroot: $Workroot"
    Write-Host "[dry-run] repo:     $RepoPath"
    return
}

. $activate

if ($NoBytecode) { $env:PYTHONDONTWRITEBYTECODE = "1" }
$env:REPO = $RepoPath
Write-Host "workroot:" $Workroot
Write-Host "repo:    " $env:REPO
Write-Host ""
Write-Host "Bootstrap active. Use 'exit' to return to the previous shell."

$toolsPath = Join-Path $Workroot "workroot_tools.ps1"
if (Test-Path -LiteralPath $toolsPath) { . $toolsPath }
if (Get-Command -Name wr -ErrorAction SilentlyContinue) {
    Write-Host "Run commands with manifests using: wr <command> [args...]"
}
