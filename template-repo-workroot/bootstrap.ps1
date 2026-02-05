param(
    [string]$RepoPath = "",
    [switch]$NoBytecode = $true,
    [switch]$NoTranscript,
    [string]$TranscriptDir = "",
    [switch]$DryRun,
    [switch]$SkipRepoInstall,
    [switch]$ForceRepoInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-RepoRequirementsInstalled {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$Workroot
    )

    $reqPath = Join-Path $RepoPath "requirements.txt"
    if (-not (Test-Path -LiteralPath $reqPath)) {
        return
    }

    $stampPath = Join-Path $Workroot ".venv\.workroot_repo_requirements_stamp.json"
    $requirementsMtimeUtc = (Get-Item -LiteralPath $reqPath).LastWriteTimeUtc.ToString("o")

    $needsInstall = $false
    if (-not (Test-Path -LiteralPath $stampPath)) {
        $needsInstall = $true
    } else {
        try {
            $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
            $requiredFields = @("repo_path","requirements_mtime_utc")
            foreach ($field in $requiredFields) {
                if (-not ($stamp.PSObject.Properties.Name -contains $field)) {
                    $needsInstall = $true
                    break
                }
            }
            if (-not $needsInstall) {
                if ($stamp.repo_path -ne $RepoPath) { $needsInstall = $true }
                elseif ($stamp.requirements_mtime_utc -ne $requirementsMtimeUtc) { $needsInstall = $true }
            }
        } catch {
            $needsInstall = $true
        }
    }

    if (-not $needsInstall) { return }

    Write-Host "Installing repo requirements..."
    Invoke-WorkrootNative -Exe "python" -Args @("-m","pip","install","-r",$reqPath)
    if ($LASTEXITCODE -ne 0) { throw "pip failed installing repo requirements." }

    $stampObj = [pscustomobject]@{
        repo_path = $RepoPath
        requirements_mtime_utc = $requirementsMtimeUtc
        installed_at_utc = ([DateTime]::UtcNow.ToString("o"))
    }
    $stampObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stampPath -Encoding UTF8
    Write-Host "Repo requirements installed."
}

function Ensure-EditableRepoInstall {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$Workroot,
        [switch]$Skip,
        [switch]$Force
    )

    if ($Skip) { return }

    $pyproject = Join-Path $RepoPath "pyproject.toml"
    if (-not (Test-Path -LiteralPath $pyproject)) {
        # Not an installable package (in the modern, standard sense). Do nothing.
        return
    }

    $reqPath = Join-Path $RepoPath "requirements.txt"
    $hasReq = Test-Path -LiteralPath $reqPath

    # Stamp lives inside the venv so it resets naturally if the venv is recreated.
    $stampPath = Join-Path $Workroot ".venv\.workroot_repo_editable_stamp.json"

    # Get current pyproject "version" via LastWriteTimeUtc (good enough for “did deps/metadata change?”).
    $pyprojectMtimeUtc = (Get-Item -LiteralPath $pyproject).LastWriteTimeUtc.ToString("o")
    $requirementsMtimeUtc = $null
    if ($hasReq) {
        $requirementsMtimeUtc = (Get-Item -LiteralPath $reqPath).LastWriteTimeUtc.ToString("o")
    }
    $installMode = if ($hasReq) { "editable_no_deps" } else { "editable_with_deps" }

    $needsInstall = $Force

    if (-not $needsInstall) {
        if (-not (Test-Path -LiteralPath $stampPath)) {
            $needsInstall = $true
        } else {
            try {
                $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
                $requiredFields = @("repo_path","pyproject_mtime_utc","requirements_present","requirements_mtime_utc","install_mode")
                foreach ($field in $requiredFields) {
                    if (-not ($stamp.PSObject.Properties.Name -contains $field)) {
                        $needsInstall = $true
                        break
                    }
                }
                if (-not $needsInstall) {
                    if ($stamp.repo_path -ne $RepoPath) { $needsInstall = $true }
                    elseif ($stamp.pyproject_mtime_utc -ne $pyprojectMtimeUtc) { $needsInstall = $true }
                    elseif ([bool]$stamp.requirements_present -ne $hasReq) { $needsInstall = $true }
                    elseif ($hasReq -and $stamp.requirements_mtime_utc -ne $requirementsMtimeUtc) { $needsInstall = $true }
                    elseif ($stamp.install_mode -ne $installMode) { $needsInstall = $true }
                }
            } catch {
                # Corrupt/old stamp? Just reinstall.
                $needsInstall = $true
            }
        }
    }

    if (-not $needsInstall) {
        Write-Host "Repo editable install: OK (stamp present, unchanged)"
        return
    }

    if ($hasReq) {
        Write-Host "Repo editable install: running pip install -e --no-deps ..."
        Invoke-WorkrootNative -Exe "python" -Args @("-m","pip","install","-e",$RepoPath,"--no-deps")
    } else {
        Write-Host "Repo editable install: running pip install -e ..."
        Invoke-WorkrootNative -Exe "python" -Args @("-m","pip","install","-e",$RepoPath)
    }
    if ($LASTEXITCODE -ne 0) { throw "pip install -e failed for repo: $RepoPath" }

    $stampObj = [pscustomobject]@{
        repo_path = $RepoPath
        pyproject_mtime_utc = $pyprojectMtimeUtc
        requirements_present = $hasReq
        requirements_mtime_utc = $requirementsMtimeUtc
        install_mode = $installMode
        installed_at_utc = ([DateTime]::UtcNow.ToString("o"))
    }
    $stampObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stampPath -Encoding UTF8
    Write-Host "Repo editable install: DONE (stamp updated)"
}

