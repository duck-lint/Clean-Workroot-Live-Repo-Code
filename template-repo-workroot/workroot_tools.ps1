Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Workroot = $PSScriptRoot
$script:ManifestsDir = Join-Path $script:Workroot "manifests"

function global:Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )
    $base = $BasePath.TrimEnd('\','/')
    if ($FullPath.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($base.Length).TrimStart('\','/')
    }
    return $FullPath
}

function global:Get-WorkrootSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootNorm = $Root.TrimEnd('\','/')
    $excludeRoots = @(
        (Join-Path $rootNorm ".venv"),
        (Join-Path $rootNorm ".git"),
        (Join-Path $rootNorm "manifests")
    )

    $entries = @()
    $items = Get-ChildItem -LiteralPath $rootNorm -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $full = $_.FullName
        $skip = $false
        foreach ($ex in $excludeRoots) {
            if ($full.StartsWith($ex, [System.StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break }
        }
        -not $skip
    }

    foreach ($item in $items) {
        $entries += [ordered]@{
            relative_path = Get-RelativePath -BasePath $rootNorm -FullPath $item.FullName
            size_bytes    = $item.Length
            mtime_utc     = $item.LastWriteTimeUtc.ToString("o")
        }
    }

    return $entries
}

function global:Get-PythonInfo {
    try {
        $json = & python -c "import json,sys; print(json.dumps({'executable':sys.executable,'version':sys.version}))"
        if ($json) { return ($json | ConvertFrom-Json) }
    } catch {
        return $null
    }
    return $null
}

function global:Get-GitInfo {
    param([string]$RepoPath)
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
        if (-not $RepoPath) { return $null }
        $inside = & git -C $RepoPath rev-parse --is-inside-work-tree 2>$null
        if ($inside -ne "true") { return $null }

        $branch = (& git -C $RepoPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
        $commit = (& git -C $RepoPath rev-parse HEAD 2>$null).Trim()
        $status = (& git -C $RepoPath status --porcelain 2>$null)
        $dirty = $false
        if ($status) { $dirty = $true }

        return [ordered]@{
            branch   = $branch
            commit   = $commit
            is_dirty = $dirty
        }
    } catch {
        return $null
    }
}

function global:Format-CommandLine {
    param([string]$Command, [string[]]$Args)
    $parts = @()
    $parts += $Command
    if ($Args) { $parts += $Args }
    $quoted = $parts | ForEach-Object {
        $s = $_
        if ($s -match '[\s"]') { '"' + ($s -replace '"','\\"') + '"' } else { $s }
    }
    return ($quoted -join ' ')
}

function global:Invoke-WorkrootCommand {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)][string]$Command,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Args,
        [switch]$DryRun,
        [switch]$Snapshot
    )

    $workroot = $script:Workroot
    if (-not $workroot) { $workroot = (Get-Location).Path }
    $repoPath = $env:REPO

    if (-not (Test-Path -LiteralPath $workroot)) {
        throw "Workroot not found: '$workroot'"
    }

    $runId = "{0}_{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")), ([Guid]::NewGuid().ToString("N").Substring(0,6))
    $manifestPath = Join-Path $script:ManifestsDir ("run_{0}.json" -f $runId)

    if ($DryRun) {
        Write-Host "[dry-run] workroot: $workroot"
        Write-Host "[dry-run] repo:     $repoPath"
        Write-Host "[dry-run] command:  $(Format-CommandLine -Command $Command -Args $Args)"
        Write-Host "[dry-run] manifest: $manifestPath"
        if ($Snapshot) { Write-Host "[dry-run] snapshot: enabled" }
        return
    }

    if (-not (Test-Path -LiteralPath $script:ManifestsDir)) {
        New-Item -ItemType Directory -Path $script:ManifestsDir -Force | Out-Null
    }

    $startUtc = [DateTime]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $before = $null
    if ($Snapshot) { $before = Get-WorkrootSnapshot -Root $workroot }

    $runError = $null
    $success = $true
    $exitCode = 0

    Push-Location $workroot
    try {
        $global:LASTEXITCODE = 0
        & $Command @Args
        $success = $?
        if ($LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE }
        elseif (-not $success) { $exitCode = 1 }
    } catch {
        $success = $false
        $exitCode = 1
        $runError = $_.Exception.Message
    } finally {
        Pop-Location
    }

    $stopwatch.Stop()
    $endUtc = [DateTime]::UtcNow

    $after = $null
    $changes = $null
    if ($Snapshot) {
        $after = Get-WorkrootSnapshot -Root $workroot
        $beforeIndex = @{}
        foreach ($e in $before) { $beforeIndex[$e.relative_path] = $e }
        $afterIndex = @{}
        foreach ($e in $after) { $afterIndex[$e.relative_path] = $e }

        $newFiles = @()
        $modifiedFiles = @()
        $deletedFiles = @()

        foreach ($k in $afterIndex.Keys) {
            if (-not $beforeIndex.ContainsKey($k)) {
                $newFiles += $k
            } else {
                $b = $beforeIndex[$k]
                $a = $afterIndex[$k]
                if ($a.size_bytes -ne $b.size_bytes -or $a.mtime_utc -ne $b.mtime_utc) {
                    $modifiedFiles += $k
                }
            }
        }
        foreach ($k in $beforeIndex.Keys) {
            if (-not $afterIndex.ContainsKey($k)) { $deletedFiles += $k }
        }

        $changes = [ordered]@{
            new_files      = $newFiles
            modified_files = $modifiedFiles
            deleted_files  = $deletedFiles
        }
    }

    $envInfo = [ordered]@{}
    if ($env:REPO) { $envInfo.REPO = $env:REPO }
    if ($env:PYTHONDONTWRITEBYTECODE) { $envInfo.PYTHONDONTWRITEBYTECODE = $env:PYTHONDONTWRITEBYTECODE }

    $pyInfo = Get-PythonInfo
    $gitInfo = Get-GitInfo -RepoPath $repoPath

    $manifest = [ordered]@{
        run_id      = $runId
        start_utc   = $startUtc.ToString("o")
        end_utc     = $endUtc.ToString("o")
        duration_ms = [int]$stopwatch.Elapsed.TotalMilliseconds
        cwd         = $workroot
        workroot    = $workroot
        repo        = $repoPath
        command     = [ordered]@{
            command = $Command
            args    = $Args
            full    = (Format-CommandLine -Command $Command -Args $Args)
        }
        exit_code   = $exitCode
        success     = [bool]$success
        python      = $pyInfo
        git         = $gitInfo
        env         = $envInfo
    }

    if ($runError) { $manifest["error"] = $runError }
    if ($Snapshot) {
        $manifest["snapshot"] = [ordered]@{
            before  = $before
            after   = $after
            changes = $changes
        }
    }

    $json = $manifest | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $manifestPath -Value $json -Encoding UTF8

    Write-Host "Manifest: $manifestPath"
}

Set-Alias -Name wr -Value Invoke-WorkrootCommand -Scope Global

# Quick test (not executed):
#   .\boot.cmd bootstrap.ps1
#   wr python -c "print('hello')"
#   # Expect: manifests\run_<run_id>.json created in the workroot