function Invoke-WorkrootNative {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Args,
        [switch]$CaptureText
    )
    $convertOutput = {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ }
    }
    if ($CaptureText) {
        $prevErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = $null
        try {
            $output = & $Exe @Args 2>&1 | ForEach-Object $convertOutput
            if ($output) { $output | Out-Host }
        } finally {
            $ErrorActionPreference = $prevErrorAction
        }
        if ($null -eq $output) { return "" }
        return ($output | Out-String).TrimEnd()
    }

    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Exe @Args 2>&1 | ForEach-Object $convertOutput | Out-Host
    } finally {
        $ErrorActionPreference = $prevErrorAction
    }
    return $null
}

function Get-NormalizedPythonVersion {
    param(
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $m = [regex]::Match($Value, "\d+\.\d+")
    if (-not $m.Success) { return "" }
    return $m.Value
}

function Get-PreferredPythonFromSpecifier {
    param(
        [string]$Specifier
    )
    if ([string]::IsNullOrWhiteSpace($Specifier)) { return "" }
    $patterns = @(
        "==\s*([0-9]+\.[0-9]+)",
        "~=\s*([0-9]+\.[0-9]+)",
        ">=\s*([0-9]+\.[0-9]+)",
        ">\s*([0-9]+\.[0-9]+)"
    )
    foreach ($pat in $patterns) {
        $m = [regex]::Match($Specifier, $pat)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return ""
}

function Get-RepoPythonVersion {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath
    )
    $override = Get-NormalizedPythonVersion -Value $env:WORKROOT_PY_VERSION
    if ($override) { return $override }

    $pyverPath = Join-Path $RepoPath ".python-version"
    if (Test-Path -LiteralPath $pyverPath) {
        $raw = (Get-Content -LiteralPath $pyverPath -Raw).Trim()
        $ver = Get-NormalizedPythonVersion -Value $raw
        if ($ver) { return $ver }
    }

    $pyproject = Join-Path $RepoPath "pyproject.toml"
    if (Test-Path -LiteralPath $pyproject) {
        $content = Get-Content -LiteralPath $pyproject -Raw
        $m = [regex]::Match($content, '(?m)^\s*requires-python\s*=\s*[''"]([^''"]+)[''"]')
        if ($m.Success) {
            $spec = $m.Groups[1].Value
            $ver = Get-PreferredPythonFromSpecifier -Specifier $spec
            if ($ver) { return $ver }
        }
    }

    return ""
}

function Start-WorkrootTranscript {
    param(
        [Parameter(Mandatory = $true)][string]$WorkrootPath,
        [switch]$NoTranscript,
        [string]$TranscriptDir
    )
    if ($NoTranscript) { return }
    $transcriptVar = Get-Variable -Name WorkrootTranscriptActive -Scope Global -ErrorAction SilentlyContinue
    if ($transcriptVar -and $transcriptVar.Value) { return }

    if ([string]::IsNullOrWhiteSpace($TranscriptDir)) {
        $TranscriptDir = Join-Path $WorkrootPath "_workroot_transcripts"
    }

    if (-not (Test-Path -LiteralPath $TranscriptDir)) {
        New-Item -ItemType Directory -Path $TranscriptDir -Force | Out-Null
    }

    $stamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
    $shortId = ([Guid]::NewGuid().ToString("N").Substring(0,6))
    $path = Join-Path $TranscriptDir ("session_{0}_{1}.log" -f $stamp, $shortId)

    try {
        Start-Transcript -Path $path -Append -ErrorAction Stop | Out-Null
        $global:WorkrootTranscriptActive = $true
        $global:WorkrootTranscriptPath = $path
        Write-Host "Transcript: $path"
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "transcrib" -and $msg -match "progress|already") {
            $global:WorkrootTranscriptActive = $true
        } else {
            Write-Warning ("Transcript failed: {0}" -f $msg)
        }
    }

    $exitVar = Get-Variable -Name WorkrootTranscriptExitRegistered -Scope Global -ErrorAction SilentlyContinue
    if (-not ($exitVar -and $exitVar.Value)) {
        Register-EngineEvent PowerShell.Exiting -Action { try { Stop-Transcript | Out-Null } catch {} } | Out-Null
        $global:WorkrootTranscriptExitRegistered = $true
    }
}

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
    throw "Venv not found at '$activate'. Create it: .\boot.cmd init.ps1"
}

if ($DryRun) {
    Write-Host "[dry-run] workroot: $Workroot"
    Write-Host "[dry-run] repo:     $RepoPath"
    return
}

. $activate

if ($NoBytecode) { $env:PYTHONDONTWRITEBYTECODE = "1" }
$env:REPO = $RepoPath
$PreferredPythonVersion = Get-RepoPythonVersion -RepoPath $RepoPath
if ($PreferredPythonVersion) {
    $pyVersion = Invoke-WorkrootNative -Exe "python" -Args @("-c","import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") -CaptureText
    if ($pyVersion -and ($pyVersion -ne $PreferredPythonVersion)) {
        throw ("Venv Python {0} does not match required {1}. Delete .venv and rerun init." -f $pyVersion, $PreferredPythonVersion)
    }
}
Start-WorkrootTranscript -WorkrootPath $Workroot -NoTranscript:$NoTranscript -TranscriptDir $TranscriptDir
Ensure-RepoRequirementsInstalled -RepoPath $env:REPO -Workroot $Workroot
Ensure-EditableRepoInstall -RepoPath $env:REPO -Workroot $Workroot -Skip:$SkipRepoInstall -Force:$ForceRepoInstall
Write-Host "workroot:" $Workroot
Write-Host "repo:    " $env:REPO
Write-Host ""
Write-Host "Bootstrap active. Use 'exit' to return to the previous shell."

$toolsPath = Join-Path $Workroot "workroot_tools.ps1"
if (Test-Path -LiteralPath $toolsPath) { . $toolsPath }
if (Get-Command -Name wr -ErrorAction SilentlyContinue) {
    Write-Host "Run commands with manifests using: wr <command> [args...]"
}
